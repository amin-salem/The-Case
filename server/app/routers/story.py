"""Story mode: the career map. Chapters are played with the normal case endpoints (/v1/cases/s01ch01/...);
this router decides which chapter a player may open: free, by warrant, by waiting 12 hours, or for coins."""
from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import economy as eco
from ..db import get_session
from ..models import CaseProgress, Player, StoryProgress, utcnow
from ..schemas import StoryChapterOut, StoryOpenIn, StoryOut
from ..security import current_player
from ..util import add_coins, ts

router = APIRouter(prefix="/v1/story", tags=["story"])
WAIT = timedelta(hours=eco.STORY_WAIT_HOURS)


async def finish(session: AsyncSession, player_id: str, case_id: str, p: CaseProgress) -> None:
    """Called when a story chapter's case is solved or lost: remember it on the career map."""
    m = content.STORY_ID.match(case_id)
    if not m:
        return
    sp = await session.scalar(select(StoryProgress).where(
        StoryProgress.player_id == player_id, StoryProgress.season == int(m.group(1)),
        StoryProgress.chapter == int(m.group(2))))
    if sp is not None:
        sp.finished_at, sp.solved, sp.stars = p.finished_at or utcnow(), bool(p.solved), p.stars if p.solved else 0


def story_extra(c: content.Case, p: CaseProgress | None) -> dict:
    """The partner's lines of a chapter: the intro always, the outro and the season thread once it is finished."""
    d = c.data
    out = {"season": d["season"], "chapter": d["chapter"], "intro": d["partner_intro"]}
    if p is not None and (p.solved or p.failed):
        out["outro"] = d["partner_outro_win"] if p.solved else d["partner_outro_lose"]
        out["thread"] = d["thread"]
    return out


def _state(n: int, rows: dict[int, StoryProgress], now):
    """(state, unlock time when waiting) of chapter n."""
    sp = rows.get(n)
    if sp is not None:
        return ("done" if sp.finished_at else "open"), None
    if n > 1:
        prev = rows.get(n - 1)
        if prev is None or prev.finished_at is None:
            return "locked", None
        if n > eco.STORY_FREE_CHAPTERS:
            at = prev.finished_at + WAIT
            if now < at:
                return "waiting", at
    return "ready", None


async def _rows(session: AsyncSession, player: Player) -> dict[int, StoryProgress]:
    return {r.chapter: r for r in (await session.execute(select(StoryProgress).where(
        StoryProgress.player_id == player.id, StoryProgress.season == content.STORY_SEASON["season"]))).scalars()}


async def _out(session: AsyncSession, player: Player, case_id: str | None = None) -> StoryOut:
    rows = await _rows(session, player)
    now = utcnow()
    out, next_at = [], None
    for c in content.story_chapters():
        n = c.number
        state, at = _state(n, rows, now)
        sp = rows.get(n)
        row = StoryChapterOut(chapter=n, id=c.id, state=state, solved=bool(sp and sp.solved),
                              stars=sp.stars if sp else 0)
        if state != "locked":
            row.title, row.location, row.scene = c.data["title"], c.data["location"], c.data["scene"]
        if state == "waiting":
            row.unlock_at = ts(at)
            row.skip_cost = eco.story_skip_cost((at - now).total_seconds())
            row.can_warrant = (player.warrants or 0) > 0
            next_at = next_at or row.unlock_at
        out.append(row)
    s = content.STORY_SEASON
    return StoryOut(open=content.story_open(), opens_at=int(content.story_opens_at().timestamp()),
                    season=s["season"], title=s["title"], tagline=s["tagline"], partner=s["partner"],
                    warrants=player.warrants or 0, coins=player.coins, free_chapters=eco.STORY_FREE_CHAPTERS,
                    wait_hours=eco.STORY_WAIT_HOURS, next_open_at=next_at, chapters=out, case_id=case_id)


@router.get("", response_model=StoryOut)
async def story(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    return await _out(session, player)


async def _begin(session: AsyncSession, player: Player, c: content.Case) -> None:
    now = utcnow()
    session.add(StoryProgress(player_id=player.id, season=c.data["season"], chapter=c.number, opened_at=now))
    if await session.scalar(select(CaseProgress.id).where(
            CaseProgress.player_id == player.id, CaseProgress.case_id == c.id)) is None:
        session.add(CaseProgress(player_id=player.id, case_id=c.id, opened_at=now))


async def _prepare(session: AsyncSession, player: Player, chapter: int):
    """Checks shared by open and skip. Returns (case, state, unlock time) or raises."""
    if not content.story_open():
        raise HTTPException(409, "story_not_open")
    chapters = content.story_chapters()
    if not 1 <= chapter <= len(chapters):
        raise HTTPException(404, "no_chapter")
    state, at = _state(chapter, await _rows(session, player), utcnow())
    if state == "locked":
        raise HTTPException(409, "wrong_order")
    return chapters[chapter - 1], state, at


@router.post("/{chapter}/open", response_model=StoryOut)
async def open_chapter(chapter: int, body: StoryOpenIn | None = None, player: Player = Depends(current_player),
                       session: AsyncSession = Depends(get_session)):
    """Opens a chapter that is free or whose wait is over. A waiting chapter opens with `warrant: true`
    (one warrant is spent); without it the answer is 409 `wait`. Opening an open chapter does nothing."""
    c, state, _ = await _prepare(session, player, chapter)
    if state == "waiting":
        if not (body and body.warrant):
            raise HTTPException(409, "wait")
        if (player.warrants or 0) < 1:
            raise HTTPException(409, "no_warrant")
        player.warrants -= 1
    if state in ("ready", "waiting"):
        await _begin(session, player, c)
        await session.commit()
    return await _out(session, player, c.id)


@router.post("/{chapter}/skip", response_model=StoryOut)
async def skip_wait(chapter: int, player: Player = Depends(current_player),
                    session: AsyncSession = Depends(get_session)):
    """Pays coins to open a waiting chapter now (the price falls as the 12 hours run down)."""
    c, state, at = await _prepare(session, player, chapter)
    if state == "waiting":
        cost = eco.story_skip_cost((at - utcnow()).total_seconds())
        if player.coins < cost:
            raise HTTPException(402, {"error": "not_enough_coins", "need": cost})
        add_coins(session, player, -cost, f"story_skip:{c.id}")
    if state in ("ready", "waiting"):
        await _begin(session, player, c)
        await session.commit()
    return await _out(session, player, c.id)
