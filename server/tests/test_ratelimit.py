"""Rate limiter: deterministic clock (no sleeps), real database store, real middleware."""
import asyncio

import httpx
import jwt
import pytest
from sqlalchemy import delete, select

from app import db
from app.config import get_settings
from app.main import app
from app.models import AdminLog, RateHit
from app.security import make_token
from app.services import ratelimit as rl
from app.services.ratelimit import DBStore, MemoryStore, RedisStore, client_ip, limiter

from .conftest import ADMIN, new_player

BASE = 1_699_999_200.0  # aligned to every window used here


class Clock:
    def __init__(self):
        self.t = BASE

    def __call__(self):
        return self.t

    def advance(self, s):
        self.t += s


@pytest.fixture
async def clock(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "rate_limit", True)
    c = Clock()
    monkeypatch.setattr(limiter, "clock", c)
    async with db.SessionLocal() as ses:
        await ses.execute(delete(RateHit))
        await ses.commit()
    limiter.mem = MemoryStore()
    limiter.strict_override = None
    limiter._blk_pending.clear()
    limiter._blk_last.clear()
    limiter._err_logged.clear()
    limiter.reload({})
    yield c
    limiter.strict_override = None
    limiter.reload({})


def mk(ip="127.0.0.1"):
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app, client=(ip, 5000)), base_url="http://test")


def auth(pid):
    return {"Authorization": "Bearer " + make_token(pid, 0)[0]}


ACCUSE = "/v1/cases/c001/accuse"


async def test_accuse_burst_sustained_and_recovery(clock):
    async with mk() as c:
        h = auth("player-a")
        r = await c.post(ACCUSE, headers=h, json={})
        assert r.status_code != 429
        r = await c.post(ACCUSE, headers=h, json={})  # 1 per 3 s
        assert r.status_code == 429
        assert 1 <= r.json()["retry_after"] <= 3
        clock.advance(3)
        assert (await c.post(ACCUSE, headers=h, json={})).status_code != 429
        for _ in range(18):  # up to 20 in the hour
            clock.advance(3)
            assert (await c.post(ACCUSE, headers=h, json={})).status_code != 429
        clock.advance(3)
        r = await c.post(ACCUSE, headers=h, json={})  # the 21st within the hour
        assert r.status_code == 429 and r.json()["retry_after"] > 60
        clock.advance(2 * 3600)
        assert (await c.post(ACCUSE, headers=h, json={})).status_code != 429


async def test_response_shape_and_headers(clock):
    async with mk() as c:
        ok = await c.get("/v1/config")
        assert ok.status_code == 200
        assert int(ok.headers["x-ratelimit-limit"]) > 0 and "x-ratelimit-remaining" in ok.headers
        h = auth("shape")
        await c.post(ACCUSE, headers=h, json={})
        r = await c.post(ACCUSE, headers=h, json={})
        assert r.status_code == 429
        body = r.json()
        assert set(body) == {"error", "message", "retry_after"}
        assert body["error"] == "rate_limited" and body["message"] and isinstance(body["retry_after"], int)
        assert r.headers["retry-after"] == str(body["retry_after"])
        assert r.headers["x-ratelimit-remaining"] == "0" and "x-ratelimit-reset" in r.headers


async def test_keyed_by_player_not_ip(clock):
    async with mk() as c:  # same IP, two players: separate allowances
        for pid in ("p-one", "p-two"):
            assert (await c.post(ACCUSE, headers=auth(pid), json={})).status_code != 429
        assert (await c.post(ACCUSE, headers=auth("p-one"), json={})).status_code == 429
        # no / forged token: keyed by IP, so rotating fake player ids does not help
        forged = lambda i: {"Authorization": "Bearer " + jwt.encode({"sub": f"fake{i}"}, "x" * 40, algorithm="HS256")}
        codes = [(await c.post(ACCUSE, headers=forged(i), json={})).status_code for i in range(3)]
        assert codes[0] != 429 and codes[1] == 429 and codes[2] == 429


async def test_forwarded_for_cannot_be_spoofed(clock):
    async with mk() as c:  # peer is the proxy (private); the proxy appended the real client as the LAST entry
        codes = []
        for i in range(5):
            r = await c.post("/v1/auth/register", json={"device_id": f"dev-spoof-{i}"},
                             headers={"X-Forwarded-For": f"10.9.9.{i}, 203.0.113.7"})
            codes.append(r.status_code)
        assert codes[:3] == [200] * 3 and codes[3] == 429 and codes[4] == 429
    async with mk("8.8.8.8") as c:  # direct public peer: the header is ignored completely
        codes = [(await c.post("/v1/auth/register", json={"device_id": f"dev-direct-{i}"},
                               headers={"X-Forwarded-For": f"10.8.8.{i}"})).status_code for i in range(4)]
        assert codes == [200, 200, 200, 429]


