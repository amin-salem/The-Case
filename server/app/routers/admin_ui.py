"""Admin panel: a web page at /admin/ui and read-only JSON under /admin/api (header X-Admin-Key).
Actions (gift, broadcast, ban) are the existing /admin/gifts and /admin/players/{id}/ban calls."""
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import case, func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from ..config import get_settings
from ..services import health as health_service
from ..db import get_session
from ..models import (AdminLog, CaseProgress, CoinLog, Event, InboxItem, MissionDay, Player, PlayerAchievement,
                      Purchase, StoryProgress, utcnow)
from ..security import require_admin
from ..services.ratelimit import limiter
from ..util import ts
from ..version import VERSION

page_router = APIRouter(tags=["admin"])
router = APIRouter(prefix="/admin/api", tags=["admin"], dependencies=[Depends(require_admin)])

_PAGE = Path(__file__).resolve().parent.parent / "admin_page.html"


@page_router.get("/admin/ui", response_class=HTMLResponse, include_in_schema=False)
async def page() -> HTMLResponse:
    # the page holds no data: it asks for the admin key and then calls /admin/api
    return HTMLResponse(_PAGE.read_text(encoding="utf-8"), headers={"Cache-Control": "no-store"})


_FONTS = Path(__file__).resolve().parent.parent / "fonts"
_FONT_NAMES = {"Vazirmatn-Regular.ttf", "Vazirmatn-Bold.ttf", "Vazirmatn-Black.ttf"}


@page_router.get("/static/fonts/{name}", include_in_schema=False)
async def font(name: str):
    """The panel uses the same font as the game (a fixed list of three files, nothing else is served)."""
    if name not in _FONT_NAMES:
        raise HTTPException(404, "no_font")
    return FileResponse(_FONTS / name, media_type="font/ttf", headers={"Cache-Control": "public, max-age=604800"})


def _day(dt: datetime) -> str:
    return dt.replace(tzinfo=timezone.utc).astimezone(content.now_local().tzinfo).date().isoformat()


def _title(case_id: str) -> str:
    c = content.by_id(case_id) or content.weekly_by_id(case_id)
    t = (c.data.get("title") if c and isinstance(c.data, dict) else None) or ""
    return f"{case_id} {t}".strip()


async def _nicknames(session: AsyncSession, ids) -> dict:
    ids = {i for i in ids if i}
    if not ids:
        return {}
    rows = (await session.execute(select(Player.id, Player.nickname).where(Player.id.in_(ids)))).all()
    return {pid: nick for pid, nick in rows}


@router.get("/overview")
async def overview(days: int = Query(14, ge=1, le=60), session: AsyncSession = Depends(get_session)):
    now = utcnow()
    since = now - timedelta(days=days + 1)
    series: dict[str, dict] = {}
    for i in range(days):
        d = _day(now - timedelta(days=days - 1 - i))
        series[d] = {"day": d, "new": 0, "opened": 0, "solved": 0, "failed": 0, "purchases": 0,
                     "coins_in": 0, "coins_out": 0, "active": set()}

    def put(dt, key, n=1):
        d = series.get(_day(dt)) if dt else None
        if d is not None:
            d[key] += n
        return d

    for (t,) in (await session.execute(select(Player.created_at).where(Player.created_at >= since))).all():
        put(t, "new")
    for pid, opened, fin, solved, failed in (await session.execute(
            select(CaseProgress.player_id, CaseProgress.opened_at, CaseProgress.finished_at, CaseProgress.solved,
                   CaseProgress.failed).where(or_(CaseProgress.opened_at >= since, CaseProgress.finished_at >= since)))).all():
        d = put(opened, "opened")
        if d is not None:
            d["active"].add(pid)
        if fin and (solved or failed):
            d = put(fin, "solved" if solved else "failed")
            if d is not None:
                d["active"].add(pid)
    for pid, t, amount in (await session.execute(
            select(CoinLog.player_id, CoinLog.at, CoinLog.amount).where(CoinLog.at >= since))).all():
        d = put(t, "coins_in" if amount > 0 else "coins_out", abs(amount))
        if d is not None:
            d["active"].add(pid)
    for pid, t in (await session.execute(select(Event.player_id, Event.ts).where(Event.ts >= since))).all():
        d = series.get(_day(t))
        if d is not None:
            d["active"].add(pid)
    for (t,) in (await session.execute(select(Purchase.created_at).where(
            Purchase.created_at >= since, Purchase.status == "granted"))).all():
        put(t, "purchases")
    out = []
    for d in series.values():
        d["active"] = len(d["active"])
        out.append(d)

    async def count(stmt) -> int:
        return int(await session.scalar(stmt) or 0)

    totals = {
        "players": await count(select(func.count()).select_from(Player)),
        "active_24h": await count(select(func.count()).select_from(Player).where(Player.last_seen >= now - timedelta(days=1))),
        "active_7d": await count(select(func.count()).select_from(Player).where(Player.last_seen >= now - timedelta(days=7))),
        "secured": await count(select(func.count()).select_from(Player).where(Player.email.is_not(None))),
        "banned": await count(select(func.count()).select_from(Player).where(Player.banned.is_(True))),
        "cases_solved": await count(select(func.count()).select_from(CaseProgress).where(CaseProgress.solved.is_(True))),
        "coins_in_circulation": int(await session.scalar(select(func.coalesce(func.sum(Player.coins), 0))) or 0),
    }
    versions = [{"version": v or "؟", "build": int(b or 0), "players": int(n)} for v, b, n in (await session.execute(
        select(Player.client_version, Player.client_build, func.count()).group_by(Player.client_version, Player.client_build)
        .order_by(func.count().desc()).limit(30))).all()]
    return {"days": out, "totals": totals, "versions": versions}


