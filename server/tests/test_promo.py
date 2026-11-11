"""Promo cases (app/services/promo.py, Amin 2 Nov 2026): an archive case that is free to open for a NEW detective while an
admin's window is open; older accounts, lost cases and every other case keep the normal price. Runs on SQLite and PostgreSQL."""
import asyncio
from datetime import datetime, timedelta

import pytest
from sqlalchemy import delete, select

from app import content, db
from app.models import CoinLog
from app.models import ConfigValue
from app.services import promo, remote_config
from .conftest import ADMIN, new_player
from .test_anticheat import fail_case
from .test_difficulty_economy import balance, changed, fund


@pytest.fixture(autouse=True)
async def clean_windows(client):
    """The database is shared by the tests of a run: a window left open here would make c020 free in other files."""
    async def wipe():
        async with db.SessionLocal() as s:
            await s.execute(delete(ConfigValue).where(ConfigValue.key == promo.KEY))
            await s.commit()
        remote_config.invalidate()
    await wipe()
    yield
    await wipe()


def setup_clock(monkeypatch, difficulty=4):
    """c020 is an archive case, c021 is tonight's case."""
    c = changed(content.by_id("c020"), difficulty)
    tonight = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tonight))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tonight) + timedelta(hours=1))
    return c


def row(rows, cid):
    return next(r for r in rows["archive"] if r["id"] == cid)


async def start(client, case_id="c020", hours=48):
    return await client.post("/admin/api/promo", headers=ADMIN, json={"case_id": case_id, "hours": hours})


# ---- the stored list: a bad row never makes anything free ----

async def test_parse_ignores_bad_rows_and_closed_windows():
    now = datetime(2026, 11, 2, 12, 0)
    good = {"case_id": "c020", "starts_at": "2026-11-02T10:00:00", "ends_at": "2026-11-04T10:00:00"}
    rows = [good,
            {"case_id": "c021", "starts_at": "2026-11-01T10:00:00", "ends_at": "2026-11-02T10:00:00"},   # ended
            {"case_id": "c022", "starts_at": "2026-11-03T10:00:00", "ends_at": "2026-11-04T10:00:00"},   # not yet
            {"case_id": "c023", "starts_at": "garbage", "ends_at": "2026-11-04T10:00:00"},
            {"case_id": "c024", "starts_at": "2026-11-02T10:00:00+00:00", "ends_at": "2026-11-04T10:00:00+00:00"},   # timezone: refused
            {"case_id": "c025", "starts_at": "2026-11-04T10:00:00", "ends_at": "2026-11-02T10:00:00"},   # ends before it starts
            {"case_id": 5, "starts_at": "2026-11-02T10:00:00", "ends_at": "2026-11-04T10:00:00"},
            {"starts_at": "2026-11-02T10:00:00"}, "text", None]
    assert promo.parse(rows, now) == {"c020": datetime(2026, 11, 4, 10, 0)}
    assert promo.parse("not a list", now) == {} and promo.parse(None, now) == {}


# ---- the admin: who may start a window and for what ----

async def test_admin_starts_and_ends_a_window_and_checks_the_case(client, monkeypatch):
    setup_clock(monkeypatch)
    assert (await client.post("/admin/api/promo", json={"case_id": "c020"})).status_code in (401, 403)   # no admin key
    assert (await start(client, "c021")).status_code == 422                       # tonight's case is free for everybody
    assert (await start(client, "c999")).status_code == 404                       # unknown
    assert (await start(client, "s01ch01")).status_code == 422                    # a story chapter
    assert (await start(client, "c020", hours=0)).status_code == 422
    assert (await start(client, "c020", hours=promo.MAX_HOURS + 1)).status_code == 422
    r = await start(client)
    assert r.status_code == 200 and r.json()["items"][0]["case_id"] == "c020" and r.json()["items"][0]["state"] == "open"
    again = await start(client, hours=24)   # starting again restarts the window, it does not add a second row
    assert again.status_code == 200 and len(again.json()["items"]) == 1
    ended = await client.post("/admin/api/promo/end", headers=ADMIN, json={"case_id": "c020"})
    assert ended.json()["ended"] is True and ended.json()["items"][0]["state"] == "ended"
    assert (await client.post("/admin/api/promo/end", headers=ADMIN, json={"case_id": "c020"})).json()["ended"] is False
    log = (await client.get("/admin/api/promo", headers=ADMIN)).json()
    assert log["default_hours"] == 48 and log["items"][0]["state"] == "ended"


async def test_too_many_open_windows_are_refused(client, monkeypatch):
    older = content.by_id("c019")   # before the clock is patched
    setup_clock(monkeypatch)
    monkeypatch.setattr(promo, "MAX_ACTIVE", 1)
    assert (await start(client)).status_code == 200
    tonight, c20 = content.by_id("c021"), content.by_id("c020")
    monkeypatch.setattr(content, "all_cases", lambda: (older, c20, tonight))
    assert (await start(client, "c019")).status_code == 409


