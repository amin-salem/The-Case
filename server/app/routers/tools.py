"""Detective tools on the case screen: the tray (GET) and use / buy (POST). Logic and rules: app/tools.py."""
import logging

from fastapi import APIRouter, Body, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content, tools
from ..config import get_settings
from ..db import get_session
from ..models import CaseProgress, CaseToolUse, Player
from ..security import current_player
from ..util import add_coins
from .cases import _can_open, _opened_case, _progress

router = APIRouter(prefix="/v1/cases", tags=["tools"])
log = logging.getLogger("tools")


def _daily(c) -> bool:
    """Tools work on daily and weekend cases (not on story chapters). The name stays for the payload key `daily`."""
    return not content.is_story(c.id)


def _scope(c) -> tuple[set[str] | None, set[str] | None, int]:
    """(visible card ids, visible suspect ids, night number). Daily cases see everything; a weekend case only what its
    open chapters show, so a tool never answers about a card or suspect the player cannot see yet."""
    if not content.is_weekly(c.id):
        return None, None, 1
    now = content.now_local()
    start, hidden = content.opens_at(c), set()
    for ch in c.data["chapters"]:
        if start + content.timedelta(hours=ch.get("at_hours", 0)) > now:
            hidden |= set(ch.get("evidence", []))
    cards = {e["id"] for e in c.data["evidence"] if e["id"] not in hidden}
    return cards, content.visible_suspect_ids(c, now), max(1, content.chapters_open(c, now))


async def _uses(session: AsyncSession, player_id: str, case_id: str) -> dict[str, CaseToolUse]:
    rows = (await session.scalars(select(CaseToolUse).where(
        CaseToolUse.player_id == player_id, CaseToolUse.case_id == case_id))).all()
    return {r.kind: r for r in rows}


async def _view(session: AsyncSession, player: Player, c, p: CaseProgress | None) -> dict:
    """The tray for one case: prices, stock, what is usable here, and the pinned results."""
    on = get_settings().detective_tools_enabled
    out = {"enabled": on, "daily": _daily(c), "coins": player.coins, "case_id": c.id, "tools": [],
           "message": None if on else "ابزارهای کارآگاهی فعلاً بسته‌ست."}
    if not _daily(c):
        out["enabled"], out["message"] = False, tools.NOT_FOR_MODE
        return out
    if not on:
        return out
    cards, vis, night = _scope(c)
    inv, uses, avail = await tools.stock(session, player.id), await _uses(session, player.id, c.id), tools.availability(c.data, cards, vis)
    out["night"], out["how"] = night, tools.how_to()
    out["earlier"] = [{"kind": u.kind.split("@")[0], **u.result} for k, u in uses.items() if k != tools.slot(k.split("@")[0], night)]
    playing = bool(p and not p.solved and not p.failed)
    for kind in tools.KINDS:
        use = uses.get(tools.slot(kind, night))
        out["tools"].append({
            "kind": kind, "title": tools.INFO[kind]["title"], "desc": tools.INFO[kind]["desc"], "price": tools.price(kind),
            "count": inv[kind]["count"], "free_available": not inv[kind]["free_used"],
            "available": avail[kind]["available"], "suspects": avail[kind]["suspects"],
            "used": use is not None, "usable": playing and avail[kind]["available"] and use is None,
            "result": use.result if use else None,
        })
    return out


@router.get("/{case_id}/tools")
async def tray(case_id: str, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    c = _opened_case(case_id, player)
    p = await _progress(session, player.id, c.id)
    return await _view(session, player, c, p)


async def _apply(case_id: str, kind: str, body: dict, player: Player, session: AsyncSession, buy: bool) -> dict:
    s = get_settings()
    if not s.detective_tools_enabled:
        raise HTTPException(503, "tools_disabled")
    if kind not in tools.KINDS:
        raise HTTPException(404, "unknown_tool")
    c = _opened_case(case_id, player)
    if not _daily(c):
        raise HTTPException(409, "tools_not_for_this_case")
    p = await _progress(session, player.id, c.id)
    if p is None or not _can_open(c, p, player):
        raise HTTPException(409, "open_case_first")
    if p.solved or p.failed:
        raise HTTPException(409, "case_finished")
    suspect = body.get("suspect") if isinstance(body, dict) else None
    if suspect is not None and (not isinstance(suspect, str) or len(suspect) > 16):
        raise HTTPException(422, "bad_suspect")
    cards, vis, night = _scope(c)
    if kind != "magnifier" and suspect not in {x["id"] for x in c.data["suspects"] if vis is None or x["id"] in vis}:
        raise HTTPException(422, "suspect_required")
    key = tools.slot(kind, night)
    prior = (await _uses(session, player.id, c.id)).get(key)
    if prior is not None:
        raise HTTPException(409, {"error": "already_used", "result": prior.result})
    result = tools.compute(kind, c.data, player.id, suspect, cards)
    if result is None:
        # nothing new for this case (or this suspect): say so, take nothing, charge nothing
        log.info("tool_nothing_new kind=%s case=%s", kind, c.id)
        return {"consumed": False, "nothing_new": True, "kind": kind,
                "text": "این بار چیز تازه‌ای پیدا نشد. چیزی ازت کم نشد.", **(await _view(session, player, c, p))}
    session.add(CaseToolUse(player_id=player.id, case_id=c.id, kind=key, source="coins" if buy else "stock", result=result))
    try:
        await session.flush()  # the unique row first: a double tap loses here, before any coin or tool moves
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "already_used")
    cost = tools.price(kind)
    if buy:
        if player.coins < cost:
            await session.rollback()
            raise HTTPException(402, {"error": "not_enough_coins", "need": cost})
        await add_coins(session, player, -cost, f"tool_{kind}:{c.id}")
        source = "coins"
    elif await tools.spend_stock(session, player.id, kind):
        source = "stock"
    elif await tools.claim_free(session, player.id, kind):
        source = "free"
    else:
        await session.rollback()
        raise HTTPException(409, {"error": "no_tool", "price": cost})
    use = await session.scalar(select(CaseToolUse).where(
        CaseToolUse.player_id == player.id, CaseToolUse.case_id == c.id, CaseToolUse.kind == key))
    use.source = source
    await session.commit()
    log.info("tool_used kind=%s case=%s source=%s price=%d", kind, c.id, source, cost if source == "coins" else 0)
    return {"consumed": True, "nothing_new": False, "kind": kind, "result": result, "source": source,
            **(await _view(session, player, c, p))}


@router.post("/{case_id}/tools/{kind}/use")
async def use_tool(case_id: str, kind: str, body: dict = Body(default_factory=dict),
                   player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Uses a tool the player holds (stock or the one-time tutorial tool). 409 no_tool {price} when he holds none."""
    return await _apply(case_id, kind, body, player, session, buy=False)


@router.post("/{case_id}/tools/{kind}/buy")
async def buy_tool(case_id: str, kind: str, body: dict = Body(default_factory=dict),
                   player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    """Buys one tool with coins and uses it on this case in one transaction (the strict `tool_buy` limit)."""
    return await _apply(case_id, kind, body, player, session, buy=True)