@router.get("/feed")
async def feed(limit: int = Query(60, ge=1, le=200), session: AsyncSession = Depends(get_session)):
    """The latest things players did, newest first (merged from the tables that already record them)."""
    items: list[dict] = []
    n = limit
    for p in (await session.execute(select(Player).order_by(Player.created_at.desc()).limit(n))).scalars().all():
        items.append({"t": ts(p.created_at), "kind": "signup", "pid": p.id, "text": "حساب تازه ساخت"})
    for x in (await session.execute(select(CaseProgress).order_by(CaseProgress.opened_at.desc()).limit(n))).scalars().all():
        items.append({"t": ts(x.opened_at), "kind": "open", "pid": x.player_id, "text": f"پرونده را باز کرد: {_title(x.case_id)}"})
    for x in (await session.execute(select(CaseProgress).where(CaseProgress.finished_at.is_not(None))
                                    .order_by(CaseProgress.finished_at.desc()).limit(n))).scalars().all():
        if x.solved:
            items.append({"t": ts(x.finished_at), "kind": "solved", "pid": x.player_id,
                          "text": f"حل کرد: {_title(x.case_id)} — {x.stars}★، {x.seconds}ث، {x.hints} سرنخ، {x.attempts} اتهام اشتباه"})
        elif x.failed:
            items.append({"t": ts(x.finished_at), "kind": "failed", "pid": x.player_id, "text": f"شکست خورد: {_title(x.case_id)}"})
    for c in (await session.execute(select(CoinLog).order_by(CoinLog.id.desc()).limit(n))).scalars().all():
        items.append({"t": ts(c.at), "kind": "coins", "pid": c.player_id, "text": f"سکه {c.amount:+d} ({c.reason}) → {c.balance}"})
    for x in (await session.execute(select(Purchase).order_by(Purchase.id.desc()).limit(n))).scalars().all():
        items.append({"t": ts(x.created_at), "kind": "purchase", "pid": x.player_id, "text": f"خرید {x.product_id} ({x.status})"})
    for e in (await session.execute(select(Event).order_by(Event.id.desc()).limit(n))).scalars().all():
        items.append({"t": ts(e.ts), "kind": "event", "pid": e.player_id, "text": f"رویداد {e.name}"})
    items.sort(key=lambda i: i["t"] or 0, reverse=True)
    items = items[:limit]
    nick = await _nicknames(session, {i["pid"] for i in items})
    for i in items:
        i["nick"] = nick.get(i["pid"], "")
    return items


_SORTS = {"last_seen": Player.last_seen, "created": Player.created_at, "coins": Player.coins,
          "solved": Player.cases_solved, "stars": Player.stars_total, "streak": Player.streak}


@router.get("/players")
async def players(q: str = Query("", max_length=60), sort: str = "last_seen", limit: int = Query(40, ge=1, le=200),
                  offset: int = Query(0, ge=0), only_banned: bool = False, session: AsyncSession = Depends(get_session)):
    col = _SORTS.get(sort, Player.last_seen)
    stmt = select(Player)
    if q:
        stmt = stmt.where(or_(Player.nickname.contains(q), Player.invite_code == q.upper(), Player.id.startswith(q),
                              Player.device_id == q, Player.email == q.lower()))
    if only_banned:
        stmt = stmt.where(Player.banned.is_(True))
    total = int(await session.scalar(select(func.count()).select_from(stmt.subquery())) or 0)
    rows = (await session.execute(stmt.order_by(col.desc(), Player.id).limit(limit).offset(offset))).scalars().all()
    return {"total": total, "items": [{
        "id": p.id, "nickname": p.nickname, "coins": p.coins, "solved": p.cases_solved, "stars": p.stars_total,
        "streak": p.streak, "secured": bool(p.email), "banned": p.banned, "app_version": p.app_version,
        "created": ts(p.created_at), "last_seen": ts(p.last_seen)} for p in rows]}


