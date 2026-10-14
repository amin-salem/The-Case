"""Capacity work (docs/operations.md «Capacity»): connection pool, shared caches, bulk test players, the load-test tool."""
import asyncio
import importlib.util
from datetime import timedelta
from pathlib import Path

import httpx

from app import cache, content, db
from app.cache import TTLCache
from app.main import app
from app.models import CaseProgress
from app.routers import cases as cases_router
from app.routers import meta

from .conftest import ADMIN, new_player


# --------------------------------------------------------------------------- connection pool
def test_pool_settings_defaults_bounds_and_bad_values(monkeypatch):
    for k in ("DB_POOL_SIZE", "DB_MAX_OVERFLOW", "DB_POOL_TIMEOUT", "DB_POOL_RECYCLE"):
        monkeypatch.delenv(k, raising=False)
    s = db.pool_settings()
    assert (s["pool_size"], s["max_overflow"], s["pool_timeout"], s["pool_recycle"]) == (5, 5, 10, 1800)
    assert s["pool_pre_ping"] is True
    monkeypatch.setenv("DB_POOL_SIZE", "3")
    monkeypatch.setenv("DB_MAX_OVERFLOW", "0")
    monkeypatch.setenv("DB_POOL_TIMEOUT", "4")
    s = db.pool_settings()
    assert (s["pool_size"], s["max_overflow"], s["pool_timeout"]) == (3, 0, 4)
    monkeypatch.setenv("DB_POOL_SIZE", "100000")  # absurd values are clamped, garbage falls back to the default
    monkeypatch.setenv("DB_MAX_OVERFLOW", "many")
    s = db.pool_settings()
    assert s["pool_size"] == 50 and s["max_overflow"] == 5


def test_postgres_engine_uses_the_bounded_pool(monkeypatch):
    monkeypatch.setenv("DB_POOL_SIZE", "4")
    monkeypatch.setenv("DB_MAX_OVERFLOW", "2")
    monkeypatch.setenv("DB_POOL_TIMEOUT", "7")
    eng = db._make_engine("postgresql+asyncpg://u:p@localhost:5432/x")  # no connection is made
    pool = eng.sync_engine.pool
    assert pool.size() == 4 and pool._max_overflow == 2 and pool.timeout() == 7


# --------------------------------------------------------------------------- the cache itself
class Clock:
    def __init__(self):
        self.t = 100.0

    def __call__(self):
        return self.t


async def test_cache_ttl_bound_and_single_loader():
    c = TTLCache("t1", ttl=10, max_size=2)
    clk = Clock()
    c.clock = clk
    calls = []

    async def loader():
        calls.append(1)
        await asyncio.sleep(0)
        return len(calls)

    assert await c.get_or_load("a", loader) == 1
    assert await c.get_or_load("a", loader) == 1  # cached
    clk.t += 11
    assert await c.get_or_load("a", loader) == 2  # expired
    calls.clear()
    c.clear()
    results = await asyncio.gather(*(c.get_or_load("b", loader) for _ in range(20)))
    assert len(calls) == 1 and set(results) == {1}  # twenty callers, one load
    for k in ("x", "y", "z"):
        c.put_sync(k, k)
    assert len(c._d) <= 2  # bounded


async def test_cache_valid_until_and_clock_going_back():
    c = TTLCache("t2", ttl=1000, max_size=4)
    c.clock = Clock()
    n = [0]

    async def loader():
        n[0] += 1
        return n[0]

    from datetime import datetime, timezone
    t0 = datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc)
    until = t0 + timedelta(minutes=5)
    assert await c.get_or_load("k", loader, now_wall=t0, valid_until_of=lambda v: until) == 1
    assert await c.get_or_load("k", loader, now_wall=t0 + timedelta(minutes=4), valid_until_of=lambda v: until) == 1
    assert await c.get_or_load("k", loader, now_wall=t0 + timedelta(minutes=5), valid_until_of=lambda v: until) == 2  # the boundary
    assert await c.get_or_load("k", loader, now_wall=t0 - timedelta(hours=1), valid_until_of=lambda v: until) == 3  # time went back


async def test_cache_switch_off_always_loads(monkeypatch):
    monkeypatch.setattr(cache, "ENABLED", False)
    c = TTLCache("t3", ttl=10)
    n = [0]

    async def loader():
        n[0] += 1
        return n[0]

    assert await c.get_or_load("k", loader) == 1 and await c.get_or_load("k", loader) == 2


# --------------------------------------------------------------------------- /v1/config
async def test_config_pieces_are_cached_but_a_new_case_appears_on_time(client, monkeypatch):
    cs = content.all_cases()
    target = cs[5]
    opens = content.opens_at(target)
    before, after = opens - timedelta(minutes=1), opens + timedelta(minutes=1)
    monkeypatch.setattr(content, "now_local", lambda: before)
    a = (await client.get("/v1/config")).json()
    hits = meta._public.hits
    b = (await client.get("/v1/config")).json()
    assert meta._public.hits == hits + 1  # the second call came from the cache
    assert a["next_case_at"] == b["next_case_at"] == int(opens.timestamp())
    assert a["today"] == before.date().isoformat()
    monkeypatch.setattr(content, "now_local", lambda: after)  # the clock passes the opening: nothing stale may be served
    c2 = (await client.get("/v1/config")).json()
    assert c2["next_case_at"] > int(opens.timestamp())
    assert c2["server_time"] == int(after.timestamp())
    assert {"notify", "upcoming", "economy"} <= set(c2) and c2["economy"]["unlock_cost"] > 0


