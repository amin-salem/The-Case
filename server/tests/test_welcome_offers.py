"""First-days offers (app/welcome.py, Amin 28 Oct 2026): a new player's FIRST reopening of a lost case costs 100 coins and
his FIRST easy archive case 50; both once; older accounts and weekend cases never get them."""
import asyncio
from datetime import timedelta

from sqlalchemy import select, update

from app import content, db, welcome
from app.models import CoinLog, Player, utcnow
from .conftest import new_player
from .test_anticheat import fail_case
from .test_difficulty_economy import balance, changed, fund


def setup_clock(monkeypatch, difficulty):
    c = changed(content.by_id("c020"), difficulty)
    tomorrow = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tomorrow))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    return c


def row(rows, cid):
    return next(r for r in rows["archive"] if r["id"] == cid)


async def test_first_easy_archive_case_costs_50_once(client, monkeypatch):
    c = setup_clock(monkeypatch, 1)
    p = await new_player(client, "wo-arch", aged=False)
    h, pid = p["headers"], p["player_id"]
    await fund(pid, 500)
    assert row((await client.get("/v1/cases", headers=h)).json(), c.id)["unlock_cost"] == welcome.NEWBIE_ARCHIVE_COST
    stale = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 100})
    assert stale.status_code == 409 and stale.json()["detail"]["cost"] == 50
    r1, r2 = await asyncio.gather(*[client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 50}) for _ in range(2)])
    assert r1.status_code == 200 and r2.status_code == 200
    assert await balance(pid) == 450   # a double tap pays once
    async with db.SessionLocal() as s:
        logs = (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid, CoinLog.reason == f"unlock:{c.id}"))).all()
        assert len(logs) == 1 and logs[0].amount == -50


async def test_second_archive_case_is_full_price_and_hard_cases_never_discounted(client, monkeypatch):
    c = setup_clock(monkeypatch, 4)   # difficulty 4: no offer
    p = await new_player(client, "wo-hard", aged=False)
    assert row((await client.get("/v1/cases", headers=p["headers"])).json(), c.id)["unlock_cost"] == 180
    c2 = setup_clock(monkeypatch, 2)
    await fund(p["player_id"], 500)
    assert row((await client.get("/v1/cases", headers=p["headers"])).json(), c2.id)["unlock_cost"] == 50
    assert (await client.post(f"/v1/cases/{c2.id}/unlock", headers=p["headers"], json={"expected_cost": 50})).status_code == 200
    async with db.SessionLocal() as s:   # the offer is used up: same easy case type is full price again
        offers = await welcome.offers_for(s, await s.get(Player, p["player_id"]))
    assert offers.archive is False


async def test_first_reopen_costs_100_for_a_new_player_then_full_price(client, monkeypatch):
    c = setup_clock(monkeypatch, 3)   # normal reopen price: 2 x 150 = 300
    p = await new_player(client, "wo-lost", aged=False)
    h, pid = p["headers"], p["player_id"]
    await fund(pid, 1000)
    # the case is bought at full price on purpose (difficulty 3 has no archive offer), then lost
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 150})).status_code == 200
    await fail_case(client, h, c)
    closed = await client.get(f"/v1/cases/{c.id}", headers=h)
    assert closed.status_code == 402 and closed.json()["detail"]["cost"] == 100 and closed.json()["detail"]["lost"]
    await fund(pid, 99)
    poor = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 100})
    assert poor.status_code == 402
    await fund(pid, 400)
    ok = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": 100})
    assert ok.status_code == 200 and await balance(pid) == 300
    await fail_case(client, h, c)
    again = await client.get(f"/v1/cases/{c.id}", headers=h)
    assert again.json()["detail"]["cost"] == 300   # only the FIRST reopening is cheap


async def test_old_accounts_and_weekend_cases_get_no_offer(client, monkeypatch):
    c = setup_clock(monkeypatch, 1)
    old = await new_player(client, "wo-old", aged=True)
    assert row((await client.get("/v1/cases", headers=old["headers"])).json(), c.id)["unlock_cost"] == 100
    p = await new_player(client, "wo-edge", aged=False)
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p["player_id"]).values(
            created_at=utcnow() - timedelta(days=welcome.NEWBIE_DAYS, minutes=1)))
        await s.commit()
    assert row((await client.get("/v1/cases", headers=p["headers"])).json(), c.id)["unlock_cost"] == 100
    from app.routers.cases import _unlock_cost
    wk = changed(content.by_id("c020"), 1)
    monkeypatch.setattr(content, "is_weekly", lambda cid: True)
    assert _unlock_cost(wk, None, welcome.Offers(reopen=True, archive=True)) == 170   # weekend archive level 1