def test_client_ip_rules():
    assert client_ip({"x-forwarded-for": "1.1.1.1, 2.2.2.2"}, "10.0.0.5") == "2.2.2.2"
    assert client_ip({"x-forwarded-for": "1.1.1.1, 2.2.2.2"}, "10.0.0.5", hops=2) == "1.1.1.1"
    assert client_ip({"x-forwarded-for": "1.1.1.1"}, "10.0.0.5", hops=2) == "10.0.0.5"  # fewer entries than hops
    assert client_ip({"x-forwarded-for": "not-an-ip"}, "10.0.0.5") == "10.0.0.5"  # malformed
    assert client_ip({"x-forwarded-for": "1.1.1.1, , "}, "10.0.0.5") == "10.0.0.5"
    assert client_ip({"x-forwarded-for": "9.9.9.9"}, "8.8.4.4") == "8.8.4.4"  # public peer is not a proxy
    assert client_ip({"x-forwarded-for": "2001:db8::1"}, "::1") == "2001:db8::1"
    assert client_ip({}, None) == "unknown"


async def test_register_is_limited_per_device_even_from_new_ips(clock):
    codes = []
    for i in range(4):
        async with mk(f"198.51.100.{i}") as c:
            codes.append((await c.post("/v1/auth/register", json={"device_id": "same-device-1"})).status_code)
    assert codes == [200, 200, 200, 429]


async def test_memory_store_is_bounded_and_expires():
    st = MemoryStore(max_keys=100)
    for i in range(5000):
        await st.hit(f"k{i}", 60, BASE)
    assert len(st.d) <= 100
    await st.hit("old", 60, BASE)
    await st.cleanup(BASE + 1000)  # everything expired
    assert len(st.d) == 0


async def test_db_store_is_atomic_under_concurrency(clock):
    st = DBStore()
    res = await asyncio.gather(*[st.hit("atomic:test", 60, BASE) for _ in range(40)])
    assert sorted(c for c, _ in res) == list(range(1, 41))  # nobody saw the same count twice
    # previous window is returned for sliding tiers
    cur, prev = await st.hit("atomic:test", 60, BASE + 60, 1, True)
    assert (cur, prev) == (1, 40)


async def test_cleanup_deletes_old_rows(clock):
    st = DBStore()
    await st.hit("old:key", 60, BASE - 3 * 86400)
    await st.hit("new:key", 60, BASE)
    assert await st.cleanup(BASE) >= 1
    async with db.SessionLocal() as s:
        keys = set((await s.execute(select(RateHit.key))).scalars())
    assert "old:key" not in keys and "new:key" in keys


class Broken:
    kind = "broken"

    async def hit(self, *a, **k):
        raise RuntimeError("store down")

    get_lock = set_lock = summary = locks_list = hit


async def test_generic_limits_fail_open_register_fails_closed(clock):
    limiter.strict_override = Broken()
    async with mk() as c:
        r = await c.post(ACCUSE, headers=auth("fo"), json={})
        assert r.status_code not in (429, 503)  # fail open
        assert (await c.get("/v1/config")).status_code == 200  # the rest of the API is fine
        r = await c.post("/v1/auth/register", json={"device_id": "dev-closed-1"})
        assert r.status_code == 503 and r.json()["error"] == "try_later"
        r = await c.get("/admin/api/health", headers=ADMIN)  # the lockout counter itself is broken: admin closed
        assert r.status_code == 503


async def test_admin_lockout_after_five_bad_keys(clock):
    async with mk("203.0.113.50") as c:
        for _ in range(5):
            assert (await c.get("/admin/api/health", headers={"X-Admin-Key": "wrong"})).status_code == 403
        r = await c.get("/admin/api/health", headers=ADMIN)  # locked, even with the right key
        assert r.status_code == 429 and 800 < r.json()["retry_after"] <= 900
    async with mk("203.0.113.51") as other:  # another IP is not affected
        r = await other.get("/admin/api/health", headers=ADMIN)
        assert r.status_code == 200
        rlinfo = r.json()["rate_limit"]
        assert rlinfo["blocked_1h"] >= 1 and len(rlinfo["lockouts"]) == 1
        assert rlinfo["top_blocked"] and len(rlinfo["top_blocked"][0]["who"]) <= 9
        lock_id = rlinfo["lockouts"][0]["id"]
        # clear it from the panel (logged in AdminLog)
        assert (await other.post("/admin/api/rate-limit/clear", headers=ADMIN, json={"id": lock_id})).json() == {"cleared": True}
        log = (await other.get("/admin/api/log", headers=ADMIN)).json()
        assert any(x["action"] == "rl_clear" for x in log)
    async with mk("203.0.113.50") as c:
        assert (await c.get("/admin/api/health", headers=ADMIN)).status_code == 200


