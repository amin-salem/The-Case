"""Avatars and frames: the catalog with what the player owns, and the coin shop."""
import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from .. import avatars, progress
from ..db import get_session
from ..models import CoinLog, Player
from ..schemas import GainsOut
from ..security import current_player

log = logging.getLogger("avatars")
router = APIRouter(prefix="/v1/avatars", tags=["avatars"])


async def _view(session: AsyncSession, player: Player, gains: progress.Gains | None = None) -> dict:
    out = avatars.catalog(player, await avatars.owned_rows(session, player), await avatars.story_chapter_done(session, player))
    if gains is not None and not gains.is_empty():
        out["gains"] = GainsOut(**gains.out()).model_dump()
    return out


@router.get("")
async def list_avatars(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Everything, with owned / locked / price and the progress toward each goal. Goals reached are unlocked here too."""
    gains = progress.Gains()
    await avatars.check_goals(session, player, gains)
    if gains.avatars:
        await session.commit()
    return await _view(session, player, gains)


@router.post("/{item_id}/buy")
async def buy(item_id: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Buys a shop avatar or frame once. The ownership row is written first (unique), so two requests at once
    can never pay twice; the coins are taken with a guarded UPDATE, so the wallet can never go below zero."""
    item = avatars.BY_ID.get(item_id)
    if item is None:
        raise HTTPException(404, "unknown_item")
    if item.how != "shop":
        raise HTTPException(422, "not_for_sale")
    if player.coins < item.price:
        raise HTTPException(402, {"error": "not_enough_coins", "need": item.price})
    if not await avatars.grant(session, player, item, "shop"):
        await session.rollback()
        raise HTTPException(409, "already_owned")
    res = await session.execute(update(Player).where(Player.id == player.id, Player.coins >= item.price)
                                .values(coins=Player.coins - item.price))
    if not res.rowcount:
        await session.rollback()
        raise HTTPException(402, {"error": "not_enough_coins", "need": item.price})
    await session.refresh(player)
    session.add(CoinLog(player_id=player.id, amount=-item.price, reason=f"avatar:{item.id}"[:48], balance=player.coins))
    await session.commit()
    log.info("avatar bought item=%s price=%s", item.id, item.price)
    return await _view(session, player)
