"""Detective tools «ابزارهای کارآگاهی» (Amin, 16 Oct 2026): three small consumables that narrow the search without
solving the case. The server decides every answer from the case file; the phone only asks.

- magnifier «ذره‌بین»: marks ONE card as irrelevant. Needs `solution.irrelevant` (authors certify the cards; a card the
  proof or the explanation uses can never be listed, see content._validate_tool_data).
- fingerprint «اثر انگشت‌خوان»: for one suspect, whether he is touched by the main (proof) cards.
- camera «دوربین مخفی»: one extra neutral line about a suspect. Needs `suspect.camera` lines in the case file.

Once per case per kind (CaseToolUse is unique). Never touches plaques, never counts as investigation (active time and
interrogated suspects are what anti-cheat reads, and tools add to neither). Pure logic here; routers/tools.py does I/O.
"""
from __future__ import annotations

import hashlib
import logging

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from . import economy as eco
from .models import PlayerTool

log = logging.getLogger("tools")

KINDS = ("magnifier", "fingerprint", "camera")
INFO = {
    "magnifier": {"title": "ذره‌بین", "desc": "یکی از مدارک پرونده رو که برای حل لازم نیست «بی‌ربط» علامت می‌زنه."},
    "fingerprint": {"title": "اثر انگشت‌خوان", "desc": "برای یک مظنون می‌گه توی مدارک اصلی نقش داره یا نه."},
    "camera": {"title": "دوربین مخفی", "desc": "یک مشاهده‌ی تازه درباره‌ی یک مظنون رو نشونت می‌ده."},
}
NOT_FOR_MODE = "ابزارهای کارآگاهی فقط توی پرونده‌های روزانه کار می‌کنن."
_TITLES = ("آقای", "خانم", "دکتر", "حاج", "سرهنگ", "استاد", "مهندس", "سردار", "سرگرد", "حاجی", "سید", "خانوم")


def _norm(text: str) -> str:
    return (text or "").replace("‌", "").replace("ي", "ی").replace("ك", "ک")


def _pick(seed: str, n: int) -> int:
    return int(hashlib.sha256(seed.encode()).hexdigest(), 16) % n


def touched_ids(data: dict) -> set[str]:
    """Suspects touched by the main (proof) cards: the culprit (the proof contradicts his own words) and everybody whose
    name appears in a proof card."""
    ev = {e["id"]: e for e in data["evidence"]}
    text = _norm(" ".join(f"{ev[i]['title']} {ev[i]['text']}" for i in data["solution"]["proof"]))
    out = {data["solution"]["culprit"]}
    for s in data["suspects"]:
        toks = [_norm(t) for t in _norm_split(s["name"])]
        if any(t and t in text for t in toks):
            out.add(s["id"])
    return out


def _norm_split(name: str) -> list[str]:
    return [t for t in name.replace("‌", " ").split() if len(t) >= 3 and t not in _TITLES]


def fingerprint_safe(data: dict) -> bool:
    """The answer must never single out the culprit: offered only when at least two suspects are touched and at least one
    is not (so "yes" is never "guilty" and the tool is never a coin flip between everybody and nobody)."""
    n = len(data["suspects"])
    return 2 <= len(touched_ids(data)) <= n - 1


def camera_lines(suspect: dict) -> list[str]:
    cam = suspect.get("camera")
    lines = [cam] if isinstance(cam, str) else list(cam or [])
    return [ln.strip() for ln in lines if isinstance(ln, str) and ln.strip()]


def availability(data: dict) -> dict[str, dict]:
    """What each tool can do on this case: {kind: {"available": bool, "suspects": [ids] | None}}."""
    irr = data["solution"].get("irrelevant") or []
    cam = [s["id"] for s in data["suspects"] if camera_lines(s)]
    return {"magnifier": {"available": bool(irr), "suspects": None},
            "fingerprint": {"available": fingerprint_safe(data), "suspects": [s["id"] for s in data["suspects"]]},
            "camera": {"available": bool(cam), "suspects": cam}}


