"""Profile, daily login reward and rewarded ads."""
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
    """Also gives the once-a-day login reward."""
    today = content.today_str()
    reward = 0
    if player.last_login_reward != today:
        player.last_login_reward = today
        reward = eco.LOGIN_REWARD
        add_coins(session, player, reward, "daily_login")
        await session.commit()
    return profile_out(player, login_reward=reward)


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
