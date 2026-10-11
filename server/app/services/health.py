"""Data for the admin panel's Health screen (GET /admin/api/health2, GET /admin/api/liara).

Every section is computed on its own and wrapped in `_safe`: one failing check never blanks the screen.
Everything that touches the outside world (clock, TLS, Liara API) goes through `deps`, so tests inject fakes.
Caches here live in this worker's memory only (the server runs 2 workers); that is fine for a read-only screen.
Secrets are never returned: the Liara token is read from the environment, used for one request and forgotten.
"""
from __future__ import annotations

import asyncio
import logging
import os
import socket
import ssl
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Awaitable, Callable

import httpx
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from .. import content
from ..config import get_settings
from ..models import CaseProgress, CoinLog, Event, Player, Purchase
from ..version import VERSION

log = logging.getLogger("health")

HOSTS = [("gaamly.ir", True), ("thecase.liara.run", False)]  # (host, is it the main address?)
LIARA_URL = "https://api.liara.ir/v1/billing"
TLS_TTL = 600          # seconds a TLS result stays cached
LIARA_TTL = 300        # seconds a balance stays cached
LIARA_MIN_GAP = 30     # at most one real Liara call per this many seconds
LIARA_TIMEOUT = 6.0
TLS_TIMEOUT = 5.0
_RANK = {"ok": 0, "warn": 1, "bad": 2}

WATCH_NOTE = [
    {"name": "Server watch", "schedule": "هر ۳۰ دقیقه (uptime.yml)"},
    {"name": "Liara balance", "schedule": "هر روز ساعت ۸ صبح به وقت تهران (liara-balance.yml)"},
]


