"""Profile, daily login calendar, streak insurance and rewarded ads."""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from .. import economy as eco
from ..db import get_session
from ..models import Player
from ..schemas import CoinsOut, ProfileIn, ProfileOut
from ..security import current_player
from ..util import add_coins, clean_nickname
from .common import profile_out

router = APIRouter(prefix="/v1", tags=["profile"])


@router.get("/me", response_model=ProfileOut)
async def me(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Also gives the once-a-day login reward: a 7-day calendar that grows each day in a row."""
    today = content.today_str()
    reward = 0
    if player.last_login_reward != today:
        yesterday = (date.fromisoformat(today) - timedelta(days=1)).isoformat()
        in_a_row = player.last_login_reward == yesterday
        player.login_day = (player.login_day or 0) % 7 + 1 if in_a_row else 1
        player.last_login_reward = today
        reward = eco.login_reward(player.login_day)
        add_coins(session, player, reward, f"daily_login:{player.login_day}")
        await session.commit()
    return profile_out(player, login_reward=reward)


@router.post("/wallet/streak-freeze", response_model=ProfileOut)
async def buy_streak_freeze(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Streak insurance: if a daily case is missed, one is spent and the streak survives."""
    if (player.streak_freezes or 0) >= eco.MAX_FREEZES:
        raise HTTPException(409, "max_freezes")
    if player.coins < eco.FREEZE_COST:
        raise HTTPException(402, {"error": "not_enough_coins", "need": eco.FREEZE_COST})
    add_coins(session, player, -eco.FREEZE_COST, "streak_freeze")
    player.streak_freezes = (player.streak_freezes or 0) + 1
    await session.commit()
    return profile_out(player)


@router.patch("/me", response_model=ProfileOut)
async def update_me(body: ProfileIn, player: Player = Depends(current_player),
                    session: AsyncSession = Depends(get_session)):
    if body.nickname is not None:
        name = clean_nickname(body.nickname)
        if name is None:
            raise HTTPException(422, "bad_nickname")
        player.nickname = name
    if body.avatar is not None:
        player.avatar = body.avatar
    await session.commit()
    return profile_out(player)


@router.post("/wallet/ad-reward", response_model=CoinsOut)
async def ad_reward(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The app calls this after a rewarded ad was watched (limited per day)."""
    today = content.today_str()
    if player.ad_day != today:
        player.ad_day, player.ad_count = today, 0
    if player.ad_count >= eco.AD_PER_DAY:
        raise HTTPException(429, "ad_limit")
    player.ad_count += 1
    add_coins(session, player, eco.AD_REWARD, "ad")
    await session.commit()
    return CoinsOut(coins=player.coins, added=eco.AD_REWARD)
