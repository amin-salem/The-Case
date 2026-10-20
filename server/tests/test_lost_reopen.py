"""A lost case stays closed; opening it again is a paid second chance at 2x the archive price of its difficulty."""
import asyncio
from datetime import timedelta

import pytest
from sqlalchemy import select, update

from app import content, db, economy as eco
from app.models import CaseProgress, CoinLog, Player, utcnow
from .conftest import new_player
from .test_anticheat import accuse, fail_case
from .test_difficulty_economy import balance, changed, fund

PRICES = [100, 120, 150, 180, 220]


async def lost_setup(client, monkeypatch, difficulty, name):
    c = changed(content.by_id("c020"), difficulty)
    tomorrow = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tomorrow))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    p = await new_player(client, name)
    await fund(p["player_id"])
    base = PRICES[difficulty - 1]
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"], json={"expected_cost": base})).status_code == 200
    await fail_case(client, p["headers"], c)
    return c, p, base


def test_reopen_price_is_double_the_archive_price_for_every_difficulty():
    for d, base in enumerate(PRICES, 1):
        assert eco.reopen_lost_cost(d) == base * 2
    assert eco.reopen_lost_cost(3, weekend=True) == eco.archive_unlock_cost(3, weekend=True) * 2
    assert eco.reopen_lost_cost(None) == eco.archive_unlock_cost(None) * 2
    assert eco.difficulty_policy()["lost_reopen_factor"] == 2


@pytest.mark.parametrize("difficulty", range(1, 6))
async def test_lost_case_is_closed_and_reopens_for_double_price(client, monkeypatch, difficulty):
    c, p, base = await lost_setup(client, monkeypatch, difficulty, f"lost-{difficulty}")
    h, pid = p["headers"], p["player_id"]
    cost = base * 2
    closed = await client.get(f"/v1/cases/{c.id}", headers=h)
    assert closed.status_code == 402 and closed.json()["detail"] == {"error": "locked", "cost": cost, "lost": True}
    row = next(r for r in (await client.get("/v1/cases", headers=h)).json()["archive"] if r["id"] == c.id)
    assert row["unlock_cost"] == cost and row["locked"]
    before = await balance(pid)
    stale = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": base})
    assert stale.status_code == 409 and stale.json()["detail"] == {"error": "price_changed", "cost": cost}
    assert await balance(pid) == before
    await fund(pid, cost - 1)
    poor = await client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": cost})
    assert poor.status_code == 402 and poor.json()["detail"]["need"] == cost
    assert await balance(pid) == cost - 1
    await fund(pid, 2000)
    # a double tap charges once
    r1, r2 = await asyncio.gather(*[client.post(f"/v1/cases/{c.id}/unlock", headers=h, json={"expected_cost": cost})
                                    for _ in range(2)])
    assert r1.status_code == 200 and r2.status_code == 200
    assert await balance(pid) == 2000 - cost
    async with db.SessionLocal() as s:
        logs = (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid, CoinLog.reason == f"reopen:{c.id}"))).all()
        assert len(logs) == 1 and logs[0].amount == -cost
        pr = await s.scalar(select(CaseProgress).where(CaseProgress.player_id == pid, CaseProgress.case_id == c.id))
        assert not pr.failed and pr.attempts == 0 and pr.ranked is False
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    won = await accuse(client, h, c, c.culprit)
    assert won["result"] == "solved"


async def test_vip_pays_for_a_lost_case_too(client, monkeypatch):
    c, p, base = await lost_setup(client, monkeypatch, 3, "lost-vip")
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p["player_id"]).values(vip_until=utcnow() + timedelta(days=1)))
        await s.commit()
    assert (await client.get(f"/v1/cases/{c.id}", headers=p["headers"])).status_code == 402
    before = await balance(p["player_id"])
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"])).status_code == 200
    assert await balance(p["player_id"]) == before - base * 2


async def test_lost_case_stays_closed_after_a_solved_case_is_not_affected(client, monkeypatch):
    """Solving is never locked: only a failed, unsolved case is closed."""
    c = content.by_id("c020")
    tomorrow = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tomorrow))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    p = await new_player(client, "solver-ok")
    await fund(p["player_id"])
    assert (await client.post(f"/v1/cases/{c.id}/unlock", headers=p["headers"])).status_code == 200
    assert (await accuse(client, p["headers"], c, c.culprit))["result"] == "solved"
    assert (await client.get(f"/v1/cases/{c.id}", headers=p["headers"])).status_code == 200
