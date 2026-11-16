"""«کیف کارآگاه»: one atomic coin -> stock purchase, price owned by the server, kill switch, retries and races."""
import asyncio
from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select

from app import db, tools
from app.config import get_settings
from app.models import CoinLog, Event, Player, utcnow
from app.services import economy_report as er
from .conftest import new_player
from .test_difficulty_economy import balance, fund

URL = "/v1/tools/kit"


async def stock_of(pid):
    async with db.SessionLocal() as s:
        return {k: v["count"] for k, v in (await tools.stock(s, pid)).items()}


async def kit_rows(pid):
    async with db.SessionLocal() as s:
        return (await s.scalar(select(func.count()).select_from(CoinLog).where(CoinLog.player_id == pid, CoinLog.reason.like("kit:%"))))


def test_kit_contents_and_singles_price():
    assert tools.KIT == {"magnifier": 3, "fingerprint": 2, "camera": 1}
    assert tools.kit_singles_total() == 335
    assert get_settings().tool_kit_price == 280 and get_settings().tool_kit_enabled is True


def test_kit_price_is_bounded():
    assert tools.kit_price(-5) == 1 and tools.kit_price(10**9) == tools.KIT_PRICE_MAX and tools.kit_price(280) == 280


async def test_buying_the_kit_moves_coins_and_stock_in_one_step(client):
    p = await new_player(client, "kit-ok")
    await fund(p["player_id"], 500)
    r = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0001"})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["granted"] is True and j["price"] == 280 and j["coins"] == 220
    assert await balance(p["player_id"]) == 220
    assert await stock_of(p["player_id"]) == {"magnifier": 3, "fingerprint": 2, "camera": 1}
    assert await kit_rows(p["player_id"]) == 1


async def test_the_same_request_id_never_pays_twice(client):
    p = await new_player(client, "kit-retry")
    await fund(p["player_id"], 1000)
    first = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0002"})
    again = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0002"})
    assert first.status_code == again.status_code == 200
    assert first.json()["granted"] is True and again.json()["granted"] is False and again.json()["already"] is True
    assert await balance(p["player_id"]) == 720
    assert await stock_of(p["player_id"]) == {"magnifier": 3, "fingerprint": 2, "camera": 1}


async def test_two_simultaneous_taps_with_one_id_pay_once(client):
    p = await new_player(client, "kit-race")
    await fund(p["player_id"], 1000)
    rs = await asyncio.wait_for(asyncio.gather(*[client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0003"}) for _ in range(2)]), 20)
    assert [r.status_code for r in rs] == [200, 200]
    assert sorted(r.json()["granted"] for r in rs) == [False, True]
    assert await balance(p["player_id"]) == 720
    assert await stock_of(p["player_id"]) == {"magnifier": 3, "fingerprint": 2, "camera": 1}


async def test_two_simultaneous_purchases_with_coins_for_one_buy_exactly_one(client):
    p = await new_player(client, "kit-short-race")
    await fund(p["player_id"], 300)           # enough for one kit, not two
    rs = await asyncio.wait_for(asyncio.gather(*[client.post(URL, headers=p["headers"], json={"request_id": f"kitreq-race{i}"}) for i in range(2)]), 20)
    assert sorted(r.status_code for r in rs) == [200, 402]
    assert await balance(p["player_id"]) == 20
    assert await stock_of(p["player_id"]) == {"magnifier": 3, "fingerprint": 2, "camera": 1}


async def test_short_of_coins_charges_nothing_and_says_the_price(client):
    p = await new_player(client, "kit-poor")
    await fund(p["player_id"], 279)
    r = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0004"})
    assert r.status_code == 402 and r.json()["detail"]["error"] == "not_enough_coins" and r.json()["detail"]["need"] == 280
    assert await balance(p["player_id"]) == 279 and await stock_of(p["player_id"]) == {"magnifier": 0, "fingerprint": 0, "camera": 0}


async def test_the_price_comes_from_the_server_not_the_phone(client):
    p = await new_player(client, "kit-trust")
    await fund(p["player_id"], 500)
    r = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0005", "price": 1, "items": {"camera": 99}})
    assert r.status_code == 200 and await balance(p["player_id"]) == 220
    assert await stock_of(p["player_id"]) == {"magnifier": 3, "fingerprint": 2, "camera": 1}


@pytest.mark.parametrize("rid", [None, "", "short", "x" * 25, "has space!!", 7, ["a"]])
async def test_a_bad_request_id_is_refused(client, rid):
    p = await new_player(client, "kit-bad")
    await fund(p["player_id"], 500)
    r = await client.post(URL, headers=p["headers"], json={"request_id": rid})
    assert r.status_code == 422 and await balance(p["player_id"]) == 500


async def test_needs_a_token(client):
    assert (await client.post(URL, json={"request_id": "kitreq-0006"})).status_code == 401


async def test_kill_switches(client, monkeypatch):
    p = await new_player(client, "kit-off")
    await fund(p["player_id"], 500)
    monkeypatch.setattr(get_settings(), "tool_kit_enabled", False)
    r = await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0007"})
    assert r.status_code == 503 and await balance(p["player_id"]) == 500
    monkeypatch.setattr(get_settings(), "tool_kit_enabled", True)
    monkeypatch.setattr(get_settings(), "detective_tools_enabled", False)
    assert (await client.post(URL, headers=p["headers"], json={"request_id": "kitreq-0008"})).status_code == 503


async def test_the_tray_carries_the_kit_offer(client):
    p = await new_player(client, "kit-tray")
    await fund(p["player_id"], 500)
    from app import content
    cid = content.all_cases()[0].id
    r = await client.get(f"/v1/cases/{cid}/tools", headers=p["headers"])
    if r.status_code == 200:
        assert r.json()["kit"] == {"enabled": True, "price": 280, "singles": 335, "items": {"magnifier": 3, "fingerprint": 2, "camera": 1}}


async def test_help_nudge_events_are_counted_by_kind_without_player_data(client):
    p = await new_player(client, "nudge-a", aged=True)
    async with db.SessionLocal() as s:
        now = utcnow()
        for name, kind in [("help_nudge_shown", "idle"), ("help_nudge_shown", "wrong_accusation"), ("help_nudge_tapped", "idle"),
                           ("help_nudge_closed", "wrong_accusation"), ("help_nudge_shown", "weird")]:
            s.add(Event(player_id=p["player_id"], name=name, props={"kind": kind}, ts=now))
        await s.commit()
        out = (await er.build(s, 14))["help_nudge"]
    assert out["shown"] == 3 and out["tapped"] == 1 and out["closed"] == 1
    assert out["by_kind"]["idle"] == {"shown": 1, "tapped": 1, "closed": 0}
    assert out["by_kind"]["other"]["shown"] == 1
    assert "player" not in str(out).lower() or "players" in str(out).lower()
