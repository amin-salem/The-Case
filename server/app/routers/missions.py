"""Daily missions: today's three, and the chest when all are done."""
from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content, missions, progress
from .. import economy as eco
from ..db import get_session
from ..models import MissionDay, Player
from ..schemas import ChestOut, GainsOut, MissionRow, MissionsOut
from ..security import current_player
from ..util import add_coins

router = APIRouter(prefix="/v1/missions", tags=["missions"])


def chest_coins(player: Player, day: str) -> int:
    """Today's chest; every CHEST_BONUS_EVERY-th day in a row adds a bonus."""
    streak = _streak_if_opened(player, day)
    return eco.CHEST_COINS + (eco.CHEST_BONUS if streak % eco.CHEST_BONUS_EVERY == 0 else 0)


def _streak_if_opened(player: Player, day: str) -> int:
    if player.last_chest_day == day:
        return player.chest_streak
    yesterday = (date.fromisoformat(day) - timedelta(days=1)).isoformat()
    return (player.chest_streak + 1) if player.last_chest_day == yesterday else 1


def missions_out(player: Player, md: MissionDay | None, day: str) -> MissionsOut:
    counts = (md.counts if md else None) or {}
    rows = [MissionRow(id=m.id, title=m.title, target=m.target, progress=min(m.target, int(counts.get(m.event, 0))),
                       done=int(counts.get(m.event, 0)) >= m.target) for m in missions.for_day(day)]
    now = content.now_local()
    next_at = int(datetime.combine(now.date() + timedelta(days=1), time(0), tzinfo=now.tzinfo).timestamp())
    shown_streak = player.chest_streak if player.last_chest_day in (
        day, (date.fromisoformat(day) - timedelta(days=1)).isoformat()) else 0
    return MissionsOut(day=day, missions=rows, all_done=all(r.done for r in rows), claimed=bool(md and md.claimed),
                       chest_coins=chest_coins(player, day), chest_streak=shown_streak, next_at=next_at,
                       coins=player.coins)


@router.get("", response_model=MissionsOut)
async def today(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    day = content.today_str()
    md = await progress.mission_day(session, player, day, create=False)
    return missions_out(player, md, day)


@router.post("/claim", response_model=ChestOut)
async def claim(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    day = content.today_str()
    md = await progress.mission_day(session, player, day, create=False)
    out = missions_out(player, md, day)
    if md is None or not out.all_done:
        raise HTTPException(409, "missions_not_done")
    if md.claimed:
        raise HTTPException(409, "already_claimed")
    reward = chest_coins(player, day)
    player.chest_streak = _streak_if_opened(player, day)
    player.last_chest_day = day
    player.chests = (player.chests or 0) + 1
    md.claimed = True
    progress.set_stat_max(player, "best_chest_streak", player.chest_streak)
    add_coins(session, player, reward, f"chest:{day}")
    gains = await progress.record(session, player, xp=eco.XP_CHEST, chest=1)
    await session.commit()
    return ChestOut(missions=missions_out(player, md, day), reward=reward, gains=GainsOut(**gains.out()))
