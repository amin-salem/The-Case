"""Detective tools «ابزارهای کارآگاهی» (Amin, 16 Oct 2026): three small consumables that narrow the search without
solving the case. The server decides every answer from the case file; the phone only asks.

- magnifier «ذره‌بین»: marks ONE card as irrelevant. Uses `solution.irrelevant` when authored, else any card that is not proof,
  not cited and does not name the culprit.
- fingerprint «اثر انگشت‌خوان»: for one suspect, one authored physical trace (`suspect.print`) that no card shows; never a verdict.
- camera «دوربین مخفی»: one extra neutral line about a suspect. Needs `suspect.camera` lines in the case file.

Once per case per kind (CaseToolUse is unique). Never touches plaques, never counts as investigation (active time and
interrogated suspects are what anti-cheat reads, and tools add to neither). Pure logic here; routers/tools.py does I/O.
"""
from __future__ import annotations

import hashlib
import logging
import re

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from . import economy as eco
from .models import PlayerTool

log = logging.getLogger("tools")

KINDS = ("magnifier", "fingerprint", "camera")
INFO = {
    "magnifier": {"title": "ذره‌بین", "desc": "یکی از مدارک پرونده رو که برای حل لازم نیست علامت می‌زنه تا وقتت رو تلف نکنی."},
    "fingerprint": {"title": "اثر انگشت‌خوان", "desc": "برای یک مظنون یه ردِ فیزیکیِ تازه رو نشون می‌ده؛ مثلاً اثرش روی یه وسیله. حکم گناه نیست، فقط یه سرنخ مکمله."},
    "camera": {"title": "دوربین مخفی", "desc": "یک مشاهده‌ی تازه درباره‌ی یک مظنون رو نشونت می‌ده."},
}
NOT_FOR_MODE = "ابزارهای کارآگاهی توی پرونده‌های داستانی کار نمی‌کنن."
_TITLES = ("آقای", "خانم", "دکتر", "حاج", "سرهنگ", "استاد", "مهندس", "سردار", "سرگرد", "حاجی", "سید", "خانوم")


def _norm(text: str) -> str:
    return (text or "").replace("‌", "").replace("ي", "ی").replace("ك", "ک")


def _pick(seed: str, n: int) -> int:
    return int(hashlib.sha256(seed.encode()).hexdigest(), 16) % n


def _norm_split(name: str) -> list[str]:
    return [t for t in name.replace("‌", " ").split() if len(t) >= 3 and t not in _TITLES]


def _lines(suspect: dict, key: str) -> list[str]:
    raw = suspect.get(key)
    lines = [raw] if isinstance(raw, str) else list(raw or [])
    return [ln.strip() for ln in lines if isinstance(ln, str) and ln.strip()]


def camera_lines(suspect: dict) -> list[str]:
    return _lines(suspect, "camera")


def print_lines(suspect: dict) -> list[str]:
    """Authored physical traces (`suspect.print`) for the fingerprint reader."""
    return _lines(suspect, "print")


def magnifier_pool(data: dict, cards: set[str] | None = None) -> tuple[list[str], bool]:
    """(card ids, authored). The author's `solution.irrelevant` when present; otherwise a card that is not a proof card (one the explanation does not cite by id when there is such a card)."""
    sol = data["solution"]
    irr = [i for i in (sol.get("irrelevant") or []) if cards is None or i in cards]
    if sol.get("irrelevant"):
        return irr, True
    cited = set(re.findall(r"\be\d+\b", sol.get("explanation", "")))
    out = [e["id"] for e in data["evidence"]
           if e["id"] not in sol["proof"] and e["id"] not in cited and (cards is None or e["id"] in cards)]
    if not out:  # an explanation that cites every spare card: they are still not the main proof, so say only that
        out = [e["id"] for e in data["evidence"]
               if e["id"] not in sol["proof"] and (cards is None or e["id"] in cards)]
    return out, False


def availability(data: dict, cards: set[str] | None = None, suspects: set[str] | None = None) -> dict[str, dict]:
    """What each tool can do on this case: {kind: {"available": bool, "suspects": [ids] | None}}. `cards`/`suspects`
    limit it to what the player can see now (weekend chapters)."""
    vis = [s for s in data["suspects"] if suspects is None or s["id"] in suspects]
    cam = [s["id"] for s in vis if camera_lines(s)]
    fp = [s["id"] for s in vis if print_lines(s)]
    return {"magnifier": {"available": bool(magnifier_pool(data, cards)[0]), "suspects": None},
            "fingerprint": {"available": bool(fp), "suspects": fp},
            "camera": {"available": bool(cam), "suspects": cam}}


def compute(kind: str, data: dict, player_id: str, suspect_id: str | None, cards: set[str] | None = None) -> dict | None:
    """The answer, or None when the tool has nothing new for this case/suspect (then it is not consumed)."""
    seed = f"{kind}:{player_id}:{data['id']}"
    if kind == "magnifier":
        pool, authored = magnifier_pool(data, cards)
        if not pool:
            return None
        card = pool[_pick(seed, len(pool))]
        title = next(e["title"] for e in data["evidence"] if e["id"] == card)
        if authored:
            return {"card": card, "text": f"ذره‌بین نشون داد «{title}» برای حل این پرونده لازم نیست؛ بی‌ربطه."}
        return {"card": card, "text": f"ذره‌بین نشون داد «{title}» جزو مدارک اصلیِ حل پرونده نیست؛ بیشتر مکمل و پس‌زمینه‌ست. اول سراغ بقیه برو."}
    s = next((x for x in data["suspects"] if x["id"] == suspect_id), None)
    if s is None:
        return None
    if kind == "fingerprint":
        lines = print_lines(s)
        if not lines:
            return None
        return {"suspect": s["id"], "text": f"اثر انگشت‌خوان ({s['name']}): {lines[_pick(seed + ':' + s['id'], len(lines))]}"}
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


def how_to() -> dict:
    """Where each tool comes from and where it is used: shown in the app's help sheet (one source of truth)."""
    return {kind: {"get": (f"اولین بار رایگانه. بعدش گاهی از جایزه‌ها (دستاوردها، گنجینه‌ی روز هفتم) درمیاد یا با {eco.TOOL_PRICES[kind]} سکه "
                           "همون‌جا موقع استفاده می‌خری."),
                   "use": "روی صفحه‌ی پرونده، بالای تب‌ها. برای هر پرونده فقط یک بار (توی پرونده‌ی آخر هفته، هر شب یک بار). اگه چیز تازه‌ای پیدا نشه، چیزی ازت کم نمی‌شه."}
            for kind in KINDS}


def slot(kind: str, chapter: int) -> str:
    """The CaseToolUse key: once per case per kind; weekend cases once per night (`kind@2` from the second night)."""
    return kind if chapter <= 1 else f"{kind}@{chapter}"