async def test_admin_config_change_is_visible_at_once(client):
    await client.delete("/admin/config/maintenance", headers=ADMIN)
    assert (await client.get("/v1/config")).json()["maintenance"] is False  # now cached
    r = await client.put("/admin/config", headers=ADMIN, json={"values": {"maintenance": True}})
    assert r.status_code == 200
    try:
        assert (await client.get("/v1/config")).json()["maintenance"] is True
    finally:
        assert (await client.delete("/admin/config/maintenance", headers=ADMIN)).status_code == 200
    assert (await client.get("/v1/config")).json()["maintenance"] is False


# --------------------------------------------------------------------------- case list
async def test_solver_counts_are_shared_for_a_short_time_then_refresh(client):
    p = await new_player(client, device="device-cap-1")
    case_id = "c-cap-test"
    async with db.SessionLocal() as s:
        first = await cases_router._solver_counts(s)
        assert first.get(case_id, 0) == 0
        s.add(CaseProgress(player_id=p["player_id"], case_id=case_id, solved=True))
        await s.commit()
        assert (await cases_router._solver_counts(s)).get(case_id, 0) == 0  # cached for this worker
        cases_router._solvers.clear()
        assert (await cases_router._solver_counts(s)).get(case_id, 0) == 1
        await s.execute(CaseProgress.__table__.delete().where(CaseProgress.case_id == case_id))
        await s.commit()


async def test_case_list_still_has_the_per_player_state(client):
    a = await new_player(client, device="device-cap-a")
    b = await new_player(client, device="device-cap-b")
    la = (await client.get("/v1/cases", headers=a["headers"])).json()
    lb = (await client.get("/v1/cases", headers=b["headers"])).json()
    assert la["today"]["id"] == lb["today"]["id"]
    today = la["today"]["id"]
    assert (await client.get(f"/v1/cases/{today}", headers=a["headers"])).status_code == 200
    assert all(r["solved"] is False for r in lb["archive"])  # a's play never leaks into b's list


# --------------------------------------------------------------------------- bulk test players + load test tool
async def test_smoke_bulk_makes_working_throwaway_players(client):
    assert (await client.post("/admin/players/smoke-bulk", json={"n": 2})).status_code == 403
    assert (await client.post("/admin/players/smoke-bulk", headers=ADMIN, json={"n": 501})).status_code == 422
    r = await client.post("/admin/players/smoke-bulk", headers=ADMIN, json={"n": 3})
    assert r.status_code == 200
    players = r.json()["players"]
    assert len(players) == 3 and len({p["player_id"] for p in players}) == 3
    me = await client.get("/v1/me", headers={"Authorization": "Bearer " + players[0]["token"]})
    assert me.status_code == 200 and me.json()["coins"] > 0
    purged = (await client.post("/admin/players/purge-smoke", headers=ADMIN)).json()
    assert purged["deleted"] >= 3
    assert (await client.get("/v1/me", headers={"Authorization": "Bearer " + players[0]["token"]})).status_code == 401


def _load_tool():
    path = Path(__file__).resolve().parent.parent / "tools" / "load_test.py"
    spec = importlib.util.spec_from_file_location("load_test_tool", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_percentiles_and_report():
    lt = _load_tool()
    data = sorted(float(x) for x in range(1, 101))
    assert lt.percentile(data, 50) == 50 and lt.percentile(data, 95) == 95 and lt.percentile(data, 99) == 99
    assert lt.percentile([], 95) == 0.0 and lt.percentile([7.0], 99) == 7.0
    st = lt.Stats()
    for i in range(10):
        st.add("GET /x", "200", 50.0)
    st.add("GET /x", "429", 5.0)
    st.add("GET /y", "503", 9.0)
    s = st.summary(2.0)
    assert s["requests"] == 12 and s["429"] == 1 and s["5xx"] == 1 and s["rps"] == 6.0
    text = lt.report(s, players=3, failed_players=0)
    assert "VERDICT: look at" in text and "429" in text and "5xx" in text
    ok = lt.Stats()
    ok.add("GET /x", "200", 20.0)
    assert "VERDICT: OK" in lt.report(ok.summary(1.0), 1, 0)


async def test_load_test_runs_against_the_app_and_cleans_up(client):
    lt = _load_tool()
    summary, failed = await lt.run("http://test", players=4, ramp=0.2, think=0.01, seed=3, concurrency=3,
                                   transport=httpx.ASGITransport(app=app))
    assert failed == 0 and summary["started"] == 4 and summary["deleted"] == 4
    assert summary["requests"] >= 4 * 8 and summary["5xx"] == 0 and summary["lost"] == 0
    assert "GET /v1/config" in summary["per_endpoint"] and "GET /v1/cases/<today>" in summary["per_endpoint"]
    # with the admin bulk mode
    summary, failed = await lt.run("http://test", players=3, ramp=0.1, think=0.01, seed=4, concurrency=3, admin_key="test-admin-key",
                                   transport=httpx.ASGITransport(app=app))
    assert failed == 0 and summary["deleted"] == 3 and summary["5xx"] == 0
