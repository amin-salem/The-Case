"""Real-money purchases: the app sends the Bazaar purchase token; the server
checks it with Bazaar and adds coins / perks to the server wallet."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import economy as eco
from ..db import get_session
from ..models import Player, Purchase
from ..schemas import VerifyIn, VerifyOut
from ..security import current_player
from ..services.bazaar import BazaarClient, get_bazaar
from ..util import add_coins, from_ts, ts
from .common import vip_active

router = APIRouter(prefix="/v1/purchases", tags=["purchases"])


def _out(player: Player, status: str, added: int = 0, consume: bool = False, reason: str = "") -> VerifyOut:
    return VerifyOut(status=status, reason=reason, coins=player.coins, added=added,
                     no_ads=player.no_ads or vip_active(player), vip_until=ts(player.vip_until), consume=consume)


@router.post("/verify", response_model=VerifyOut)
async def verify(body: VerifyIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session),
                 bazaar: BazaarClient = Depends(get_bazaar)):
    prod = eco.PRODUCTS.get(body.product_id)
    if prod is None:
        raise HTTPException(422, "unknown_product")
    consume = prod.kind == "consumable"
    existing = await session.scalar(select(Purchase).where(Purchase.purchase_token == body.purchase_token))
    if existing is not None and existing.player_id != player.id:
        return _out(player, "rejected", reason="token_used")
    if existing is not None and existing.product_id != body.product_id:
        return _out(player, "rejected", reason="wrong_product")
    if existing is not None and existing.status == "granted" and prod.kind != "subscription":
        return _out(player, "already_granted", consume=consume)

    check = (await bazaar.check_subscription(body.product_id, body.purchase_token) if prod.kind == "subscription"
             else await bazaar.check_inapp(body.product_id, body.purchase_token))
    if check.reason.startswith("bazaar_unreachable"):
        raise HTTPException(503, "bazaar_unreachable_try_later")
    if not check.valid:
        if existing is None:
            existing = Purchase(player_id=player.id, product_id=body.product_id,
                                purchase_token=body.purchase_token, status="rejected")
            session.add(existing)
        existing.status = "refunded" if check.refunded else "rejected"
        existing.raw = check.raw
        await session.commit()
        return _out(player, "rejected", reason=check.reason or "invalid")

    renewal = existing is not None and existing.status == "granted"
    added = 0
    grants: list[dict] = []
    if not renewal:
        if prod.coins:
            added = prod.coins
            add_coins(session, player, added, f"buy:{prod.id}")
            grants.append({"type": "coins", "amount": added})
        if prod.no_ads:
            player.no_ads = True
            grants.append({"type": "no_ads"})
    if prod.kind == "subscription" and check.valid_until_ms:
        until = from_ts(check.valid_until_ms // 1000)
        if player.vip_until is None or until > player.vip_until:
            player.vip_until = until
        grants.append({"type": "vip_until", "ts": ts(player.vip_until)})
    if existing is None:
        existing = Purchase(player_id=player.id, product_id=body.product_id,
                            purchase_token=body.purchase_token, status="granted")
        session.add(existing)
    existing.status, existing.grants, existing.raw = "granted", grants, check.raw
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        return _out(player, "already_granted", consume=consume)
    return _out(player, "granted", added=added, consume=consume)
