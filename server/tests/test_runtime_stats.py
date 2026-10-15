"""The per-worker runtime meter (app/services/runtime_stats.py): deterministic clocks, no sleeps."""
from app.services import runtime_stats as rs

from .conftest import ADMIN


def make(wall0=1000.0, cpu0=50.0):
    t = {"wall": wall0, "cpu": cpu0}
    return rs.RuntimeStats(clock=lambda: t["wall"], cpu=lambda: t["cpu"]), t


def test_cpu_share_is_cpu_seconds_over_wall_seconds():
    st, t = make()
    t["wall"] += 1.0
    t["cpu"] += 0.85
    s = st.sample(0.01, {"out": 3, "max": 10})
    assert round(s["cpu"], 2) == 0.85 and round(s["lag_ms"]) == 10 and s["pool_out"] == 3 and s["pool_max"] == 10
    assert st.is_busy(s)  # 85 % of a core
    t["wall"] += 1.0
    t["cpu"] += 0.10
    assert not st.is_busy(st.sample(0.0, {"out": 1, "max": 10}))


def test_busy_by_lag_by_inflight_and_by_a_full_pool():
    st, t = make()
    t["wall"] += 1.0
    assert st.is_busy(st.sample(0.25, {}))                       # the loop woke up 250 ms late
    for _ in range(rs.BUSY_INFLIGHT):
        st.request_started()
    t["wall"] += 1.0
    assert st.is_busy(st.sample(0.0, {}))                        # many requests at once
    for _ in range(rs.BUSY_INFLIGHT):
        st.request_finished(200)
    t["wall"] += 1.0
    assert not st.is_busy(st.sample(0.0, {"out": 9, "max": 10}))
    t["wall"] += 1.0
    assert st.is_busy(st.sample(0.0, {"out": 10, "max": 10}))    # every connection is checked out


def test_log_line_is_rate_limited_and_has_no_personal_data():
    st, t = make()
    t["wall"] += 1.0
    t["cpu"] += 0.9
    s = st.sample(0.0, {"out": 2, "max": 10})
    assert st.should_log(s) is True
    line = st.log_line(s)
    assert line.startswith("runtime busy pid=") and "cpu=90%" in line and "pool=2/10" in line
    t["wall"] += 1.0
    t["cpu"] += 0.9
    assert st.should_log(st.sample(0.0, {})) is False            # less than 10 s since the last line
    t["wall"] += rs.LOG_EVERY
    t["cpu"] += rs.LOG_EVERY * 0.9
    assert st.should_log(st.sample(0.0, {})) is True


def test_requests_inflight_and_5xx_counters():
    st, _ = make()
    st.request_started()
    st.request_started()
    assert st.inflight == 2 and st.requests == 2
    st.request_finished(200)
    st.request_finished(503)
    assert st.inflight == 0 and st.errors_5xx == 1
    st.request_finished(200)                                      # never below zero
    assert st.inflight == 0


def test_window_is_bounded_and_snapshot_summarises_it():
    st, t = make()
    for i in range(rs.WINDOW + 40):
        t["wall"] += 1.0
        t["cpu"] += 0.5
        st.request_started()
        st.request_finished(500 if i == rs.WINDOW + 39 else 200)
        st.sample(0.0, {"out": 2, "max": 10})
    assert len(st.samples) == rs.WINDOW
    snap = st.snapshot()
    assert snap["seconds"] == rs.WINDOW and snap["cpu_avg_percent"] == 50.0 and snap["pool_out_max"] == 2
    assert snap["pool_limit"] == 10 and snap["requests_per_second"] == 1.0 and snap["errors_5xx_window"] == 1
    assert rs.RuntimeStats().snapshot()["seconds"] == 0           # empty meter: no crash


async def test_runtime_call_needs_the_admin_key_and_answers(client):
    assert (await client.get("/admin/api/runtime")).status_code == 403
    r = await client.get("/admin/api/runtime", headers=ADMIN)
    assert r.status_code == 200
    body = r.json()
    assert {"pid", "seconds", "requests_total", "errors_5xx_total", "inflight_now"} <= set(body)
    assert body["requests_total"] >= 1                            # the middleware counted this very request


async def test_middleware_counts_a_crashing_request_as_5xx():
    inner_calls = []

    async def boom(scope, receive, send):
        inner_calls.append(1)
        raise RuntimeError("x")

    before = (rs.STATS.errors_5xx, rs.STATS.inflight)
    mw = rs.StatsMiddleware(boom)
    try:
        await mw({"type": "http"}, None, None)
    except RuntimeError:
        pass
    assert inner_calls == [1] and rs.STATS.errors_5xx == before[0] + 1 and rs.STATS.inflight == before[1]
