"""Gift inbox (admin/event gifts) and invite codes."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import distinct, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import economy as eco
from .. import feed as feedmod
from .. import rewards
from ..db import get_session
from ..models import Broadcast, BroadcastClaim, CaseProgress, InboxItem, Player, utcnow
from ..schemas import ClaimOut, FeedOut, InboxRow, RedeemIn, ReferralStatusOut
from ..security import current_player
from ..util import add_coins, from_ts, ts
from .common import fast_json

router = APIRouter(prefix="/v1", tags=["inbox"])


async def apply_grants(session: AsyncSession, player: Player, grants: list[dict], reason: str) -> None:
    for g in grants:
        if g.get("type") == "coins":
            await add_coins(session, player, int(g["amount"]), reason)
        elif g.get("type") == "no_ads":
            player.no_ads = True
        elif g.get("type") == "vip_until":
            until = from_ts(int(g["ts"]))
            if player.vip_until is None or until > player.vip_until:
                player.vip_until = until


@router.get("/feed", response_model=FeedOut)
async def feed(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """One merged list for the messages hub: at most 40 items from the last 14 days, newest first."""
    items = await feedmod.build_feed(session, player)
    return fast_json(FeedOut(items=items, unread=sum(1 for i in items if i["unread"]), seen_at=ts(player.feed_seen_at)))


@router.post("/feed/seen", response_model=FeedOut)
async def feed_seen(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Marks everything up to now as read. Safe to repeat."""
    player.feed_seen_at = utcnow()
    await session.commit()
    items = await feedmod.build_feed(session, player)
    return FeedOut(items=items, unread=sum(1 for i in items if i["unread"]), seen_at=ts(player.feed_seen_at))


@router.get("/inbox", response_model=list[InboxRow])
async def inbox(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    try:
        await rewards.settle_last_week(session)  # pays last week's top players once
    except Exception:
        await session.rollback()
    now = utcnow()
    personal = (await session.execute(select(InboxItem).where(
        InboxItem.player_id == player.id, InboxItem.claimed_at.is_(None),
        or_(InboxItem.expires_at.is_(None), InboxItem.expires_at > now)).order_by(InboxItem.id.desc()).limit(50))).scalars().all()
    claimed = select(BroadcastClaim.broadcast_id).where(BroadcastClaim.player_id == player.id)
    shared = (await session.execute(select(Broadcast).where(
        Broadcast.id.not_in(claimed), or_(Broadcast.expires_at.is_(None), Broadcast.expires_at > now))
        .order_by(Broadcast.id.desc()).limit(20))).scalars().all()
    rows = [InboxRow(id=f"p{i.id}", title=i.title, message=i.message, grants=i.grants, expires_at=ts(i.expires_at))
            for i in personal]
    rows += [InboxRow(id=f"b{b.id}", title=b.title, message=b.message, grants=b.grants, expires_at=ts(b.expires_at))
             for b in shared]
    return rows


@router.post("/inbox/{item_id}/claim", response_model=ClaimOut)
async def claim(item_id: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    now = utcnow()
    if len(item_id) < 2 or item_id[0] not in "pb" or not item_id[1:].isdigit():
        raise HTTPException(404, "no_item")
    num = int(item_id[1:])
    if item_id[0] == "p":
        item = await session.get(InboxItem, num)
        if item is None or item.player_id != player.id:
            raise HTTPException(404, "no_item")
        if item.claimed_at is not None:
            raise HTTPException(409, "already_claimed")
        if item.expires_at is not None and item.expires_at < now:
            raise HTTPException(410, "expired")
        item.claimed_at = now
        await apply_grants(session, player, item.grants, f"gift:{item.id}")
        await session.commit()
        return ClaimOut(grants=item.grants, coins=player.coins)
    b = await session.get(Broadcast, num)
    if b is None:
        raise HTTPException(404, "no_item")
    if b.expires_at is not None and b.expires_at < now:
        raise HTTPException(410, "expired")
    session.add(BroadcastClaim(broadcast_id=b.id, player_id=player.id))
    await apply_grants(session, player, b.grants, f"broadcast:{b.id}")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "already_claimed")
    return ClaimOut(grants=b.grants, coins=player.coins)


async def _solve_days(session: AsyncSession, ids: list[str]) -> dict[str, int]:
    """player id -> on how many different days the player solved a case (the rule maybe_pay_referral applies)."""
    if not ids:
        return {}
    rows = (await session.execute(select(CaseProgress.player_id, func.count(distinct(CaseProgress.day))).where(
        CaseProgress.player_id.in_(ids), CaseProgress.solved.is_(True), CaseProgress.day != "")
        .group_by(CaseProgress.player_id))).all()
    return {pid: int(n) for pid, n in rows}


@router.get("/referrals/status", response_model=ReferralStatusOut)
async def referral_status(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """The invite card: whether a code can still be entered, my own progress as an invited player, and how far
    the friends I invited are (bounded: the 50 newest)."""
    need = eco.INVITE_MIN_DAYS
    referred = player.referred_by is not None
    out = ReferralStatusOut(referred=referred, can_redeem=(not referred and (utcnow() - player.created_at).days <= 7),
                            new_player_reward=eco.INVITE_NEW_PLAYER, inviter_reward=eco.INVITE_INVITER, need_days=need,
                            max_paid=eco.MAX_REWARDED_INVITES, invited_paid=player.invites_rewarded)
    if referred:
        out.my_days = min(need, (await _solve_days(session, [player.id])).get(player.id, 0))
        out.my_inviter_paid = bool(player.referral_paid)
    friends = (await session.execute(select(Player.id, Player.referral_paid).where(Player.referred_by == player.id)
                                     .order_by(Player.created_at.desc()).limit(50))).all()
    out.invited = len(friends)
    open_ids = [pid for pid, paid in friends if not paid]
    if open_ids:
        out.best_days = min(need, max((await _solve_days(session, open_ids)).values(), default=0))
    return out


@router.post("/referrals/redeem", response_model=ClaimOut)
async def redeem(body: RedeemIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    code = body.code.strip().upper()
    if player.referred_by is not None:
        raise HTTPException(409, "already_redeemed")
    if (utcnow() - player.created_at).days > 7:
        raise HTTPException(410, "only_for_new_players")
    inviter = await session.scalar(select(Player).where(Player.invite_code == code))
    if inviter is None or inviter.id == player.id:
        raise HTTPException(404, "bad_code")
    if inviter.device_id == player.device_id or inviter.referred_by == player.id:
        raise HTTPException(409, "same_device")
    player.referred_by = inviter.id  # the inviter is paid later, see anticheat.maybe_pay_referral
    grants = [{"type": "coins", "amount": eco.INVITE_NEW_PLAYER}]
    await apply_grants(session, player, grants, "invited")
    await session.commit()
    return ClaimOut(grants=grants, coins=player.coins)
