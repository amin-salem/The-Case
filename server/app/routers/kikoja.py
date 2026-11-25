"""«کی کجا؟» endpoints (rules in app/kikoja.py): three levels a day (easy free, medium and hard opened with coins), a new set
every day at 09:00 Tehran. Visible only when the remote config `kikoja` says so: to testers (Amin, 25 Nov 2026) or to everybody. Every change is made under the player's row lock, so two taps never pay twice,
count a mistake twice or give the reward twice. The answer never leaves before the puzzle is solved."""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import kikoja
from ..db import get_session, lock_players
from ..models import KikojaRun, Player, utcnow
from ..security import current_player
from ..services.remote_config import load_config
from ..util import add_coins

router = APIRouter(prefix="/v1/kikoja", tags=["kikoja"])
LEVEL = Path(pattern="^(easy|medium|hard)$")
log = logging.getLogger("kikoja")


class HintIn(BaseModel):
    kind: str = Field(pattern="^(time|pair)$")


class AccuseIn(BaseModel):
    who: int = Field(ge=0, le=15)
    lie: str = Field(min_length=1, max_length=8)
    con: str = Field(min_length=1, max_length=8)
    wit: list[str] = Field(default_factory=list, max_length=2)
    secs: int = Field(default=0, ge=0, le=10 * 3600)


async def _setup(session: AsyncSession, player: Player, level: str) -> dict:
    """The level's puzzle of today or a 404 the app reads as «no game for you»."""
    cfg = kikoja.config(await load_config(session))
    p = kikoja.today_puzzle(level)
    if p is None or not kikoja.visible(cfg, player):
        raise HTTPException(404, {"error": "no_kikoja"})
    return p


async def _run(session: AsyncSession, player: Player, pid: str, create: bool) -> KikojaRun | None:
    row = await session.scalar(select(KikojaRun).where(KikojaRun.player_id == player.id, KikojaRun.puzzle_id == pid))
    if row is None and create:
        row = KikojaRun(player_id=player.id, puzzle_id=pid, hints=[], proof=[])
        session.add(row)
        await session.flush()
    return row


def _open(level: str, row: KikojaRun | None) -> bool:
    """A free level is always open; a paid one only after its coins were taken (row.unlocked)."""
    return kikoja.price_of(level) == 0 or bool(row and row.unlocked)


def _need_open(level: str, row: KikojaRun) -> None:
    if not _open(level, row):
        raise HTTPException(403, {"error": "locked"})


def _meta(level: str, p: dict, row: KikojaRun | None) -> dict:
    """What every tile shows, locked or not: the house, how many suspects and hours, the price and how it went."""
    mistakes = row.mistakes if row else 0
    solved = bool(row and row.solved)
    return {"level": level, "id": p["id"], "title": p["title"], "house": p["house"], "n": p["n"], "T": p["T"],
            "target": p["target"], "price": kikoja.price_of(level), "open": _open(level, row), "solved": solved,
            "failed": mistakes >= kikoja.MAX_MISTAKES and not solved, "stars": row.stars if row else 0,
            "reward": kikoja.REWARD if level in kikoja.REWARD_LEVELS else 0}


def _answer(player: Player, level: str, p: dict, row: KikojaRun | None) -> dict:
    mistakes = row.mistakes if row else 0
    hints = list(row.hints or []) if row else []
    meta = _meta(level, p, row)
    out = {"visible": True, "coins": player.coins, "prices": kikoja.PRICES, "max_mistakes": kikoja.MAX_MISTAKES,
           "next_at": kikoja.next_open().isoformat(), **meta}
    if not meta["open"]:
        return out                      # a locked level shows only its tile: the statements stay on the server
    out |= {"puzzle": kikoja.public(p),
            "run": {"mistakes": mistakes, "hints": hints, "reopened": bool(row and row.reopened),
                    "solved": meta["solved"], "failed": meta["failed"], "stars": meta["stars"],
                    "secs": row.secs if row else 0, "paid": row.reward if row else 0},
            "hint_data": kikoja.hint_data(p, hints)}
    if row and row.solved:
        out["reveal"] = kikoja.reveal(p, list(row.proof or []))
    return out


