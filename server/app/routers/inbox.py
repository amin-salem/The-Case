"""Gift inbox (admin/event gifts) and invite codes."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import economy as eco
from ..db import get_session
from ..models import Broadcast, BroadcastClaim, InboxItem, Player, utcnow
from ..schemas import ClaimOut, InboxRow, RedeemIn
from ..security import current_player
from ..util import add_coins, from_ts, ts

router = APIRouter(prefix="/v1", tags=["inbox"])


def apply_grants(session: AsyncSession, player: Player, grants: list[dict], reason: str) -> None:
    for g in grants:
        if g.get("type") == "coins":
            add_coins(session, player, int(g["amount"]), reason)
        elif g.get("type") == "no_ads":
            player.no_ads = True
        elif g.get("type") == "vip_until":
            until = from_ts(int(g["ts"]))
            if player.vip_until is None or until > player.vip_until:
                player.vip_until = until


@router.get("/inbox", response_model=list[InboxRow])
async def inbox(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
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
        apply_grants(session, player, item.grants, f"gift:{item.id}")
        await session.commit()
        return ClaimOut(grants=item.grants, coins=player.coins)
    b = await session.get(Broadcast, num)
    if b is None:
        raise HTTPException(404, "no_item")
    if b.expires_at is not None and b.expires_at < now:
        raise HTTPException(410, "expired")
    session.add(BroadcastClaim(broadcast_id=b.id, player_id=player.id))
    apply_grants(session, player, b.grants, f"broadcast:{b.id}")
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "already_claimed")
    return ClaimOut(grants=b.grants, coins=player.coins)


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
    player.referred_by = inviter.id
    if inviter.invites_rewarded < eco.MAX_REWARDED_INVITES:
        inviter.invites_rewarded += 1
        session.add(InboxItem(player_id=inviter.id, title="یه کارآگاه تازه با کد تو اومد!",
                              message=f"{player.nickname} با کد دعوت تو وارد شد.",
                              grants=[{"type": "coins", "amount": eco.INVITE_INVITER}], source="referral"))
    grants = [{"type": "coins", "amount": eco.INVITE_NEW_PLAYER}]
    apply_grants(session, player, grants, "invited")
    await session.commit()
    return ClaimOut(grants=grants, coins=player.coins)