# ---- the player: free once for a new detective, never for anybody else ----

async def test_new_player_opens_the_promo_case_free_once_and_it_does_not_use_the_first_days_offer(client, monkeypatch):
    c = setup_clock(monkeypatch, 1)   # difficulty 1: the first-days archive offer (50 coins) could apply, the promo must win
    p = await new_player(client, "promo-new", aged=False)
    h, pid = p["headers"], p["player_id"]
    await fund(pid, 500)
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["unlock_cost"] == 50   # before the window
    assert (await start(client, c.id)).status_code == 200
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["unlock_cost"] == 0
    stale = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 50})
    assert stale.status_code == 409 and stale.json()["detail"]["cost"] == 0
    r1, r2 = await asyncio.gather(*[client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 0}) for _ in range(2)])
    assert r1.status_code == 200 and r2.status_code == 200
    assert await balance(pid) == 500   # nothing was paid
    async with db.SessionLocal() as s:
        reasons = [x.reason for x in (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid))).all()
                   if x.reason.endswith(c.id)]
    assert reasons.count(f"promo:{c.id}") == 1 and f"unlock:{c.id}" not in reasons   # the 50-coin offer is still unused
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200


async def test_an_old_account_pays_the_normal_price(client, monkeypatch):
    c = setup_clock(monkeypatch)
    assert (await start(client, c.id)).status_code == 200
    p = await new_player(client, "promo-old", aged=True)
    assert row((await client.get("/v1/cases", headers=p["headers"])).json(), c.id)["unlock_cost"] == 180
    await fund(p["player_id"], 500)
    poor = await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"], json={"expected_cost": 0})
    assert poor.status_code == 409 and poor.json()["detail"]["cost"] == 180


async def test_the_window_closes_and_only_the_named_case_is_free(client, monkeypatch):
    c = setup_clock(monkeypatch)
    p = await new_player(client, "promo-end", aged=False)
    h = p["headers"]
    assert (await start(client, c.id)).status_code == 200
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["unlock_cost"] == 0
    await client.post("/admin/api/promo/end", headers=ADMIN, json={"case_id": c.id})
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["unlock_cost"] == 180


async def test_a_lost_promo_case_still_costs_the_reopen_price(client, monkeypatch):
    c = setup_clock(monkeypatch, 3)
    p = await new_player(client, "promo-lost", aged=False)
    h, pid = p["headers"], p["player_id"]
    assert (await start(client, c.id)).status_code == 200
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 0})).status_code == 200
    await fail_case(client, h, c)
    closed = await client.get(f"/v1/cases/{c.id}", headers=h)
    assert closed.status_code == 402 and closed.json()["detail"]["cost"] > 0 and closed.json()["detail"]["lost"]
    assert await balance(pid) >= 0


# ---- the public page of a case ----

async def test_case_page_for_ad_links(client, monkeypatch):
    c = setup_clock(monkeypatch)
    r = await client.get(f"/c/{c.id}")
    assert r.status_code == 200 and c.data["title"] in r.text and "پرونده‌ی بایگانی" in r.text
    assert "رایگان برای کارآگاه" not in r.text   # no window yet
    assert (await start(client, c.id)).status_code == 200
    r = await client.get(f"/c/{c.id}")
    assert "رایگان برای کارآگاه‌های تازه" in r.text and "cafebazaar.ir" in r.text
    assert c.data["evidence"][0]["text"][:30] not in r.text and c.data["solution"]["explanation"][:30] not in r.text
    for bad in ("c999", "s01ch01", "x1", "c020%3Cscript%3E"):
        g = await client.get(f"/c/{bad}", follow_redirects=False)
        assert g.status_code == 302 and g.headers["location"] == "/"
    tonight = await client.get("/c/c021")
    assert tonight.status_code == 200 and "پرونده‌ی امشب" in tonight.text
    future = await client.get("/c/c050", follow_redirects=False)
    assert future.status_code == 302   # not published yet: nothing is shown


# ---- the admin's effect report (read only) ----