@router.get("")
async def get_kikoja(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The three tiles of today (no statements): the app's home card and the unlock sheet read this."""
    cfg = kikoja.config(await load_config(session))
    if not kikoja.visible(cfg, player):
        return {"visible": False}
    levels = []
    for lv in kikoja.LEVELS:
        p = kikoja.today_puzzle(lv)
        if p is not None:
            levels.append(_meta(lv, p, await _run(session, player, p["id"], create=False)))
    if not levels:
        return {"visible": False}
    return {"visible": True, "coins": player.coins, "next_at": kikoja.next_open().isoformat(), "levels": levels}


@router.get("/{level}")
async def get_level(level: str = LEVEL, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    p = await _setup(session, player, level)
    return _answer(player, level, p, await _run(session, player, p["id"], create=False))


@router.post("/{level}/unlock")
async def unlock(level: str = LEVEL, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Opens a paid level for today: the coins are taken once (a second tap, a retry or a race never pays twice)."""
    p = await _setup(session, player, level)
    await lock_players(session, [player.id])
    row = await _run(session, player, p["id"], create=True)
    if not row.unlocked:
        price = kikoja.price_of(level)
        if price:
            await add_coins(session, player, -price, "kikoja_unlock")
        row.unlocked, row.updated_at = True, utcnow()
        log.info("kikoja unlock player=%s puzzle=%s level=%s price=%s", player.id[:6], p["id"], level, price)
    await session.commit()
    return _answer(player, level, p, row)


@router.post("/{level}/hint")
async def hint(body: HintIn, level: str = LEVEL, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Buys a hint once per puzzle; asking again for a bought hint is free (a reload never pays twice)."""
    p = await _setup(session, player, level)
    await lock_players(session, [player.id])
    row = await _run(session, player, p["id"], create=True)
    _need_open(level, row)
    if row.solved or row.mistakes >= kikoja.MAX_MISTAKES:
        raise HTTPException(409, {"error": "closed"})
    hints = list(row.hints or [])
    if body.kind not in hints:
        await add_coins(session, player, -int(kikoja.PRICES[body.kind]), "kikoja_hint")
        row.hints, row.updated_at = [*hints, body.kind], utcnow()
        log.info("kikoja hint player=%s puzzle=%s kind=%s", player.id[:6], p["id"], body.kind)
    await session.commit()
    return _answer(player, level, p, row)


@router.post("/{level}/accuse")
async def accuse(body: AccuseIn, level: str = LEVEL, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The accusation: the thief, his false statement, the statement that contradicts it and, when the contradiction alone does not
    clear the other speaker, the witness statements. A wrong one costs a mistake and says which step to redo."""
    p = await _setup(session, player, level)
    await lock_players(session, [player.id])
    row = await _run(session, player, p["id"], create=True)
    _need_open(level, row)
    if row.solved:
        raise HTTPException(409, {"error": "already_solved"})
    if row.mistakes >= kikoja.MAX_MISTAKES:
        raise HTTPException(409, {"error": "failed"})
    step = kikoja.judge(p, body.who, body.lie, body.con, body.wit)
    if step is not None:
        row.mistakes, row.updated_at = row.mistakes + 1, utcnow()
        await session.commit()
        log.info("kikoja wrong player=%s puzzle=%s step=%s mistakes=%s", player.id[:6], p["id"], step, row.mistakes)
        return _answer(player, level, p, row) | {"ok": False, "step": step}
    row.solved, row.proof, row.secs = True, [body.lie, body.con, sorted(set(body.wit))], min(body.secs, kikoja.MAX_SECS)
    row.stars = kikoja.stars_for(row.mistakes, list(row.hints or []), row.reopened)
    paid = 0
    if row.stars == 3 and not row.reopened and row.reward == 0 and level in kikoja.REWARD_LEVELS:
        paid = kikoja.REWARD
        row.reward = paid
        await add_coins(session, player, paid, "kikoja_win")
    row.updated_at = utcnow()
    await session.commit()
    log.info("kikoja solved player=%s puzzle=%s level=%s stars=%s paid=%s", player.id[:6], p["id"], level, row.stars, paid)
    return _answer(player, level, p, row) | {"ok": True}


@router.post("/{level}/reopen")
async def reopen(level: str = LEVEL, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """After three mistakes: opens the file again for coins (one star at most, no reward)."""
    p = await _setup(session, player, level)
    await lock_players(session, [player.id])
    row = await _run(session, player, p["id"], create=True)
    _need_open(level, row)
    if row.solved or row.mistakes < kikoja.MAX_MISTAKES:
        raise HTTPException(409, {"error": "not_failed"})
    await add_coins(session, player, -int(kikoja.PRICES["reopen"]), "kikoja_reopen")
    row.mistakes, row.reopened, row.updated_at = 0, True, utcnow()
    await session.commit()
    log.info("kikoja reopen player=%s puzzle=%s", player.id[:6], p["id"])
    return _answer(player, level, p, row)