def compute(kind: str, data: dict, player_id: str, suspect_id: str | None) -> dict | None:
    """The answer, or None when the tool has nothing new for this case/suspect (then it is not consumed)."""
    seed = f"{kind}:{player_id}:{data['id']}"
    if kind == "magnifier":
        irr = data["solution"].get("irrelevant") or []
        if not irr:
            return None
        card = irr[_pick(seed, len(irr))]
        title = next(e["title"] for e in data["evidence"] if e["id"] == card)
        return {"card": card, "text": f"ذره‌بین نشون داد «{title}» برای حل این پرونده لازم نیست؛ بی‌ربطه."}
    s = next((x for x in data["suspects"] if x["id"] == suspect_id), None)
    if s is None:
        return None
    if kind == "fingerprint":
        if not fingerprint_safe(data):
            return None
        main = s["id"] in touched_ids(data)
        verdict = "توی مدارک اصلی نقش داره" if main else "توی مدارک اصلی نقش مهمی نداره"
        return {"suspect": s["id"], "main": main, "text": f"اثر انگشت‌خوان: {s['name']} {verdict}."}
    lines = camera_lines(s)
    if not lines:
        return None
    return {"suspect": s["id"], "text": f"دوربین مخفی ({s['name']}): {lines[_pick(seed + ':' + s['id'], len(lines))]}"}


# ---- stock (guarded SQL only: a double tap or two workers can never spend one tool twice) ----------------------------

def _insert(session: AsyncSession):
    return pg_insert if session.get_bind().dialect.name == "postgresql" else sqlite_insert


async def stock(session: AsyncSession, player_id: str) -> dict[str, dict]:
    rows = (await session.scalars(select(PlayerTool).where(PlayerTool.player_id == player_id))).all()
    out = {k: {"count": 0, "free_used": False} for k in KINDS}
    for r in rows:
        if r.kind in out:
            out[r.kind] = {"count": max(0, int(r.count or 0)), "free_used": bool(r.free_used)}
    return out


async def _ensure_row(session: AsyncSession, player_id: str, kind: str) -> None:
    await session.execute(_insert(session)(PlayerTool).values(player_id=player_id, kind=kind, count=0, free_used=False)
                          .on_conflict_do_nothing(index_elements=["player_id", "kind"]))


async def grant(session: AsyncSession, player_id: str, kind: str, n: int = 1, *, why: str = "drop") -> None:
    """Adds tools to the stock (a rare drop at an existing reward point). Atomic upsert; the caller commits and has
    already guarded the reward itself against repeating (chest claimed flag, achievement row)."""
    if kind not in KINDS or n <= 0:
        return
    ins = _insert(session)(PlayerTool).values(player_id=player_id, kind=kind, count=n, free_used=False)
    await session.execute(ins.on_conflict_do_update(index_elements=["player_id", "kind"],
                                                    set_={"count": PlayerTool.count + n}))
    log.info("tool_granted kind=%s n=%d why=%s", kind, n, why)


async def spend_stock(session: AsyncSession, player_id: str, kind: str) -> bool:
    res = await session.execute(update(PlayerTool).where(
        PlayerTool.player_id == player_id, PlayerTool.kind == kind, PlayerTool.count >= 1)
        .values(count=PlayerTool.count - 1))
    return bool(res.rowcount)


async def claim_free(session: AsyncSession, player_id: str, kind: str) -> bool:
    """The one-time tutorial tool of this kind: true exactly once per player and kind, whatever the concurrency."""
    await _ensure_row(session, player_id, kind)
    res = await session.execute(update(PlayerTool).where(
        PlayerTool.player_id == player_id, PlayerTool.kind == kind, PlayerTool.free_used.is_(False))
        .values(free_used=True))
    return bool(res.rowcount)


def price(kind: str) -> int:
    return eco.TOOL_PRICES[kind]