async def test_admin_lock_expires_after_15_minutes(clock):
    async with mk("203.0.113.60") as c:
        for _ in range(5):
            await c.get("/admin/api/health", headers={"X-Admin-Key": "bad"})
        assert (await c.get("/admin/api/health", headers=ADMIN)).status_code == 429
        clock.advance(901)
        assert (await c.get("/admin/api/health", headers=ADMIN)).status_code == 200


async def test_correct_admin_key_never_locks(clock):
    async with mk("203.0.113.70") as c:
        for _ in range(40):
            clock.advance(1)
            assert (await c.get("/admin/api/health", headers=ADMIN)).status_code == 200


async def test_exempt_routes_and_global_ceiling(clock):
    async with mk() as c:
        for path in ("/health", "/privacy", "/terms"):
            for _ in range(150):
                assert (await c.get(path)).status_code == 200
        codes = [(await c.get("/v1/config")).status_code for _ in range(130)]
        assert 429 in codes  # the global per-IP burst ceiling (100 per 5 s)
        clock.advance(25)
        assert (await c.get("/v1/config")).status_code == 200


async def test_kill_switch(clock, monkeypatch):
    monkeypatch.setattr(get_settings(), "rate_limit", False)
    async with mk() as c:
        for _ in range(6):
            assert (await c.post(ACCUSE, headers=auth("ks"), json={})).status_code != 429


def test_env_overrides():
    limiter.reload({"RL_ACCUSE": "2/3,50/3600", "RL_HINT": "off", "RL_READ": "garbage"})
    p = limiter.policies
    assert p["accuse"].tiers == ((2, 3), (50, 3600)) and p["hint"] is None
    assert p["read"] == rl.DEFAULTS["read"]  # bad value ignored
    limiter.reload({})


async def test_redis_store_with_fake_client():
    class Fake:
        def __init__(self):
            self.d = {}

        async def incrby(self, k, n):
            self.d[k] = int(self.d.get(k, 0)) + n
            return self.d[k]

        async def expire(self, k, s):
            pass

        async def get(self, k):
            return self.d.get(k)

        async def set(self, k, v, ex=None):
            self.d[k] = v

        async def delete(self, k):
            self.d.pop(k, None)

        async def scan_iter(self, match):
            import fnmatch
            for k in list(self.d):
                if fnmatch.fnmatch(k, match):
                    yield k

    st = RedisStore(Fake())
    assert await st.hit("a", 60, BASE) == (1, 0)
    assert await st.hit("a", 60, BASE, 2) == (3, 0)
    assert await st.hit("a", 60, BASE + 60, 1, True) == (1, 3)
    await st.set_lock("adm:x", BASE + 900)
    assert await st.get_lock("adm:x") == BASE + 900
    assert [k for k, _ in await st.locks_list(BASE)] == ["adm:x"]
    await st.clear_lock("adm:x")
    assert await st.get_lock("adm:x") == 0
    await st.hit("blk:accuse:abc", 600, BASE, 4)
    assert await st.summary("blk:", BASE - 10, 5) == (4, [("blk:accuse:abc", 4)])


# ---- app info reported by the phone
async def test_client_info_is_stored_validated_and_shown_to_admin(client):
    p = await new_player(client, "device-client-1")
    good = {"app_version": "1.21.0", "build": 39, "platform": "android", "os_version": "Android 14 (SDK 34)",
            "device_model": "samsung SM-A546E"}
    assert (await client.post("/v1/me/client", json=good, headers=p["headers"])).status_code == 200
    d = (await client.get(f"/admin/api/players/{p['player_id']}", headers=ADMIN)).json()["player"]["client"]
    assert d["version"] == "1.21.0" and d["build"] == 39 and d["device_model"] == "samsung SM-A546E"
    versions = (await client.get("/admin/api/overview", headers=ADMIN)).json()["versions"]
    assert {"version": "1.21.0", "build": 39, "players": 1} in versions
    for bad in ({**good, "app_version": "x" * 30}, {**good, "device_model": "<script>alert(1)</script>"},
                {**good, "os_version": "a" * 33}, {**good, "build": -1}, {**good, "platform": "Android 1"}):
        assert (await client.post("/v1/me/client", json=bad, headers=p["headers"])).status_code == 422
    assert (await client.post("/v1/me/client", json=good)).status_code == 401
