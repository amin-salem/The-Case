"""Leaderboards: today's case (fastest with most stars), this week (stars), all time (stars)."""
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from ..db import get_session
from ..models import CaseProgress, Player
from ..schemas import LeaderboardOut, LeaderRow
from ..security import current_player
from .common import rank_title

router = APIRouter(prefix="/v1", tags=["leaderboard"])


@router.get("/leaderboard", response_model=LeaderboardOut)
async def leaderboard(period: str = Query("daily", pattern="^(daily|weekly|all)$"),
                      limit: int = Query(50, ge=1, le=100),
                      player: Player = Depends(current_player),
                      session: AsyncSession = Depends(get_session)):
    visible = Player.banned.is_(False)
    if period == "daily":
        c = content.todays_case()
        if c is None:
            raise HTTPException(404, "no_case")
        q = (select(Player, CaseProgress.stars, CaseProgress.seconds)
             .join(CaseProgress, CaseProgress.player_id == Player.id)
             .where(CaseProgress.case_id == c.id, CaseProgress.solved.is_(True),
                    CaseProgress.was_daily.is_(True), visible)
             .order_by(CaseProgress.stars.desc(), CaseProgress.seconds.asc()))
        rows = (await session.execute(q)).all()
        out = [LeaderRow(rank=i + 1, nickname=pl.nickname, avatar=pl.avatar, value=secs, stars=st,
                         me=pl.id == player.id, rank_title=rank_title(pl)) for i, (pl, st, secs) in enumerate(rows)]
        title = f"پرونده‌ی امروز: {c.data['title']}"
    elif period == "weekly":
        start = content.week_start(date.fromisoformat(content.today_str())).isoformat()
        total = func.sum(CaseProgress.stars).label("total")
        q = (select(Player, total).join(CaseProgress, CaseProgress.player_id == Player.id)
             .where(CaseProgress.solved.is_(True), CaseProgress.day >= start, visible)
             .group_by(Player.id).order_by(total.desc()))
        rows = (await session.execute(q)).all()
        out = [LeaderRow(rank=i + 1, nickname=pl.nickname, avatar=pl.avatar, value=int(t), stars=int(t),
                         me=pl.id == player.id, rank_title=rank_title(pl)) for i, (pl, t) in enumerate(rows)]
        title = "این هفته"
    else:
        q = (select(Player).where(visible, Player.stars_total > 0)
             .order_by(Player.stars_total.desc(), Player.cases_solved.desc()))
        rows = (await session.execute(q)).scalars().all()
        out = [LeaderRow(rank=i + 1, nickname=pl.nickname, avatar=pl.avatar, value=pl.stars_total,
                         stars=pl.stars_total, me=pl.id == player.id, rank_title=rank_title(pl)) for i, pl in enumerate(rows)]
        title = "همه‌ی زمان‌ها"
    me = next((r for r in out if r.me), None)
    return LeaderboardOut(period=period, title=title, top=out[:limit], me=me)