async def test_impact_counts_signups_free_opens_solves_and_buyers(client, monkeypatch):
    from app.models import CaseProgress, Player, Purchase, utcnow
    c = setup_clock(monkeypatch, 1)
    before = await new_player(client, "impact-before", aged=False)   # signed up before the window: baseline
    assert (await start(client, c.id)).status_code == 200
    async with db.SessionLocal() as s:   # the first account becomes one hour older than the window start
        await s.execute(Player.__table__.update().where(Player.id == before["player_id"]).values(created_at=utcnow() - timedelta(minutes=1)))
        await s.commit()
    base = next(x for x in (await client.get("/admin/api/promo/impact", headers=ADMIN)).json()["items"] if x["case_id"] == c.id)
    p = await new_player(client, "impact-new", aged=False)
    await fund(p["player_id"], 100)
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"], json={"expected_cost": 0})).status_code == 200
    async with db.SessionLocal() as s:   # solved + bought coins
        cp = (await s.execute(select(CaseProgress).where(CaseProgress.player_id == p["player_id"], CaseProgress.case_id == c.id))).scalar_one()
        cp.solved = True
        s.add(Purchase(player_id=p["player_id"], product_id="coins_400", purchase_token="impact-token-1", status="granted"))
        await s.commit()
    items = (await client.get("/admin/api/promo/impact", headers=ADMIN)).json()["items"]
    w = next(x for x in items if x["case_id"] == c.id)
    assert w["state"] == "open" and w["signups"] == base["signups"] + 1 and w["opened"] == base["opened"] + 1 and w["opened_new"] == base["opened_new"] + 1
    assert w["solved"] == base["solved"] + 1 and w["buyers"] == base["buyers"] + 1 and w["signups_before"] >= 0
    assert (await client.get("/admin/api/promo/impact")).status_code in (401, 403)   # admin key required


async def test_impact_with_no_windows_is_empty(client):
    assert (await client.get("/admin/api/promo/impact", headers=ADMIN)).json() == {"items": []}


# ---- 11 Nov 2026: the free hours of a detective are counted from HIS signup, and the app is told until when ----

def test_personal_end_counts_from_the_signup_or_the_window_start():
    start = datetime(2026, 11, 12, 10, 0)
    assert promo.personal_end(datetime(2026, 11, 14, 8, 0), start) == datetime(2026, 11, 16, 8, 0)   # signed up on day 3 of the ad
    assert promo.personal_end(datetime(2026, 11, 11, 8, 0), start) == datetime(2026, 11, 14, 10, 0)  # signed up before the window
    w = promo.windows([{"case_id": "c020", "starts_at": "2026-11-12T10:00:00", "ends_at": "2026-11-19T10:00:00"}],
                      datetime(2026, 11, 13, 0, 0))
    assert w == {"c020": (datetime(2026, 11, 12, 10, 0), datetime(2026, 11, 19, 10, 0))}
    assert promo.windows("x", datetime(2026, 11, 13)) == {} and promo.windows(None, datetime(2026, 11, 13)) == {}


async def _save_window(case_id, start_ago_h, end_in_h):
    from app.models import utcnow
    now = utcnow()
    async with db.SessionLocal() as s:
        await promo._save(s, [{"case_id": case_id, "starts_at": (now - timedelta(hours=start_ago_h)).isoformat(timespec="seconds"),
                               "ends_at": (now + timedelta(hours=end_in_h)).isoformat(timespec="seconds")}])


async def _age(pid, hours):
    from sqlalchemy import update
    from app.models import Player, utcnow
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(created_at=utcnow() - timedelta(hours=hours)))
        await s.commit()


async def test_a_late_signup_still_gets_his_own_free_hours_and_free_until_is_sent(client, monkeypatch):
    c = setup_clock(monkeypatch)
    await _save_window(c.id, start_ago_h=100, end_in_h=60)   # the ad has been running for four days, a week in all
    late = await new_player(client, "promo-late", aged=False)   # signed up just now
    r = row((await client.get("/v1/cases", headers=late["headers"])).json(), c.id)
    assert r["unlock_cost"] == 0 and r["free_until"] > 0
    from datetime import timezone
    from app.models import utcnow
    assert 47 * 3600 < r["free_until"] - utcnow().replace(tzinfo=timezone.utc).timestamp() <= 48 * 3600
    # the same window gives nothing to a detective whose own 48 hours are over, and no free_until
    spent = await new_player(client, "promo-spent", aged=False)
    await _age(spent["player_id"], 60)
    r = row((await client.get("/v1/cases", headers=spent["headers"])).json(), c.id)
    assert r["unlock_cost"] == 180 and r["free_until"] == 0


async def test_free_until_disappears_once_the_case_is_opened_and_when_the_window_is_ended(client, monkeypatch):
    c = setup_clock(monkeypatch)
    assert (await start(client, c.id)).status_code == 200
    p = await new_player(client, "promo-open", aged=False)
    h = p["headers"]
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["free_until"] > 0
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 0})).status_code == 200
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["free_until"] == 0
    other = await new_player(client, "promo-ended", aged=False)
    assert row((await client.get("/v1/cases", headers=other["headers"])).json(), c.id)["free_until"] > 0
    await client.post("/admin/api/promo/end", headers=ADMIN, json={"case_id": c.id})   # the kill switch ends it for everybody
    assert row((await client.get("/v1/cases", headers=other["headers"])).json(), c.id)["free_until"] == 0
