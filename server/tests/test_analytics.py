"""The delegated key reads aggregate reports only, never player/admin data or writes."""
import hashlib
from datetime import datetime, timezone

import pytest
from sqlalchemy import event

from app import db
from app.config import get_settings
from app.main import app
from app.routers import analytics
from app.services import funnel
from app.services import ratelimit as rl

from .conftest import ADMIN, new_player
from .test_funnel import NOW, seed, session  # noqa: F401 - private seeded-db fixture

KEY = "test-report-only-key-independent-0123456789"
HEADERS = {"X-Analytics-Key": KEY}
PATH = "/v1/analytics/funnel"


def digest(key):
    return hashlib.sha256(key.encode()).hexdigest()


@pytest.fixture
async def enabled(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "analytics_api_key_sha256", digest(KEY))
    monkeypatch.setattr(s, "analytics_api_key_expires_at", int(datetime.now(timezone.utc).timestamp()) + 3600)
    return s


async def test_disabled_by_default_even_with_admin_key(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "analytics_api_key_sha256", "")
    for headers in ({}, HEADERS, ADMIN):
        assert (await client.get(PATH, headers=headers)).status_code == 403


async def test_only_its_header_is_accepted_and_bad_requests_never_build(client, enabled, monkeypatch):
    async def no_build(*args, **kwargs):
        pytest.fail("unauthorized request reached report service")
    monkeypatch.setattr(funnel, "build", no_build)
    for headers in ({}, {"X-Analytics-Key": "wrong"}, {"X-Admin-Key": KEY}, ADMIN,
                    {"Authorization": f"Bearer {KEY}"}, {"X-Analytics-Key": "x" * 257}):
        r = await client.get(PATH, headers=headers)
        assert r.status_code == 403 and r.json() == {"detail": "analytics_forbidden"}
    assert (await client.get(PATH, params={"key": KEY})).status_code == 403


async def test_report_matches_admin_aggregates_and_is_not_http_cached(client, enabled):
    p = await new_player(client, "analytics-private-device")
    r = await client.get(PATH, headers=HEADERS)
    assert r.status_code == 200, r.text
    admin = (await client.get("/admin/api/funnel", headers=ADMIN)).json()
    for key in ("days", "timezone", "first_day", "last_day", "signups", "funnel", "retention", "drop_off", "money", "quality", "text"):
        assert r.json()[key] == admin[key]
    assert r.headers["cache-control"] == "no-store"
    assert r.headers["vary"] == "X-Analytics-Key"
    for secret in (KEY, p["player_id"], p["secret"], p["token"], "analytics-private-device"):
        assert secret not in r.text


@pytest.mark.parametrize("deadline", [0, 1])
async def test_expired_or_missing_expiry_refuses_access(client, enabled, deadline):
    enabled.analytics_api_key_expires_at = deadline
    assert (await client.get(PATH, headers=HEADERS)).status_code == 403


async def test_revocation_rotation_and_expiry_apply_to_cache_hits(client, enabled):
    assert (await client.get(PATH, headers=HEADERS)).status_code == 200
    enabled.analytics_api_key_expires_at = 1
    assert (await client.get(PATH, headers=HEADERS)).status_code == 403
    enabled.analytics_api_key_expires_at = int(datetime.now(timezone.utc).timestamp()) + 3600
    new = KEY + "-rotated"
    enabled.analytics_api_key_sha256 = digest(new)
    assert (await client.get(PATH, headers=HEADERS)).status_code == 403
    assert (await client.get(PATH, headers={"X-Analytics-Key": new})).status_code == 200
    enabled.analytics_api_key_sha256 = ""
    assert (await client.get(PATH, headers={"X-Analytics-Key": new})).status_code == 403


@pytest.mark.parametrize("bad_hash", ["not-a-hash", "g" * 64])
async def test_bad_hash_fails_closed(client, enabled, bad_hash):
    enabled.analytics_api_key_sha256 = bad_hash
    assert (await client.get(PATH, headers=HEADERS)).status_code == 403