@router.get("/players/{player_id}")
async def player(player_id: str, session: AsyncSession = Depends(get_session)):
    p = await session.get(Player, player_id)
    if p is None:
        raise HTTPException(404, "no_player")
    same_device = (await session.execute(select(Player.id, Player.nickname, Player.created_at).where(
        Player.device_id == p.device_id, Player.id != p.id).limit(20))).all()
    prog = (await session.execute(select(CaseProgress).where(CaseProgress.player_id == p.id)
                                  .order_by(CaseProgress.opened_at.desc()))).scalars().all()
    story = (await session.execute(select(StoryProgress).where(StoryProgress.player_id == p.id))).scalars().all()
    ach = (await session.execute(select(PlayerAchievement).where(PlayerAchievement.player_id == p.id))).scalars().all()
    days = (await session.execute(select(MissionDay).where(MissionDay.player_id == p.id)
                                  .order_by(MissionDay.day.desc()).limit(14))).scalars().all()
    timeline: list[dict] = []
    for c in (await session.execute(select(CoinLog).where(CoinLog.player_id == p.id).order_by(CoinLog.id.desc()).limit(150))).scalars():
        timeline.append({"t": ts(c.at), "kind": "coins", "text": f"سکه {c.amount:+d} ({c.reason}) → {c.balance}"})
    for x in prog:
        timeline.append({"t": ts(x.opened_at), "kind": "open", "text": f"باز کرد: {_title(x.case_id)}"})
        if x.finished_at:
            timeline.append({"t": ts(x.finished_at), "kind": "solved" if x.solved else "failed",
                             "text": f"{'حل' if x.solved else 'شکست'}: {_title(x.case_id)} — {x.stars}★، {x.seconds}ث"})
    for x in (await session.execute(select(Purchase).where(Purchase.player_id == p.id))).scalars():
        timeline.append({"t": ts(x.created_at), "kind": "purchase", "text": f"خرید {x.product_id} ({x.status})"})
    for x in (await session.execute(select(InboxItem).where(InboxItem.player_id == p.id).order_by(InboxItem.id.desc()).limit(30))).scalars():
        timeline.append({"t": ts(x.created_at), "kind": "inbox", "text": f"پیام: {x.title}" + (" (دریافت شد)" if x.claimed_at else "")})
    for a in ach:
        timeline.append({"t": ts(a.at), "kind": "achievement", "text": f"دستاورد {a.achievement_id}"})
    for e in (await session.execute(select(Event).where(Event.player_id == p.id).order_by(Event.id.desc()).limit(80))).scalars():
        timeline.append({"t": ts(e.ts), "kind": "event", "text": f"رویداد {e.name}"})
    timeline.sort(key=lambda i: i["t"] or 0, reverse=True)
    return {
        "player": {"id": p.id, "nickname": p.nickname, "email": p.email, "device_id": p.device_id, "coins": p.coins,
                   "xp": p.xp, "streak": p.streak, "best_streak": p.best_streak, "solved": p.cases_solved,
                   "stars": p.stars_total, "warrants": p.warrants, "no_ads": p.no_ads, "vip_until": ts(p.vip_until),
                   "banned": p.banned, "app_version": p.app_version, "invite_code": p.invite_code,
                   "referred_by": p.referred_by, "client": {
                       "version": p.client_version, "build": p.client_build, "platform": p.platform,
                       "os_version": p.os_version, "device_model": p.device_model, "reported": ts(p.client_at)},
                   "created": ts(p.created_at), "last_seen": ts(p.last_seen),
                   "stats": p.stats or {}},
        "same_device": [{"id": i, "nickname": n, "created": ts(c)} for i, n, c in same_device],
        "cases": [{"case": x.case_id, "title": _title(x.case_id), "solved": x.solved, "failed": x.failed, "stars": x.stars,
                   "hints": x.hints, "attempts": x.attempts, "seconds": x.seconds, "active_seconds": x.active_seconds,
                   "seen": len(x.seen or []), "opened": ts(x.opened_at)} for x in prog],
        "story": [{"season": s.season, "chapter": s.chapter, "solved": s.solved, "stars": s.stars} for s in story],
        "missions": [{"day": d.day, "counts": d.counts, "chest": d.claimed} for d in days],
        "timeline": timeline[:250],
    }


