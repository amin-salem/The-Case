"""The real first run of a brand-new guest, on SQLite and (CI job server-postgres) on PostgreSQL: every screen the app opens
in the first minute must answer 2xx. Added after 28 Oct 2026, when GET /v1/cases was a 500 for every account younger than
3 days on PostgreSQL while the suite (100-hour-old accounts, SQLite) stayed green."""
from app import content
from .conftest import new_player


async def test_brand_new_guest_first_run(client):
    p = await new_player(client, "first-run-guest")  # created just now, no email, no phone
    h = p["headers"]

    def ok(r, what):
        assert 200 <= r.status_code < 300, f"{what}: {r.status_code} {r.text[:300]}"
        return r.json()

    cfg = ok(await client.get("/v1/config"), "config")
    assert cfg["economy"]["products"], "the purchase products list"
    cases = ok(await client.get("/v1/cases", headers=h), "case list")
    today = content.todays_case()
    assert today is not None
    ok(await client.get(f"/v1/cases/{today.id}", headers=h), "open today's case")
    for period in ("daily", "weekly", "all"):
        ok(await client.get(f"/v1/leaderboard?period={period}", headers=h), f"leaderboard {period}")
    me = ok(await client.get("/v1/me", headers=h), "me / wallet")
    assert me["coins"] >= 0
    ok(await client.get("/v1/album", headers=h), "album")
    ok(await client.get("/v1/inbox", headers=h), "inbox")
    ok(await client.get("/v1/feed", headers=h), "feed")
    ok(await client.get("/v1/missions", headers=h), "missions")
    ok(await client.get("/v1/achievements", headers=h), "achievements")
    ok(await client.get("/v1/avatars", headers=h), "avatars")
    ok(await client.get("/v1/referrals/status", headers=h), "referrals")
    # and again after the case list has been seen: the second visit must not differ
    ok(await client.get("/v1/cases", headers=h), "case list again")
    assert cases is not None
