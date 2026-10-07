"""Achievements: every badge with the player's progress toward it."""
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import achievements, missions
from ..db import get_session
from ..models import Player, PlayerAchievement
from ..schemas import AchievementRow, AchievementsOut
from ..security import current_player
from ..util import ts

router = APIRouter(prefix="/v1/achievements", tags=["achievements"])


@router.get("", response_model=AchievementsOut)
async def list_achievements(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    earned = dict((await session.execute(select(PlayerAchievement.achievement_id, PlayerAchievement.at).where(
        PlayerAchievement.player_id == player.id))).all())
    items = [AchievementRow(id=a.id, title=a.title, desc=a.desc, group=a.group, target=a.target,
                            progress=min(a.target, a.value(player)), earned=a.id in earned,
                            earned_at=ts(earned.get(a.id)), coins=a.coins, xp=a.xp) for a in achievements.ALL
                            if missions.RIDDLES_ON or a.group != "riddles"]
    return AchievementsOut(earned=sum(1 for i in items if i.earned), total=len(items), items=items)
