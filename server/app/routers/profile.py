"""Profile, daily login calendar, streak insurance and rewarded ads."""
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import avatars, content, feed, progress, purge, streakrepair
from .. import economy as eco
from ..config import get_settings
from ..db import get_session, lock_players
from ..models import Player, StreakRepair, utcnow
from ..schemas import ClientInfoIn, CoinsOut, GainsOut, ProfileIn, ProfileOut
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
        await add_coins(session, player, reward, f"daily_login:{player.login_day}")
        gains = await progress.record(session, player, full_week=int(player.login_day == 7))
        await session.commit()
    else:
        # achievements earned elsewhere (secured account, invites) or added later are granted here
        gains = progress.Gains()
        await progress.check_achievements(session, player, gains)
        if gains.achievements:
            await session.commit()
    out = profile_out(player, login_reward=reward)
    try:
        out.unread = await feed.unread_count(session, player)
    except Exception:  # the bell must never break the profile
        await session.rollback()
    out.gains = GainsOut(**gains.out()) if not gains.is_empty() else None
    return out


@router.post("/me/delete")
async def delete_me(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Deletes the account and its progress for good (stores require an in-app way to do this)."""
    # every row of the player in every table (coin log, invite payouts, weekly league rows too), so the public
    # «delete account» page is true (21 Oct 2026); one transaction
    await purge.purge_players(session, [player.id])
    await session.commit()
    return {"deleted": True}


@router.post("/wallet/streak-freeze", response_model=ProfileOut)
async def buy_streak_freeze(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Streak insurance: if a daily case is missed, one is spent and the streak survives."""
    if (player.streak_freezes or 0) >= eco.MAX_FREEZES:
        raise HTTPException(409, "max_freezes")
    if player.coins < eco.FREEZE_COST:
        raise HTTPException(402, {"error": "not_enough_coins", "need": eco.FREEZE_COST})
    await add_coins(session, player, -eco.FREEZE_COST, "streak_freeze")
    player.streak_freezes = (player.streak_freezes or 0) + 1
    await session.commit()
    return profile_out(player)


@router.post("/wallet/streak-repair", response_model=ProfileOut)
async def repair_streak(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Mends a streak that broke within the last 24 h (the player missed exactly one daily case). The server decides
    whether the player is eligible (app/streakrepair.py); one transaction under the player lock plus a UNIQUE row per
    break, so a double tap or two workers charge once. The repair counts the missed night as bridged: tonight's case
    then continues the streak (it does not add a night). Rate limit: the strict «wallet» policy (/v1/wallet/*)."""
    if not get_settings().streak_repair_enabled:
        streakrepair.log_decision("disabled")
        raise HTTPException(403, "repair_disabled")
    player = (await lock_players(session, [player.id]))[player.id]
    offer = streakrepair.repair_offer(player)
    if offer is None:
        streakrepair.log_decision("not_eligible", player.streak or 0)
        raise HTTPException(409, "not_eligible")
    price = offer["price"]
    if player.coins < price:
        streakrepair.log_decision("not_enough_coins", offer["streak"], price)
        raise HTTPException(402, {"error": "not_enough_coins", "need": price})
    await add_coins(session, player, -price, "streak_repair")
    player.last_daily_solved = offer["bridge"]
    player.streak_repair_mark = offer["bridge"]
    session.add(StreakRepair(player_id=player.id, broken_after=offer["key"], streak=offer["streak"], price=price))
    try:
        await session.flush()
    except IntegrityError:  # this break was repaired already: undo the charge as well
        await session.rollback()
        streakrepair.log_decision("already_repaired", offer["streak"], price)
        raise HTTPException(409, "not_eligible")
    await session.commit()
    streakrepair.log_decision("repaired", offer["streak"], price)
    return profile_out(player)


@router.patch("/me", response_model=ProfileOut)
async def update_me(body: ProfileIn, player: Player = Depends(current_player),
                    session: AsyncSession = Depends(get_session)):
    if body.nickname is not None:
        name = clean_nickname(body.nickname)
        if name is None:
            raise HTTPException(422, "bad_nickname")
        player.nickname = name
    if body.avatar is not None:  # old apps: the portrait index
        player.avatar = body.avatar
        player.avatar_id = ""
    owned = None
    for kind, value in (("avatar", body.avatar_id), ("frame", body.avatar_frame)):
        if value is None:
            continue
        item = avatars.BY_ID.get(value)
        if item is None or item.kind != kind:
            raise HTTPException(422, "not_owned")
        if item.how != "free":
            owned = owned if owned is not None else await avatars.owned_rows(session, player)
            if (kind, value) not in owned:
                raise HTTPException(422, "not_owned")
        if kind == "avatar":
            player.avatar_id = value
        else:
            player.avatar_frame = value
    await session.commit()
    return profile_out(player)


@router.delete("/me/smoke")
async def delete_smoke_player(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Only for the throw-away test players made by tools/smoke_test.py (device id «smoke-…»): removes the player and
    everything that belongs to it. Any other account is refused, so a real player can never be deleted here."""
    if not purge.is_smoke(player.device_id):
        raise HTTPException(403, "not_a_test_player")
    n = await purge.purge_players(session, [player.id])
    await session.commit()
    return {"deleted": n}


@router.post("/me/client")
async def report_client(body: ClientInfoIn, player: Player = Depends(current_player),
                        session: AsyncSession = Depends(get_session)):
    """The app reports its version and device once per start (rate limited by the «client_info» policy)."""
    player.client_version = body.app_version.strip()
    player.client_build = body.build
    player.platform = body.platform
    player.os_version = body.os_version.strip()
    player.device_model = body.device_model.strip()
    player.client_at = utcnow()
    await session.commit()
    return {"ok": True}


@router.post("/wallet/ad-reward", response_model=CoinsOut)
async def ad_reward(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The app calls this after a rewarded ad was watched (limited per day)."""
    if not get_settings().ads_enabled:
        raise HTTPException(403, "ads_off")
    today = content.today_str()
    if player.ad_day != today:
        player.ad_day, player.ad_count = today, 0
    if player.ad_count >= eco.AD_PER_DAY:
        raise HTTPException(429, "ad_limit")
    player.ad_count += 1
    await add_coins(session, player, eco.AD_REWARD, "ad")
    await session.commit()
    return CoinsOut(coins=player.coins, added=eco.AD_REWARD)
