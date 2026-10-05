"""Real-money purchases: the app sends the store's purchase token (Myket or Bazaar); the server
checks it with that store and adds coins / perks to the server wallet."""
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import economy as eco
from ..db import get_session
from ..config import get_settings
from ..models import Player, Purchase, utcnow
from ..schemas import VerifyIn, VerifyOut
from ..security import current_player
from ..services.bazaar import BazaarClient, PurchaseCheck, get_bazaar
from ..services.myket import MyketClient, get_myket
from ..util import add_coins, from_ts, ts
from .common import vip_active

router = APIRouter(prefix="/v1/purchases", tags=["purchases"])


def _out(player: Player, status: str, added: int = 0, consume: bool = False, reason: str = "") -> VerifyOut:
    return VerifyOut(status=status, reason=reason, coins=player.coins, added=added,
                     no_ads=player.no_ads or vip_active(player), vip_until=ts(player.vip_until), consume=consume)


@router.post("/verify", response_model=VerifyOut)
async def verify(body: VerifyIn, player: Player = Depends(current_player),
                 session: AsyncSession = Depends(get_session),
                 bazaar: BazaarClient = Depends(get_bazaar), myket: MyketClient = Depends(get_myket)):
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

    if body.store == "myket":
        check = await myket.check_inapp(body.product_id, body.purchase_token, payload=player.id)
    elif get_settings().env == "prod" and get_settings().bazaar_mode == "fake":
        check = PurchaseCheck(valid=False, reason="store_not_configured")  # never accept test tokens in production
    else:
        check = (await bazaar.check_subscription(body.product_id, body.purchase_token) if prod.kind == "subscription"
                 else await bazaar.check_inapp(body.product_id, body.purchase_token))
    if check.reason.startswith(("bazaar_unreachable", "store_unreachable")):
        raise HTTPException(503, "store_unreachable_try_later")
    if check.valid and check.consumed and existing is None and body.store == "myket":
        # already used up in the store but unknown here (e.g. the account was deleted): never grant twice
        check = PurchaseCheck(valid=False, reason="already_consumed", raw=check.raw)
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
        if prod.vip_days:
            start = player.vip_until if player.vip_until and player.vip_until > utcnow() else utcnow()
            player.vip_until = start + timedelta(days=prod.vip_days)
            grants.append({"type": "vip_until", "ts": ts(player.vip_until)})
    if prod.kind == "subscription" and check.valid_until_ms:
        until = from_ts(check.valid_until_ms // 1000)
        if player.vip_until is None or until > player.vip_until:
            player.vip_until = until
        grants.append({"type": "vip_until", "ts": ts(player.vip_until)})
    if existing is None:
        existing = Purchase(player_id=player.id, product_id=body.product_id,
                            purchase_token=body.purchase_token, status="granted")
        session.add(existing)
    existing.status, existing.grants, existing.raw = "granted", grants, {**check.raw, "store": body.store}
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        await session.refresh(player)
        return _out(player, "already_granted", consume=consume)
    return _out(player, "granted", added=added, consume=consume)