def _tls_days_sync(host: str) -> int:
    ctx = ssl.create_default_context()
    with socket.create_connection((host, 443), timeout=TLS_TIMEOUT) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as tls:
            cert = tls.getpeercert()
    return int((ssl.cert_time_to_seconds(cert["notAfter"]) - time.time()) // 86400)


async def _tls_days(host: str) -> int:
    return await asyncio.wait_for(asyncio.to_thread(_tls_days_sync, host), TLS_TIMEOUT + 1)


async def _liara_fetch(token: str) -> tuple[int, Any]:
    """One GET to the Liara billing API. Returns (http status, parsed json or None)."""
    async with httpx.AsyncClient(timeout=LIARA_TIMEOUT) as c:
        r = await c.get(LIARA_URL, headers={"Authorization": f"Bearer {token}"})
    try:
        return r.status_code, r.json()
    except ValueError:
        return r.status_code, None


class Deps:
    """Everything outside the process. Tests replace these attributes."""
    clock: Callable[[], float] = staticmethod(time.time)
    now_local: Callable[[], datetime] = staticmethod(content.now_local)
    tls_days: Callable[[str], Awaitable[int]] = staticmethod(_tls_days)
    liara_fetch: Callable[[str], Awaitable[tuple[int, Any]]] = staticmethod(_liara_fetch)


deps = Deps()
_STARTED = time.time()
_tls_cache: dict[str, tuple[float, dict]] = {}
_liara_cache: dict[str, Any] = {"at": 0.0, "result": None, "last_call": -1e9}


def reset() -> None:
    """Forget caches (tests)."""
    _tls_cache.clear()
    _liara_cache.update({"at": 0.0, "result": None, "last": None, "last_call": -1e9})


def worst(*statuses: str) -> str:
    return max(statuses, key=lambda s: _RANK.get(s, 0)) if statuses else "ok"


def level_low(value: float | None, amber: float, red: float) -> str:
    """Status for a number that is bad when LOW (days left, balance): below red = bad, below amber = warn."""
    if value is None:
        return "warn"
    if value < red:
        return "bad"
    if value < amber:
        return "warn"
    return "ok"


async def _safe(name: str, fn: Callable[[], Awaitable[dict]], extra: dict | None = None) -> dict:
    try:
        return await fn()
    except Exception as e:  # one failing check must not blank the screen
        log.warning("health section %s failed: %s", name, type(e).__name__)
        return {"status": "bad", "error": type(e).__name__, **(extra or {})}


# ---------------------------------------------------------------- sections


async def _server(session: AsyncSession) -> dict:
    out: dict = {"status": "ok", "version": VERSION, "uptime_s": max(0, int(deps.clock() - _STARTED)),
                 "workers": None, "db_ok": False, "db_ms": None, "db_size_mb": None, "rows": {}}
    try:
        out["workers"] = int(os.environ.get("WEB_CONCURRENCY", "")) or None
    except ValueError:
        pass
    t0 = time.perf_counter()
    try:
        await session.execute(text("SELECT 1"))
        out["db_ok"] = True
        out["db_ms"] = round((time.perf_counter() - t0) * 1000, 1)
    except Exception:
        out["status"] = "bad"
        return out
    if out["db_ms"] > 1000:
        out["status"] = "bad"
    elif out["db_ms"] > 300:
        out["status"] = "warn"
    for label, model in (("players", Player), ("case_progress", CaseProgress), ("purchases", Purchase),
                         ("coin_log", CoinLog), ("events", Event)):
        try:
            out["rows"][label] = int(await session.scalar(select(func.count()).select_from(model)) or 0)
        except Exception:
            out["rows"][label] = None
    try:
        if session.bind is not None and session.bind.dialect.name == "postgresql":
            size = await session.scalar(text("SELECT pg_database_size(current_database())"))
            out["db_size_mb"] = round(int(size) / 1048576, 1)
    except Exception:
        pass
    return out


async def _domain(host: str, main: bool) -> dict:
    now = deps.clock()
    hit = _tls_cache.get(host)
    if hit and now - hit[0] < TLS_TTL:
        return {**hit[1], "cached": True}
    try:
        days = await deps.tls_days(host)
        res = {"host": host, "days": days, "status": level_low(days, 30, 14), "error": None}
        if not main and res["status"] == "bad":
            res["status"] = "warn"
    except Exception as e:
        kind = "timeout" if isinstance(e, (asyncio.TimeoutError, TimeoutError)) else type(e).__name__
        # the old address is a fallback only: its failure is an amber note, not an alarm
        res = {"host": host, "days": None, "status": "bad" if main else "warn", "error": kind}
    _tls_cache[host] = (now, res)
    return {**res, "cached": False}


async def _domains() -> dict:
    items = await asyncio.gather(*[_domain(h, m) for h, m in HOSTS])
    return {"status": worst(*[i["status"] for i in items]), "items": list(items)}


def _iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


async def _content() -> dict:
    now = deps.now_local()
    problems: list[str] = []
    cases: tuple = ()
    try:
        cases = content.all_cases()
    except Exception as e:
        problems.append(f"nightly: {type(e).__name__}")
    try:
        content.weekly_cases()
    except Exception as e:
        problems.append(f"weekend: {type(e).__name__}")
    try:
        chapters = content.story_chapters()
    except Exception as e:
        chapters = ()
        problems.append(f"story: {type(e).__name__}")
    days_ahead = max(0, (cases[-1].publish - now.date()).days) if cases else 0
    today = content.todays_case(now) if cases else None
    nxt = content.next_weekly(now)
    ahead_status = level_low(days_ahead, 7, 3)
    return {
        "status": worst(ahead_status, "bad" if problems else "ok"),
        "days_ahead": days_ahead, "days_ahead_status": ahead_status,
        "nightly_total": len(cases), "last_nightly_opened": _iso(content.opens_at(today)) if today else None,
        "today_case": today.id if today else None,
        "weekend_next": {"id": nxt.id, "opens_at": _iso(content.opens_at(nxt))} if nxt else None,
        "story": {"season": content.STORY_SEASON["season"], "title": content.STORY_SEASON["title"],
                  "chapters": len(chapters), "next_missing": len(chapters) + 1},
        "validation": "ok" if not problems else "failed", "problems": problems,
    }


def _day_start_utc(now_local: datetime) -> datetime:
    start = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    return start.astimezone(timezone.utc).replace(tzinfo=None)


async def _players(session: AsyncSession) -> dict:
    start = _day_start_utc(deps.now_local())
    total = int(await session.scalar(select(func.count()).select_from(Player)) or 0)
    active = int(await session.scalar(select(func.count()).select_from(Player).where(Player.last_seen >= start)) or 0)
    solves = int(await session.scalar(select(func.count()).select_from(CaseProgress).where(
        CaseProgress.solved.is_(True), CaseProgress.finished_at >= start)) or 0)
    rows = (await session.execute(select(Player.app_version, func.count()).group_by(Player.app_version)
                                  .order_by(func.count().desc()).limit(10))).all()
    return {"status": "ok", "total": total, "active_today": active, "solves_today": solves,
            "errors_1h": None,  # the server does not count 5xx answers yet
            "app_versions": [{"version": int(v or 0), "players": int(n)} for v, n in rows]}


async def _security() -> dict:
    s = get_settings()
    admin_ok = s.admin_api_key != "change-me-admin-dev-only" and len(s.admin_api_key) >= 24
    jwt_ok = s.jwt_secret != "change-me-dev-only" and len(s.jwt_secret) >= 32
    prod = s.env == "prod"
    status = "ok"
    if not admin_ok or not jwt_ok:
        status = "bad" if prod else "warn"
    if prod and s.bazaar_mode == "fake" and not s.myket_access_token:
        status = "bad"
    return {"status": status, "env": s.env, "admin_key_real": admin_ok, "jwt_secret_real": jwt_ok,
            "rate_limit": bool(s.rate_limit), "rate_limit_blocked_1h": None,  # the limiter has no counter yet
            "ads_enabled": bool(s.ads_enabled), "bazaar_mode": s.bazaar_mode,
            "myket_token_set": bool(s.myket_access_token)}


# ---------------------------------------------------------------- the endpoint payload


async def build(session: AsyncSession) -> dict:
    server = await _safe("server", lambda: _server(session), {"version": VERSION})
    domains = await _safe("domains", _domains)
    cont = await _safe("content", _content)
    players = await _safe("players", lambda: _players(session))
    sec = await _safe("security", _security)
    sections = {"server": server, "domains": domains, "content": cont, "players": players, "security": sec}
    return {"overall": worst(*[v.get("status", "ok") for v in sections.values()]),
            "checked_at": int(deps.clock()), **sections, "watch": WATCH_NOTE}


# ---------------------------------------------------------------- Liara balance


def _find_balance(o: Any) -> float | None:
    """The balance field wherever it is (same search as .github/workflows/liara-balance.yml)."""
    if isinstance(o, dict):
        for k, v in o.items():
            if str(k).lower() in ("balance", "credit", "credits") and isinstance(v, (int, float)) \
                    and not isinstance(v, bool):
                return v
        for v in o.values():
            r = _find_balance(v)
            if r is not None:
                return r
    elif isinstance(o, list):
        for v in o:
            r = _find_balance(v)
            if r is not None:
                return r
    return None


def _min_balance() -> float:
    try:
        return float(os.environ.get("LIARA_MIN_BALANCE") or 300000)
    except ValueError:
        return 300000.0


def _balance_result(data: Any, limit: float) -> dict:
    bal = None
    if isinstance(data, dict):
        user = data.get("user")
        b = user.get("balance") if isinstance(user, dict) else None
        if isinstance(b, (int, float)) and not isinstance(b, bool):
            bal = b
    if bal is None:
        bal = _find_balance(data)
    if bal is None:
        return {"state": "error", "kind": "no_balance_field", "status": "bad"}
    status = "bad" if bal <= limit else "warn" if bal <= limit * 1.5 else "ok"
    return {"state": "ok", "balance": bal, "limit": limit, "status": status}


async def liara_balance(refresh: bool = False) -> dict:
    """The Liara wallet for the admin panel. Token only from LIARA_API_TOKEN; never returned or logged."""
    token = os.environ.get("LIARA_API_TOKEN", "").strip()
    if not token:
        return {"state": "no_token", "status": "warn",
                "message": "LIARA_API_TOKEN روی لیارا تنظیم نشده",
                "hint": "در لیارا: برنامه ← تنظیمات ← متغیرهای محیطی ← LIARA_API_TOKEN را (همان توکن GitHub) اضافه کن."}
    now = deps.clock()
    cached = _liara_cache["result"]
    age = now - _liara_cache["at"]
    if cached is not None and age < LIARA_TTL and not refresh:
        return {**cached, "cached": True, "age_s": int(age)}
    if now - _liara_cache["last_call"] < LIARA_MIN_GAP:  # at most one real call per 30 s
        if cached is not None:
            return {**cached, "cached": True, "throttled": True, "age_s": int(age)}
        last = _liara_cache.get("last")
        return {**(last or {"state": "error", "kind": "too_soon", "status": "warn"}), "throttled": True}
    _liara_cache["last_call"] = now
    limit = _min_balance()
    try:
        code, data = await asyncio.wait_for(deps.liara_fetch(token), LIARA_TIMEOUT + 1)
        if code != 200:
            res = {"state": "error", "kind": f"http_{code}", "status": "bad"}
        else:
            res = _balance_result(data, limit)
    except (asyncio.TimeoutError, TimeoutError, httpx.TimeoutException):
        res = {"state": "error", "kind": "timeout", "status": "bad"}
    except httpx.HTTPError:
        res = {"state": "error", "kind": "network", "status": "bad"}
    except Exception as e:
        res = {"state": "error", "kind": type(e).__name__, "status": "bad"}
    log.info("liara balance check: %s", res.get("state"))
    _liara_cache["last"] = res
    if res["state"] == "ok":
        _liara_cache.update({"at": now, "result": res})
    return {**res, "cached": False, "age_s": 0}