@pytest.mark.parametrize("source", ["admin_api_key", "jwt_secret"])
async def test_admin_or_jwt_secret_cannot_be_reused_as_delegated_key(client, enabled, monkeypatch, source):
    monkeypatch.setattr(enabled, source, KEY)
    assert (await client.get(PATH, headers=HEADERS)).status_code == 403


async def test_limited_key_grants_no_player_admin_or_mutation_access(client, enabled):
    # An attacker also placing the delegated key in the admin header gains nothing.
    headers = {**HEADERS, "X-Admin-Key": KEY}
    for path in ("/admin/api/funnel", "/admin/api/overview", "/admin/api/players", "/admin/api/money", "/admin/api/log"):
        assert (await client.get(path, headers=headers)).status_code == 403
    assert (await client.get("/v1/me", headers={"Authorization": f"Bearer {KEY}"})).status_code == 401
    assert (await client.post("/admin/gifts", headers=headers,
                              json={"title": "forbidden", "grants": [{"type": "coins", "amount": 1}]})).status_code == 403
    assert (await client.put("/admin/config", headers=headers, json={})).status_code == 403
    assert (await client.post("/admin/players/no-player/ban", headers=headers, json={"banned": True})).status_code == 403
    for method in ("POST", "PUT", "PATCH", "DELETE"):
        assert (await client.request(method, PATH, headers=HEADERS)).status_code == 405
    assert (await client.get("/v1/analytics/players", headers=HEADERS)).status_code == 404


async def test_window_bounds_and_cached_queries(client, enabled, monkeypatch):
    original = funnel.build
    calls = []
    async def build(s, days):
        calls.append(days)
        return await original(s, days)
    monkeypatch.setattr(funnel, "build", build)
    for days in (0, 91, "wrong"):
        assert (await client.get(PATH, headers=HEADERS, params={"days": days})).status_code == 422
    for days in (1, 30, 90):
        a = await client.get(PATH, headers=HEADERS, params={"days": days})
        b = await client.get(PATH, headers=HEADERS, params={"days": days})
        assert a.status_code == b.status_code == 200 and a.json() == b.json()
    assert calls == [1, 30, 90]


async def test_response_whitelists_nested_fields_and_rebuilds_text(session):
    await seed(session)
    raw = await funnel.build(session, 10, NOW)
    marker = "personal-data-must-never-leak"
    raw["players"] = [{"email": marker}]
    raw["text"] = marker
    raw["funnel"]["days"][0]["nickname"] = marker
    raw["money"]["packs"][0]["purchase_token"] = marker
    raw["quality"]["cases"][0]["players"] = [marker]
    safe = analytics.aggregate_only(raw)
    assert marker not in str(safe)
    assert safe["money"]["payers"] == 2
    assert safe["retention"]["total"]["d1"]["pct"] == 40.0
    assert "قیف و ماندگاری" in safe["text"]


async def test_report_queries_do_not_mutate_business_data(client, enabled):
    statements = []
    def record(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement.lstrip().upper())
    event.listen(db.engine.sync_engine, "before_cursor_execute", record)
    try:
        assert (await client.get(PATH, headers=HEADERS)).status_code == 200
    finally:
        event.remove(db.engine.sync_engine, "before_cursor_execute", record)
    assert statements
    assert not any(s.startswith(("INSERT", "UPDATE", "DELETE", "REPLACE", "CREATE", "DROP", "ALTER")) for s in statements)


async def test_partial_section_failure_remains_safe(client, enabled, monkeypatch):
    async def boom(*args):
        raise RuntimeError(KEY)
    monkeypatch.setitem(funnel.SECTIONS, "money", boom)
    r = await client.get(PATH, headers=HEADERS)
    assert r.status_code == 200 and r.json()["money"] == {"error": "section_failed"}
    assert KEY not in r.text


def test_report_has_a_strict_bounded_rate_policy():
    matched = [name for method, rx, name in rl.ROUTES if (method in ("*", "GET")) and rx.match(PATH)]
    assert matched[0] == "analytics"
    policy = rl.DEFAULTS["analytics"]
    assert policy.scope == "ip" and policy.store == "strict" and policy.fail == "closed"
    assert policy.tiers == ((6, 60), (60, 3600))
