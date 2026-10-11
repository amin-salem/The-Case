"""Rate limiter: layered, multi-worker safe, fail-safe. Docs: docs/operations.md «Rate limits».

Pieces
- POLICIES: the one table of limits (each overridable with an env variable RL_<NAME>="limit/seconds,limit/seconds").
  A policy has one or more tiers (burst + sustained). Tiers with limit >= 10 use a sliding-window estimate
  (current + weighted previous window); smaller tiers use exact fixed windows (a sliding estimate is useless for "1 per 3 s").
- ROUTES: which request goes to which policy. Every request also passes the global per-IP ceiling.
- Stores: MemoryStore (per worker, bounded, generous limits), DBStore (rate_hits table, atomic upsert,
  shared by all workers) and RedisStore (used automatically for the strict limits when REDIS_URL is set).
- Identity: player id from a VALID JWT, else the client IP. The IP comes from X-Forwarded-For only from the last
  trusted hop (see client_ip); keys are salted hashes, never raw IPs.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import ipaddress
import json
import logging
import math
import os
import re
import time
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Callable

import jwt

log = logging.getLogger("ratelimit")

MESSAGE = "تعداد درخواست‌ها زیاد بود. چند لحظه صبر کن و دوباره امتحان کن."
UNAVAILABLE_MESSAGE = "الان نمی‌شود. کمی بعد دوباره امتحان کن."
RETENTION = 7200  # seconds a counter row is kept (longest window is 3600, plus the previous window)
DEV_ADMIN_KEY = "change-me-admin-dev-only"

EXEMPT_PATHS = {"/health", "/privacy", "/terms", "/delete-account", "/admin/ui", "/docs", "/openapi.json",
                "/docs/oauth2-redirect", "/favicon.ico", "/robots.txt"}
EXEMPT_PREFIXES = ("/static/",)


# --------------------------------------------------------------------------- policies
@dataclass(frozen=True)
class Policy:
    name: str
    tiers: tuple[tuple[int, int], ...]  # (max requests, window seconds): burst first, then sustained
    scope: str = "player"  # "ip" | "player" (player id when logged in, else the IP) | "key" (caller gives the key)
    store: str = "mem"  # "mem" = per worker, bounded | "strict" = shared (Redis, else the database)
    fail: str = "open"  # what a broken store does: "open" = allow, "closed" = refuse (503)
    note: str = ""


def _p(name, tiers, scope="player", store="mem", fail="open", note=""):
    return Policy(name, tuple(tiers), scope, store, fail, note)


DEFAULTS: dict[str, Policy] = {p.name: p for p in [
    _p("global_ip", [(100, 5), (600, 60)], "ip", note="every request, per IP"),
    # accounts: very strict
    _p("register", [(3, 60), (20, 3600)], "ip", "strict", "closed", "new account, per IP"),
    _p("register_device", [(3, 3600)], "key", "strict", "closed", "new account, per device_id (extra, client-supplied)"),
    _p("login", [(20, 60), (60, 600)], "ip", "strict", note="login / email login, per IP"),
    _p("login_target", [(20, 600)], "key", "strict", note="login attempts against one account / email / code"),
    _p("transfer", [(5, 300)], "ip", "strict", note="use a transfer code, per IP"),
    _p("account", [(5, 600)], "player", "strict", note="set email+password, make a transfer code"),
    # game actions that cost or pay coins: strict per player
    _p("accuse", [(1, 3), (20, 3600)], "player", "strict", note="accusations"),
    _p("hint", [(2, 5), (60, 3600)], "player", "strict"),
    _p("unlock", [(3, 10), (60, 3600)], "player", "strict", note="unlock case / riddle"),
    _p("riddle_answer", [(2, 5), (60, 600)], "player", "strict"),
    _p("wallet", [(5, 10), (60, 600)], "player", "strict", note="streak freeze, ad reward, mission chest"),
    _p("purchase", [(3, 30), (20, 3600)], "player", "strict", note="purchase verification"),
    _p("story", [(3, 10), (60, 3600)], "player", "strict", note="story open / skip"),
    _p("claim", [(5, 10), (60, 600)], "player", "strict", note="inbox claim"),
    _p("referral", [(3, 60), (10, 600)], "player", "strict", note="redeem an invite code"),
    _p("client_info", [(2, 60), (10, 3600)], "player", note="app reports its version"),
    # generous
    _p("read", [(60, 10), (1500, 600)], "player", note="GET under /v1"),
    _p("write", [(30, 10), (900, 600)], "player", note="other POST/PATCH under /v1"),
    # admin
    _p("admin", [(60, 10), (2000, 600)], "ip", note="admin API with a correct key"),
    _p("admin_fail", [(5, 900)], "ip", "strict", "closed", "wrong X-Admin-Key: N failures in the window lock the IP for the window"),
]}

ROUTES: list[tuple[str, re.Pattern, str]] = [(m, re.compile(rx), pol) for m, rx, pol in [
    ("POST", r"^/v1/auth/register$", "register"),
    ("POST", r"^/v1/auth/(login|login/email)$", "login"),
    ("POST", r"^/v1/auth/transfer$", "transfer"),
    ("POST", r"^/v1/auth/(email|transfer-code)$", "account"),
    ("POST", r"^/v1/cases/[^/]+/accuse$", "accuse"),
    ("POST", r"^/v1/cases/[^/]+/hint$", "hint"),
    ("POST", r"^/v1/(cases|riddles)/[^/]+/unlock$", "unlock"),
    ("POST", r"^/v1/riddles/[^/]+/answer$", "riddle_answer"),
    ("POST", r"^/v1/(wallet/.+|missions/claim)$", "wallet"),
    ("POST", r"^/v1/purchases/verify$", "purchase"),
    ("POST", r"^/v1/story/[^/]+/(open|skip)$", "story"),
    ("POST", r"^/v1/inbox/[^/]+/claim$", "claim"),
    ("POST", r"^/v1/referrals/redeem$", "referral"),
    ("POST", r"^/v1/me/client$", "client_info"),
    ("GET", r"^/v1/", "read"),
    ("*", r"^/v1/", "write"),
    ("*", r"^/admin(/|$)", "admin"),
]]


def _parse_tiers(text: str) -> tuple[tuple[int, int], ...]:
    tiers = []
    for part in text.split(","):
        n, w = part.strip().split("/")
        n, w = int(n), int(w)
        if not (1 <= n <= 1_000_000 and 1 <= w <= 3600):
            raise ValueError("out of range")
        tiers.append((n, w))
    if not tiers:
        raise ValueError("empty")
    return tuple(tiers)


def load_policies(env=None) -> dict[str, Policy | None]:
    """DEFAULTS with RL_<NAME> overrides applied. "off" disables a policy; a bad value is logged and ignored."""
    env = os.environ if env is None else env
    out: dict[str, Policy | None] = {}
    for name, pol in DEFAULTS.items():
        raw = env.get("RL_" + name.upper())
        if raw is not None and raw.strip():
            if raw.strip().lower() == "off":
                out[name] = None
                continue
            try:
                pol = Policy(pol.name, _parse_tiers(raw), pol.scope, pol.store, pol.fail, pol.note)
            except Exception:
                log.warning("ratelimit: ignoring bad RL_%s", name.upper())
        out[name] = pol
    return out


# --------------------------------------------------------------------------- identity
def _trusted_peer(peer: str, proxies: list) -> bool:
    try:
        ip = ipaddress.ip_address(peer)
    except ValueError:
        return False
    if proxies:
        return any(ip in net for net in proxies)
    return ip.is_private or ip.is_loopback or ip.is_link_local


def client_ip(headers: dict, peer: str | None, hops: int = 1, proxies: list | None = None) -> str:
    """The caller's IP. X-Forwarded-For is read only when the socket peer is a trusted proxy, and then only the entry
    added by the last trusted hop (hops=1: the LAST entry); what the client wrote itself sits further left and is
    ignored. Anything malformed falls back to the socket address."""
    peer = peer or "unknown"
    xff = headers.get("x-forwarded-for")
    if not xff or hops < 1 or not _trusted_peer(peer, proxies or []):
        return peer
    parts = [p.strip() for p in xff.split(",")]
    if len(parts) < hops:
        return peer
    try:
        return str(ipaddress.ip_address(parts[-hops]))
    except ValueError:
        return peer


def player_id_from_auth(authorization: str | None, secret: str) -> str | None:
    """The player id from a VALID, unexpired token (signature checked), else None. Forged ids never count."""
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    try:
        data = jwt.decode(authorization[7:].strip(), secret, algorithms=["HS256"])
        sub = data.get("sub")
        return str(sub) if sub else None
    except Exception:
        return None


# --------------------------------------------------------------------------- stores
class MemoryStore:
    """Per worker. Bounded: expired entries are dropped first, then the least recently used, so a flood of new keys
    cannot grow memory past max_keys. With N workers the effective limit is up to N times the configured one."""

    kind = "memory"

    def __init__(self, max_keys: int = 20000):
        self.max_keys = max_keys
        self.d: OrderedDict[str, list] = OrderedDict()  # key -> [window, window_start, current, previous]
        self.locks: OrderedDict[str, float] = OrderedDict()

    async def hit(self, key, window, now, n=1, want_prev=False):
        ws = int(now // window) * window
        e = self.d.get(key)
        if e is None or e[1] != ws:
            prev = e[2] if e is not None and e[1] == ws - window else 0
            e = [window, ws, 0, prev]
        e[2] += n
        self.d[key] = e
        self.d.move_to_end(key)
        if len(self.d) > self.max_keys:
            self._evict(now)
        return e[2], e[3]

    def _evict(self, now):
        for k in [k for k, e in self.d.items() if e[1] + 2 * e[0] <= now]:
            del self.d[k]
        target = int(self.max_keys * 0.9)
        while len(self.d) > target:
            self.d.popitem(last=False)

    async def get_lock(self, key):
        return self.locks.get(key, 0.0)

    async def set_lock(self, key, until):
        self.locks[key] = until
        while len(self.locks) > self.max_keys:
            self.locks.popitem(last=False)

    async def clear_lock(self, key):
        self.locks.pop(key, None)

    async def reset(self, key):
        self.d.pop(key, None)

    async def locks_list(self, now):
        return [(k, u) for k, u in self.locks.items() if u > now]

    async def summary(self, prefix, since, k):
        agg: dict[str, int] = {}
        for key, e in self.d.items():
            if key.startswith(prefix) and e[1] >= since:
                agg[key] = agg.get(key, 0) + e[2]
        return sum(agg.values()), sorted(agg.items(), key=lambda kv: -kv[1])[:k]

    async def cleanup(self, now):
        before = len(self.d)
        self._evict(now) if before else None
        for k in [k for k, u in self.locks.items() if u < now - RETENTION]:
            del self.locks[k]
        return before - len(self.d)


class DBStore:
    """Table rate_hits(key, window_start, count): one atomic INSERT .. ON CONFLICT DO UPDATE .. RETURNING per hit,
    the same statement on Postgres and SQLite. Locks are rows whose window_start is the unlock time."""

    kind = "database"

    @staticmethod
    def _insert():
        from .. import db
        if db.engine.dialect.name == "postgresql":
            from sqlalchemy.dialects.postgresql import insert
        else:
            from sqlalchemy.dialects.sqlite import insert
        return insert

    async def hit(self, key, window, now, n=1, want_prev=False):
        from sqlalchemy import select
        from .. import db
        from ..models import RateHit

        ws = int(now // window) * window
        t = RateHit.__table__
        stmt = self._insert()(t).values(key=key, window_start=ws, count=n)
        stmt = stmt.on_conflict_do_update(index_elements=[t.c.key, t.c.window_start],
                                          set_={"count": t.c.count + n}).returning(t.c.count)
        async with db.SessionLocal() as s:
            cur = (await s.execute(stmt)).scalar_one()
            prev = 0
            if want_prev:
                prev = await s.scalar(select(RateHit.count).where(RateHit.key == key, RateHit.window_start == ws - window)) or 0
            await s.commit()
        return int(cur), int(prev)

    async def get_lock(self, key):
        from sqlalchemy import func, select
        from .. import db
        from ..models import RateHit

        async with db.SessionLocal() as s:
            return float(await s.scalar(select(func.max(RateHit.window_start)).where(RateHit.key == "lock:" + key)) or 0)

    async def set_lock(self, key, until):
        from .. import db
        from ..models import RateHit

        t = RateHit.__table__
        stmt = self._insert()(t).values(key="lock:" + key, window_start=int(until), count=1)
        stmt = stmt.on_conflict_do_nothing(index_elements=[t.c.key, t.c.window_start])
        async with db.SessionLocal() as s:
            await s.execute(stmt)
            await s.commit()

    async def clear_lock(self, key):
        await self._delete("lock:" + key)

    async def reset(self, key):
        await self._delete(key)

    async def _delete(self, key):
        from sqlalchemy import delete
        from .. import db
        from ..models import RateHit

        async with db.SessionLocal() as s:
            await s.execute(delete(RateHit).where(RateHit.key == key))
            await s.commit()

    async def locks_list(self, now):
        from sqlalchemy import func, select
        from .. import db
        from ..models import RateHit

        async with db.SessionLocal() as s:
            rows = (await s.execute(select(RateHit.key, func.max(RateHit.window_start)).where(RateHit.key.like("lock:%"))
                                    .group_by(RateHit.key).having(func.max(RateHit.window_start) > int(now)))).all()
        return [(k[5:], float(u)) for k, u in rows]

    async def summary(self, prefix, since, k):
        from sqlalchemy import func, select
        from .. import db
        from ..models import RateHit

        cond = (RateHit.key.like(prefix + "%"), RateHit.window_start >= int(since))
        async with db.SessionLocal() as s:
            total = await s.scalar(select(func.coalesce(func.sum(RateHit.count), 0)).where(*cond)) or 0
            rows = (await s.execute(select(RateHit.key, func.sum(RateHit.count).label("n")).where(*cond)
                                    .group_by(RateHit.key).order_by(func.sum(RateHit.count).desc()).limit(k))).all()
        return int(total), [(key, int(n)) for key, n in rows]

    async def cleanup(self, now):
        from sqlalchemy import delete
        from .. import db
        from ..models import RateHit

        async with db.SessionLocal() as s:
            res = await s.execute(delete(RateHit).where(RateHit.window_start < int(now) - RETENTION))
            await s.commit()
        return res.rowcount or 0


class RedisStore:
    """Used automatically when REDIS_URL is set. Keys expire by themselves (TTL), so cleanup does nothing."""

    kind = "redis"

    def __init__(self, client):
        self.r = client

    async def hit(self, key, window, now, n=1, want_prev=False):
        ws = int(now // window) * window
        k = f"rl:{key}:{ws}"
        cur = int(await self.r.incrby(k, n))
        await self.r.expire(k, window * 2 + 5)
        prev = 0
        if want_prev:
            prev = int(await self.r.get(f"rl:{key}:{ws - window}") or 0)
        return cur, prev

    async def get_lock(self, key):
        return float(await self.r.get("rl:lock:" + key) or 0)

    async def set_lock(self, key, until):
        await self.r.set("rl:lock:" + key, int(until), ex=max(1, int(until - time.time()) + 5))

    async def clear_lock(self, key):
        await self.r.delete("rl:lock:" + key)

    async def reset(self, key):
        async for k in self.r.scan_iter(match=f"rl:{key}:*"):
            await self.r.delete(k)

    async def locks_list(self, now):
        out = []
        async for k in self.r.scan_iter(match="rl:lock:*"):
            k = k.decode() if isinstance(k, bytes) else k
            until = float(await self.r.get(k) or 0)
            if until > now:
                out.append((k[len("rl:lock:"):], until))
        return out

    async def summary(self, prefix, since, k):
        agg: dict[str, int] = {}
        async for raw in self.r.scan_iter(match=f"rl:{prefix}*"):
            raw = raw.decode() if isinstance(raw, bytes) else raw
            body, ws = raw[3:].rsplit(":", 1)
            if int(ws) >= since:
                agg[body] = agg.get(body, 0) + int(await self.r.get(raw) or 0)
        return sum(agg.values()), sorted(agg.items(), key=lambda kv: -kv[1])[:k]

    async def cleanup(self, now):
        return 0


# --------------------------------------------------------------------------- the limiter
@dataclass
class Verdict:
    allowed: bool
    limit: int
    remaining: int
    reset: int  # seconds until the window ends
    retry_after: int = 0
    policy: str = ""

    def headers(self) -> list[tuple[bytes, bytes]]:
        h = [(b"x-ratelimit-limit", str(self.limit).encode()), (b"x-ratelimit-remaining", str(self.remaining).encode()),
             (b"x-ratelimit-reset", str(self.reset).encode())]
        if not self.allowed:
            h.append((b"retry-after", str(self.retry_after).encode()))
        return h


class RateLimited(Exception):
    """Raised by enforce() / the limiter; app.main turns it into the JSON 429 (or 503) response."""

    def __init__(self, retry_after: int, status: int = 429, verdict: Verdict | None = None):
        self.retry_after, self.status, self.verdict = retry_after, status, verdict


def body_for(status: int, retry_after: int) -> dict:
    if status == 429:
        return {"error": "rate_limited", "message": MESSAGE, "retry_after": retry_after}
    return {"error": "try_later", "message": UNAVAILABLE_MESSAGE, "retry_after": retry_after}


class Limiter:
    def __init__(self):
        self.clock: Callable[[], float] = time.time  # tests replace it: no sleeps
        self.mem = MemoryStore()
        self.strict_override = None  # tests; normally Redis if REDIS_URL, else the database
        self._strict = None
        self._policies: dict[str, Policy | None] | None = None
        self._err_logged: dict[str, float] = {}
        self._blk_pending: dict[str, int] = {}
        self._blk_last: dict[str, float] = {}

    # -- setup
    @property
    def policies(self) -> dict[str, Policy | None]:
        if self._policies is None:
            self._policies = load_policies()
        return self._policies

    def reload(self, env=None) -> None:
        self._policies = load_policies(env)

    @property
    def strict(self):
        if self.strict_override is not None:
            return self.strict_override
        if self._strict is None:
            self._strict = self._make_strict()
        return self._strict

    def _make_strict(self):
        from ..config import get_settings
        url = get_settings().redis_url
        if url:
            try:
                import redis.asyncio as aioredis
                return RedisStore(aioredis.from_url(url, socket_timeout=0.5, socket_connect_timeout=0.5))
            except Exception as e:  # missing package or bad URL: do not stop the game, use the database
                log.warning("ratelimit: Redis unavailable (%s), using the database store", type(e).__name__)
        return DBStore()

    def _store(self, pol: Policy):
        return self.strict if pol.store == "strict" else self.mem

    @staticmethod
    def hash(value: str) -> str:
        from ..config import get_settings
        return hashlib.sha256((get_settings().jwt_secret + "|" + value).encode()).hexdigest()[:16]

    # -- core
    async def _check(self, pol: Policy, ident: str) -> Verdict:
        now = self.clock()
        store = self._store(pol)
        best: Verdict | None = None
        for i, (limit, window) in enumerate(pol.tiers):
            weighted = limit >= 10
            cur, prev = await store.hit(f"{pol.name}:{i}:{ident}", window, now, 1, weighted)
            ws = int(now // window) * window
            reset = max(1, math.ceil(ws + window - now))
            used = cur + prev * (1 - (now - ws) / window) if weighted else cur
            if used > limit:
                return Verdict(False, limit, 0, reset, reset, pol.name)
            v = Verdict(True, limit, max(0, limit - math.ceil(used)), reset, 0, pol.name)
            if best is None or v.remaining / v.limit < best.remaining / best.limit:
                best = v
        return best

    async def evaluate(self, pol: Policy | None, ident: str) -> Verdict | None:
        """One policy for one identity. A broken store fails open (None) unless the policy fails closed (RateLimited 503)."""
        if pol is None:
            return None
        try:
            v = await self._check(pol, ident)
        except Exception as e:
            self._log_store_error(pol, e)
            if pol.fail == "closed":
                raise RateLimited(30, 503)
            return None
        if not v.allowed:
            await self._record_block(pol.name, ident)
        return v

    def _log_store_error(self, pol: Policy, e: Exception) -> None:
        now = self.clock()
        if now - self._err_logged.get(pol.name, -1e9) > 300:  # once per policy per 5 minutes
            self._err_logged[pol.name] = now
            log.error("ratelimit store_error policy=%s fail=%s err=%s", pol.name, pol.fail, type(e).__name__)

    async def _record_block(self, policy: str, ident: str) -> None:
        """Count blocks for the admin Health screen. Written to the shared store at most every 10 s per key."""
        try:
            now = self.clock()
            key = f"blk:{policy}:{ident}"
            if len(self._blk_pending) > 5000:
                self._blk_pending.clear()
                self._blk_last.clear()
            self._blk_pending[key] = self._blk_pending.get(key, 0) + 1
            if now - self._blk_last.get(key, -1e9) >= 10:
                n = self._blk_pending.pop(key)
                self._blk_last[key] = now
                await self.strict.hit(key, 600, now, n, False)
            log.info("ratelimit blocked policy=%s who=%s", policy, ident[:9])
        except Exception:
            pass

    # -- a request
    async def handle(self, method: str, path: str, headers: dict, peer: str | None) -> tuple[Verdict | None, RateLimited | None]:
        """Returns (verdict to put in the headers, a refusal or None)."""
        from ..config import get_settings
        s = get_settings()
        proxies = [ipaddress.ip_network(x.strip(), strict=False) for x in s.rate_trusted_proxies.split(",") if x.strip()]
        ip = client_ip(headers, peer, s.rate_trusted_hops, proxies)
        iph = self.hash(ip)
        try:
            if path.startswith("/admin"):
                allow = {x.strip() for x in s.rate_admin_allow_ips.split(",") if x.strip()}
                if ip not in allow:
                    blocked = await self._admin_gate(iph, headers.get("x-admin-key", ""), s.admin_api_key)
                    if blocked is not None:
                        return None, blocked
            v = await self.evaluate(self.policies.get("global_ip"), "i" + iph)
            if v is not None and not v.allowed:
                return v, RateLimited(v.retry_after, 429, v)
            for m, rx, name in ROUTES:
                if (m == "*" or m == method) and rx.match(path):
                    pol = self.policies.get(name)
                    if pol is None:
                        break
                    pid = player_id_from_auth(headers.get("authorization"), s.jwt_secret) if pol.scope == "player" else None
                    ident = ("p" + self.hash(pid)) if pid else ("i" + iph)
                    rv = await self.evaluate(pol, ident)
                    if rv is not None:
                        if not rv.allowed:
                            return rv, RateLimited(rv.retry_after, 429, rv)
                        v = rv
                    break
            return v, None
        except RateLimited as e:  # a fail-closed policy with a broken store
            return None, e

    async def _admin_gate(self, iph: str, supplied: str, real_key: str) -> RateLimited | None:
        """Wrong X-Admin-Key counts as a failure; after N the IP is locked (even for the right key). Fail CLOSED for
        /admin only if the lockout counter itself is broken."""
        pol = self.policies.get("admin_fail")
        if pol is None:
            return None
        key = "adm:" + iph
        now = self.clock()
        try:
            store = self.strict
            until = await store.get_lock(key)
            if until > now:
                await self._record_block("admin_lock", iph)
                return RateLimited(max(1, math.ceil(until - now)), 429)
            valid = real_key != DEV_ADMIN_KEY and hmac.compare_digest(supplied.encode(), real_key.encode())
            if not valid:
                limit, window = pol.tiers[0]
                cur, _ = await store.hit(f"admin_fail:0:{iph}", window, now, 1, False)
                if cur >= limit:
                    await store.set_lock(key, now + window)
                    log.warning("ratelimit admin_lockout who=%s seconds=%d", iph[:8], window)
        except Exception as e:
            self._log_store_error(pol, e)
            return RateLimited(30, 503)
        return None

    # -- named-policy API for other code (anti-cheat reuses this)
    async def enforce(self, name: str, raw_key: str) -> None:
        from ..config import get_settings
        if not get_settings().rate_limit:
            return
        v = await self.evaluate(self.policies.get(name), "k" + self.hash(raw_key))
        if v is not None and not v.allowed:
            raise RateLimited(v.retry_after, 429, v)

    # -- admin panel
    async def admin_summary(self) -> dict:
        now = self.clock()
        out = {"enabled": True, "store": self.strict.kind, "blocked_1h": 0, "top_blocked": [], "lockouts": []}
        try:
            total, top = await self.strict.summary("blk:", now - 3600, 5)
            out["blocked_1h"] = total
            out["top_blocked"] = [{"policy": k.split(":")[1], "who": k.split(":")[2][:9], "count": n} for k, n in top]
            out["lockouts"] = [{"id": k[4:], "who": k[4:12], "seconds_left": int(u - now)}
                               for k, u in await self.strict.locks_list(now)]
        except Exception as e:
            out["error"] = type(e).__name__
        return out

    async def clear_lockout(self, lock_id: str) -> bool:
        """lock_id: the id shown in admin_summary (the hash of the IP). True if a lockout existed."""
        now = self.clock()
        existed = any(k == "adm:" + lock_id for k, u in await self.strict.locks_list(now))
        await self.strict.clear_lock("adm:" + lock_id)
        await self.strict.reset(f"admin_fail:0:{lock_id}")
        return existed

    async def cleanup(self) -> int:
        now = self.clock()
        n = await self.mem.cleanup(now)
        return n + await self.strict.cleanup(now)


limiter = Limiter()


async def enforce(name: str, raw_key: str) -> None:
    await limiter.enforce(name, raw_key)


async def cleanup_loop() -> None:
    """Hourly: delete old rate_hits rows and expired memory entries (safe to run in every worker)."""
    while True:
        await asyncio.sleep(3600)
        try:
            await limiter.cleanup()
        except Exception as e:
            log.warning("ratelimit cleanup failed: %s", type(e).__name__)


# --------------------------------------------------------------------------- ASGI middleware
def is_exempt(path: str) -> bool:
    return path in EXEMPT_PATHS or path.startswith(EXEMPT_PREFIXES)


def rate_limited_response(exc: RateLimited):
    from starlette.responses import JSONResponse
    h = {"Retry-After": str(exc.retry_after)}
    if exc.verdict is not None:
        h.update({k.decode(): v.decode() for k, v in exc.verdict.headers() if k != b"retry-after"})
    return JSONResponse(body_for(exc.status, exc.retry_after), status_code=exc.status, headers=h)


class RateLimitMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        from ..config import get_settings
        if scope["type"] != "http" or not get_settings().rate_limit or is_exempt(scope["path"]):
            return await self.app(scope, receive, send)
        headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope.get("headers", [])
                   if k in (b"x-forwarded-for", b"authorization", b"x-admin-key")}
        peer = scope["client"][0] if scope.get("client") else None
        verdict, refusal = await limiter.handle(scope["method"], scope["path"], headers, peer)
        if refusal is not None:
            return await rate_limited_response(refusal)(scope, receive, send)
        if verdict is None:
            return await self.app(scope, receive, send)
        extra = verdict.headers()

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                message = {**message, "headers": list(message.get("headers", [])) + extra}
            await send(message)

        await self.app(scope, receive, send_with_headers)