@router.get("/cases")
async def cases(session: AsyncSession = Depends(get_session)):
    """Per case: how many opened it, solved, failed, averages, and who the players accuse first."""
    agg = {}
    for cid, n, s, f, stars, secs, hints, att in (await session.execute(
            select(CaseProgress.case_id, func.count(),
                   func.sum(case((CaseProgress.solved.is_(True), 1), else_=0)),
                   func.sum(case((CaseProgress.failed.is_(True), 1), else_=0)),
                   func.avg(CaseProgress.stars), func.avg(CaseProgress.seconds), func.avg(CaseProgress.hints),
                   func.avg(CaseProgress.attempts)).group_by(CaseProgress.case_id))).all():
        agg[cid] = (n, s, f, stars, secs, hints, att)
    first = defaultdict(dict)
    for cid, sid, n in (await session.execute(select(CaseProgress.case_id, CaseProgress.first_accused, func.count())
                                              .where(CaseProgress.first_accused.is_not(None))
                                              .group_by(CaseProgress.case_id, CaseProgress.first_accused))).all():
        first[cid][sid] = n
    out = []
    for c in list(content.all_cases()) + list(content.weekly_cases()):
        n, s, f, stars, secs, hints, att = agg.get(c.id, (0, 0, 0, None, None, None, None))
        names = {x["id"]: x.get("name", x["id"]) for x in c.data.get("suspects", [])} if isinstance(c.data, dict) else {}
        top = sorted(first.get(c.id, {}).items(), key=lambda kv: -kv[1])[:3]
        out.append({"id": c.id, "title": _title(c.id), "opens": content.opens_at(c).isoformat(), "opened": int(n or 0),
                    "solved": int(s or 0), "failed": int(f or 0),
                    "avg_stars": round(float(stars), 2) if stars is not None else None,
                    "avg_seconds": round(float(secs)) if secs is not None else None,
                    "avg_hints": round(float(hints), 2) if hints is not None else None,
                    "avg_wrong": round(float(att), 2) if att is not None else None,
                    "first_guess": [{"suspect": names.get(k, k), "n": v, "culprit": k == c.culprit} for k, v in top]})
    return out


@router.get("/money")
async def money(days: int = Query(30, ge=1, le=90), session: AsyncSession = Depends(get_session)):
    since = utcnow() - timedelta(days=days)
    by_day: dict[str, dict] = defaultdict(lambda: defaultdict(int))
    by_product: dict[str, int] = defaultdict(int)
    for pid, t, status in (await session.execute(select(Purchase.product_id, Purchase.created_at, Purchase.status)
                                                 .where(Purchase.created_at >= since))).all():
        if status == "granted":
            by_day[_day(t)][pid] += 1
            by_product[pid] += 1
    earned: dict[str, int] = defaultdict(int)
    spent: dict[str, int] = defaultdict(int)
    for amount, reason in (await session.execute(select(CoinLog.amount, CoinLog.reason).where(CoinLog.at >= since))).all():
        (earned if amount > 0 else spent)[reason.split(":")[0]] += abs(amount)
    return {"purchases_by_day": {d: dict(v) for d, v in sorted(by_day.items())}, "purchases_by_product": dict(by_product),
            "coins_earned_by_reason": dict(sorted(earned.items(), key=lambda kv: -kv[1])),
            "coins_spent_by_reason": dict(sorted(spent.items(), key=lambda kv: -kv[1]))}


@router.get("/health")
async def health(session: AsyncSession = Depends(get_session)):
    db_ok = True
    try:
        await session.execute(text("SELECT 1"))
    except Exception:
        db_ok = False
    today = content.todays_case()
    return {"server_version": VERSION, "db_ok": db_ok, "now": content.now_local().isoformat(),
            "today_case": today.id if today else None, "nightly_cases": len(content.all_cases()),
            "weekly_cases": len(content.weekly_cases()),
            "rate_limit": await limiter.admin_summary() if get_settings().rate_limit else {"enabled": False}}


class ClearLockIn(BaseModel):
    id: str = Field(min_length=4, max_length=32, pattern=r"^[0-9a-f]+$")


@router.post("/rate-limit/clear")
async def clear_lockout(body: ClearLockIn, session: AsyncSession = Depends(get_session)):
    """Lift one admin lockout (the id is shown on the Health screen); recorded in the admin log."""
    existed = await limiter.clear_lockout(body.id)
    session.add(AdminLog(action="rl_clear", target=body.id[:12], detail={"existed": existed}))
    await session.commit()
    return {"cleared": existed}


@router.get("/health2")
async def health2(session: AsyncSession = Depends(get_session)):
    """The Health screen: server, both addresses, content, players, security. Never fails as a whole."""
    return await health_service.build(session)


@router.get("/liara")
async def liara(refresh: bool = False):
    """Liara wallet balance (the token stays on the server; cached 5 min, one real call per 30 s)."""
    return await health_service.liara_balance(refresh)


@router.get("/log")
async def log(limit: int = Query(100, ge=1, le=300), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(AdminLog).order_by(AdminLog.id.desc()).limit(limit))).scalars().all()
    return [{"t": ts(r.at), "action": r.action, "target": r.target, "detail": r.detail} for r in rows]
