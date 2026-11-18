"""«شکار سه‌روزه» endpoints (rules in app/hunt.py). Visible only when the remote config `hunt` says so: to testers
(the owner's test, Amin 18 Nov 2026) or to everybody. Every change is made under the player's row lock, so two taps never
pay twice or accuse twice."""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import hunt
from ..db import get_session, lock_players
from ..models import HuntState, Player, utcnow
from ..security import current_player
from ..services.remote_config import load_config
from ..util import add_coins

router = APIRouter(prefix="/v1/hunt", tags=["hunt"])
log = logging.getLogger("hunt")


class HoldIn(BaseModel):
    suspect: str = Field(min_length=1, max_length=16)


class AccuseIn(BaseModel):
    suspect: str = Field(min_length=1, max_length=16)
    evidence: str = Field(min_length=1, max_length=16)


async def _setup(session: AsyncSession, player: Player):
    """(hunt content, cleaned config) or a 404 the app reads as «no hunt for you»."""
    cfg = hunt.config(await load_config(session))
    h = hunt.load(cfg["id"])
    if h is None or cfg["starts_at"] is None or not hunt.visible(cfg, player):
        raise HTTPException(404, {"error": "no_hunt"})
    return h, cfg


async def collective(session: AsyncSession, hunt_id: str) -> dict:
    players = await session.scalar(select(func.count(HuntState.id)).where(HuntState.hunt_id == hunt_id)) or 0
    solved = await session.scalar(select(func.count(HuntState.id)).where(
        HuntState.hunt_id == hunt_id, HuntState.solved.is_(True))) or 0
    return {"players": players, "solved": solved, "pct": round(100 * solved / players) if players else 0}


async def _row(session: AsyncSession, player: Player, hunt_id: str, create: bool) -> HuntState | None:
    row = await session.scalar(select(HuntState).where(HuntState.player_id == player.id, HuntState.hunt_id == hunt_id))
    if row is None and create:
        row = HuntState(player_id=player.id, hunt_id=hunt_id, holds={}, early=[])
        session.add(row)
        await session.flush()
    return row


def _live_minute(h: dict, cfg: dict) -> int:
    minute = hunt.minute_at(cfg, hunt.now_epoch())
    if minute < 0:
        raise HTTPException(409, {"error": "not_started"})
    if minute >= int(h["duration_minutes"]):
        raise HTTPException(409, {"error": "hunt_over"})
    return minute


async def _answer(session: AsyncSession, player: Player, h: dict, cfg: dict, row) -> dict:
    return hunt.state(h, cfg, row, player.coins, await collective(session, h["id"]))


@router.get("")
async def get_hunt(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    try:
        h, cfg = await _setup(session, player)
    except HTTPException:
        return {"visible": False}
    row = None
    if hunt.minute_at(cfg, hunt.now_epoch()) >= 0:
        # joining counts the detective in the collective share; a race between two first loads hits the unique key
        row = await _row(session, player, h["id"], create=False)
        if row is None:
            await lock_players(session, [player.id])
            row = await _row(session, player, h["id"], create=True)
            await session.commit()
    return await _answer(session, player, h, cfg, row)


@router.post("/hold")
async def hold(body: HoldIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """«منع خروج»: the suspect stays `hold_minutes` longer. Once per suspect, not for one who left, not after accusing."""
    h, cfg = await _setup(session, player)
    await lock_players(session, [player.id])
    row = await _row(session, player, h["id"], create=True)
    minute = _live_minute(h, cfg)
    s = next((x for x in h["suspects"] if x["id"] == body.suspect), None)
    if s is None or s.get("leave") is None:
        raise HTTPException(404, {"error": "no_suspect"})
    holds = dict(row.holds or {})
    if row.accused:
        raise HTTPException(409, {"error": "already_accused"})
    if hunt.is_gone(h, s, holds, None, minute):
        raise HTTPException(409, {"error": "gone"})
    if holds.get(s["id"], 0) >= 1:
        raise HTTPException(409, {"error": "already_held"})
    await add_coins(session, player, -int(h["prices"]["hold"]), "hunt_hold")
    holds[s["id"]] = holds.get(s["id"], 0) + 1
    row.holds, row.updated_at = holds, utcnow()
    await session.commit()
    log.info("hunt hold player=%s hunt=%s suspect=%s", player.id[:6], h["id"], s["id"])
    return await _answer(session, player, h, cfg, row)


@router.post("/early")
async def early(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Opens the next closed evidence drop now, for coins."""
    h, cfg = await _setup(session, player)
    await lock_players(session, [player.id])
    row = await _row(session, player, h["id"], create=True)
    minute = _live_minute(h, cfg)
    d = hunt.next_closed_drop(h, list(row.early or []), minute)
    if d is None:
        raise HTTPException(409, {"error": "nothing_left"})
    await add_coins(session, player, -int(h["prices"]["early"]), "hunt_early")
    row.early, row.updated_at = [*(row.early or []), d["id"]], utcnow()
    await session.commit()
    log.info("hunt early player=%s hunt=%s drop=%s", player.id[:6], h["id"], d["id"])
    return await _answer(session, player, h, cfg, row)


@router.post("/accuse")
async def accuse(body: AccuseIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The one accusation: a suspect still in town and a piece of evidence the player can see."""
    h, cfg = await _setup(session, player)
    await lock_players(session, [player.id])
    row = await _row(session, player, h["id"], create=True)
    minute = _live_minute(h, cfg)
    if row.accused:
        raise HTTPException(409, {"error": "already_accused"})
    s = next((x for x in h["suspects"] if x["id"] == body.suspect), None)
    if s is None:
        raise HTTPException(404, {"error": "no_suspect"})
    early = list(row.early or [])
    if hunt.is_gone(h, s, dict(row.holds or {}), None, minute):
        raise HTTPException(409, {"error": "gone"})
    if body.evidence not in hunt.unlocked_items(h, early, minute):
        raise HTTPException(409, {"error": "no_evidence"})
    stars = hunt.stars_for(h, s["id"], body.evidence, early, minute)
    row.accused, row.evidence, row.accused_minute = s["id"], body.evidence, minute
    row.solved, row.stars, row.updated_at = stars > 0, stars, utcnow()
    reward = int(h["rewards"].get(str(stars), 0)) if stars else 0
    if reward:
        await add_coins(session, player, reward, "hunt_win")
    await session.commit()
    log.info("hunt accuse player=%s hunt=%s solved=%s stars=%s", player.id[:6], h["id"], stars > 0, stars)
    return await _answer(session, player, h, cfg, row) | {"reward": reward}
