"""Leaderboards: today's case (fastest with most stars), this week (stars of the week's own cases, per league), all time."""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import anticheat as ac
from .. import avatars, content, gameclock, streakrepair, weekboard
from ..db import get_session
from ..models import CaseProgress, Player
from ..schemas import LeagueInfo, LeaderboardOut, LeaderRow
from ..security import current_player
from .common import rank_title

router = APIRouter(prefix="/v1", tags=["leaderboard"])


@router.get("/leaderboard", response_model=LeaderboardOut)
async def leaderboard(period: str = Query("daily", pattern="^(daily|weekly|all)$"),
                      limit: int = Query(50, ge=1, le=100),
                      league: int | None = Query(None, ge=0, le=3),
                      player: Player = Depends(current_player),
                      session: AsyncSession = Depends(get_session)):
    visible = ac.visible_player()
    live = streakrepair.LiveStreak()  # the flame: one lookup per row, no extra query
    if period == "daily":
        c = content.todays_case()
        if c is None:
            raise HTTPException(404, "no_case")
        q = (select(Player, CaseProgress.stars, CaseProgress.seconds)
             .join(CaseProgress, CaseProgress.player_id == Player.id)
             .where(CaseProgress.case_id == c.id, CaseProgress.solved.is_(True),
                    CaseProgress.was_daily.is_(True), CaseProgress.ranked.is_(True), visible)
             .order_by(CaseProgress.stars.desc(), CaseProgress.seconds.asc()))
        rows = (await session.execute(q)).all()
        out = [LeaderRow(rank=i + 1, nickname=pl.nickname, avatar=pl.avatar, avatar_id=avatars.avatar_key(pl), avatar_frame=avatars.frame_key(pl), streak=live.of(pl), value=secs, stars=st,
                         me=pl.id == player.id, rank_title=rank_title(pl)) for i, (pl, st, secs) in enumerate(rows)]
        title = f"پرونده‌ی امروز: {c.data['title']}"
    elif period == "weekly":
        return await _weekly(player, league, limit, session, live)
    else:
        q = (select(Player).where(visible, Player.stars_total > 0)
             .order_by(Player.stars_total.desc(), Player.cases_solved.desc()))
        rows = (await session.execute(q)).scalars().all()
        out = [LeaderRow(rank=i + 1, nickname=pl.nickname, avatar=pl.avatar, avatar_id=avatars.avatar_key(pl), avatar_frame=avatars.frame_key(pl), streak=live.of(pl), value=pl.stars_total,
                         stars=pl.stars_total, me=pl.id == player.id, rank_title=rank_title(pl)) for i, pl in enumerate(rows)]
        title = "همه‌ی زمان‌ها"
    me = next((r for r in out if r.me), None)
    return LeaderboardOut(period=period, title=title, top=out[:limit], me=me)


async def _weekly(player: Player, league: int | None, limit: int, session: AsyncSession,
                  live: streakrepair.LiveStreak) -> LeaderboardOut:
    """The week's own cases only (weekboard.py has the rule); one league at a time, the player's own by default."""
    ws = gameclock.week_of(content.now_local())
    on = weekboard.leagues_on()
    mine = await weekboard.league_of(session, ws, player.id) if on else None
    shown = (league if league is not None else mine) if on else None
    rows = await weekboard.cached_rows(session, ws, shown, limit)
    out = [LeaderRow(rank=i + 1, nickname=r["nickname"], avatar=r["avatar"], avatar_id=r["avatar_id"],
                     avatar_frame=r["avatar_frame"], streak=r.get("streak", 0), value=r["points"], stars=r["points"], me=r["id"] == player.id,
                     rank_title=r["rank_title"]) for i, r in enumerate(rows)]
    me = next((r for r in out if r.me), None)
    if me is None and (shown is None or shown == mine):
        st = await weekboard.my_standing(session, ws, player, shown)
        if st is not None and ac.is_visible(player):
            me = LeaderRow(rank=st[0], nickname=player.nickname, avatar=player.avatar, avatar_id=avatars.avatar_key(player),
                           avatar_frame=avatars.frame_key(player), streak=live.of(player), value=st[1], stars=st[1], me=True, rank_title=rank_title(player))
    title = "این هفته" + (f" · لیگ {weekboard.LEAGUES[shown]}" if shown is not None else "")
    return LeaderboardOut(period="weekly", title=title, top=out, me=me, week_ends_at=int(gameclock.week_end(ws).timestamp()),
                          league=shown, my_league=mine,
                          leagues=[LeagueInfo(id=i, name=n) for i, n in enumerate(weekboard.LEAGUES)] if on else [])
