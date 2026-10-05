"""Quick riddles: same set for everyone, free and paid slots, one answer each, answer hidden until then."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content, riddles
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def test_content_is_valid_and_rotates():
    items = riddles.all_riddles()
    assert len(items) >= 60
    assert {r.answer for r in items} == {0, 1, 2}  # the right answer is not always in the same place
    days_per_cycle = len(items) // eco.RIDDLES_PER_DAY
    start = riddles.EPOCH + timedelta(days=days_per_cycle * 25)  # the first day of a cycle
    seen = []
    for d in range(days_per_cycle):
        day = (start + timedelta(days=d)).isoformat()
        got = riddles.for_day(day)
        assert len(got) == eco.RIDDLES_PER_DAY
        assert got == riddles.for_day(day)  # the same set every time it is asked
        seen += [r.id for r in got]
    assert len(seen) == len(set(seen))  # nothing repeats inside a cycle


async def test_play_a_day(client, clock):
    clock(datetime(2026, 11, 3, 18, 0, tzinfo=TEHRAN))
    p = await new_player(client, "riddler-1")
    h = p["headers"]
    day = (await client.get("/v1/riddles", headers=h)).json()
    items = day["items"]
    assert len(items) == eco.RIDDLES_PER_DAY and day["day"] == "2026-11-03"
    free, paid = items[:eco.RIDDLE_FREE], items[eco.RIDDLE_FREE:]
    assert all(i["free"] and not i["locked"] and i["text"] and len(i["choices"]) == 3 for i in free)
    assert all(i["locked"] and i["text"] is None and i["choices"] == [] for i in paid)
    assert all(i["answer"] is None and i["explain"] is None for i in items)  # never before answering

    truth = {r.id: r.answer for r in riddles.for_day("2026-11-03")}
    coins = day["coins"]
    # right answer pays, and can't be answered again
    r = (await client.post(f"/v1/riddles/{free[0]['id']}/answer", headers=h, json={"choice": truth[free[0]['id']], "seconds": 12})).json()
    bonus = sum(a["coins"] for a in r["gains"]["achievements"])  # "first riddle" achievement
    assert r["correct"] and r["reward"] == eco.RIDDLE_REWARD and r["coins"] == coins + eco.RIDDLE_REWARD + bonus
    assert r["item"]["answered"] and r["item"]["explain"] and r["answer"] == truth[free[0]["id"]]
    again = await client.post(f"/v1/riddles/{free[0]['id']}/answer", headers=h, json={"choice": 0})
    assert again.status_code == 409
    # wrong answer (time ran out) pays nothing but shows the solution
    r = (await client.post(f"/v1/riddles/{free[1]['id']}/answer", headers=h, json={"choice": -1})).json()
    assert not r["correct"] and r["reward"] == 0 and r["explain"]

    # a paid one: locked until bought
    locked = await client.post(f"/v1/riddles/{paid[0]['id']}/answer", headers=h, json={"choice": 0})
    assert locked.status_code == 402
    u = (await client.post(f"/v1/riddles/{paid[0]['id']}/unlock", headers=h)).json()
    assert not u["item"]["locked"] and u["item"]["text"] and u["coins"] == coins + eco.RIDDLE_REWARD + bonus - eco.RIDDLE_UNLOCK_COST
    u2 = (await client.post(f"/v1/riddles/{paid[0]['id']}/unlock", headers=h)).json()
    assert u2["coins"] == u["coins"]  # opening twice costs once
    r = (await client.post(f"/v1/riddles/{paid[0]['id']}/answer", headers=h, json={"choice": truth[paid[0]['id']]})).json()
    assert r["correct"]

    # a riddle from another day can't be answered today
    other = next(x for x in riddles.all_riddles() if x.id not in truth)
    assert (await client.post(f"/v1/riddles/{other.id}/answer", headers=h, json={"choice": 0})).status_code == 404

    # the list remembers everything
    day = (await client.get("/v1/riddles", headers=h)).json()
    st = {i["id"]: i for i in day["items"]}
    assert st[free[0]["id"]]["correct"] and st[free[1]["id"]]["answered"] and not st[free[1]["id"]]["correct"]
    assert not st[paid[0]["id"]]["locked"] and st[paid[1]["id"]]["locked"]

    # tomorrow: a new set, nothing answered
    clock(datetime(2026, 11, 4, 0, 30, tzinfo=TEHRAN))
    day = (await client.get("/v1/riddles", headers=h)).json()
    assert day["day"] == "2026-11-04" and not any(i["answered"] for i in day["items"])
    assert {i["id"] for i in day["items"]}.isdisjoint(truth)


async def test_unlock_needs_coins(client, clock, monkeypatch):
    clock(datetime(2026, 11, 5, 18, 0, tzinfo=TEHRAN))
    p = await new_player(client, "riddler-poor")
    monkeypatch.setattr(eco, "RIDDLE_UNLOCK_COST", 100_000)
    items = (await client.get("/v1/riddles", headers=p["headers"])).json()["items"]
    r = await client.post(f"/v1/riddles/{items[-1]['id']}/unlock", headers=p["headers"])
    assert r.status_code == 402 and r.json()["detail"]["error"] == "not_enough_coins"
    # free ones never need unlocking
    r = await client.post(f"/v1/riddles/{items[0]['id']}/unlock", headers=p["headers"])
    assert r.status_code == 200 and not r.json()["item"]["locked"]


async def test_config_has_riddle_numbers(client):
    e = (await client.get("/v1/config")).json()["economy"]
    assert e["riddle_free"] == eco.RIDDLE_FREE and e["riddle_unlock_cost"] == eco.RIDDLE_UNLOCK_COST
