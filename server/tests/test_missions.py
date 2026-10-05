"""Daily missions: same three for everyone, progress from real actions, a chest when all are done."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content, missions, riddles
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


@pytest.fixture
def fixed_missions(monkeypatch):
    """Every day: answer 3 riddles, solve today's case, interrogate every suspect."""
    picked = [missions.BY_ID["riddle_play3"], missions.BY_ID["daily_case"], missions.BY_ID["interrogate_all"]]
    monkeypatch.setattr(missions, "for_day", lambda day: picked)
    return picked


def test_pool_and_daily_pick():
    for d in range(30):
        day = (datetime(2026, 11, 1) + timedelta(days=d)).date().isoformat()
        got = missions.for_day(day)
        assert [m.group for m in got] == ["riddle", "case", "extra"]
        assert got == missions.for_day(day)
    assert len({m.id for m in missions.POOL}) == len(missions.POOL)


async def _answer_riddles(client, h, n):
    day = content.today_str()
    truth = {r.id: r.answer for r in riddles.for_day(day)}
    items = (await client.get("/v1/riddles", headers=h)).json()["items"]
    out = []
    for it in [i for i in items if not i["locked"]][:n]:
        out.append((await client.post(f"/v1/riddles/{it['id']}/answer", headers=h,
                                      json={"choice": truth[it["id"]], "seconds": 30})).json())
    return out


async def test_missions_chest_and_streak(client, clock, fixed_missions):
    c = content.by_id("c020")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    p = await new_player(client, "missioner-1")
    h = p["headers"]

    m = (await client.get("/v1/missions", headers=h)).json()
    assert [x["id"] for x in m["missions"]] == ["riddle_play3", "daily_case", "interrogate_all"]
    assert not m["all_done"] and not m["claimed"] and m["chest_coins"] == eco.CHEST_COINS
    assert (await client.post("/v1/missions/claim", headers=h)).status_code == 409

    # three riddles: the third one finishes the first mission
    res = await _answer_riddles(client, h, 3)
    assert [r["gains"]["missions_done"] for r in res] == [[], [], ["به ۳ معمای سریع جواب بده"]]

    # solve today's case
    assert (await client.get("/v1/cases", headers=h)).json()["today"]["id"] == c.id
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    # interrogate everyone (twice the same one doesn't count twice)
    ids = [s["id"] for s in c.data["suspects"]]
    seen = [(await client.post(f"/v1/cases/{c.id}/seen", headers=h, json={"suspect": s})).json() for s in [ids[0], *ids]]
    assert seen[-1]["seen"] == len(ids) and seen[-1]["gains"]["missions_done"] == ["از همه‌ی مظنون‌های یک پرونده بازجویی کن"]
    assert all(not x["gains"]["missions_done"] for x in seen[:-1])
    assert (await client.post(f"/v1/cases/{c.id}/seen", headers=h, json={"suspect": "nobody"})).status_code == 404

    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved" and r["gains"]["missions_done"] == ["پرونده‌ی امروز را حل کن"]

    m = (await client.get("/v1/missions", headers=h)).json()
    assert m["all_done"] and all(x["done"] and x["progress"] == x["target"] for x in m["missions"])
    coins = m["coins"]
    ch = (await client.post("/v1/missions/claim", headers=h)).json()
    bonus = sum(a["coins"] for a in ch["gains"]["achievements"])  # "first chest" achievement
    assert ch["reward"] == eco.CHEST_COINS and ch["missions"]["coins"] == coins + eco.CHEST_COINS + bonus
    assert "chest_1" in {a["id"] for a in ch["gains"]["achievements"]}
    assert ch["missions"]["claimed"] and ch["missions"]["chest_streak"] == 1
    assert (await client.post("/v1/missions/claim", headers=h)).status_code == 409

    # the next day: new counters; finishing again makes the streak 2
    nxt = content.all_cases()[content.all_cases().index(c) + 1]
    clock(datetime(nxt.publish.year, nxt.publish.month, nxt.publish.day, 22, 0, tzinfo=TEHRAN))
    m = (await client.get("/v1/missions", headers=h)).json()
    assert not any(x["done"] for x in m["missions"]) and m["chest_streak"] == 1
    await _answer_riddles(client, h, 3)
    assert (await client.get(f"/v1/cases/{nxt.id}", headers=h)).status_code == 200
    for s in nxt.data["suspects"]:
        await client.post(f"/v1/cases/{nxt.id}/seen", headers=h, json={"suspect": s["id"]})
    await client.post(f"/v1/cases/{nxt.id}/accuse", headers=h, json={"suspect": nxt.culprit, "evidence": sorted(nxt.proof)[0]})
    ch = (await client.post("/v1/missions/claim", headers=h)).json()
    assert ch["missions"]["chest_streak"] == 2

    # a day without the chest: the streak shown is 0, and starts again from 1
    later = content.all_cases()[content.all_cases().index(c) + 3]
    clock(datetime(later.publish.year, later.publish.month, later.publish.day, 22, 0, tzinfo=TEHRAN))
    assert (await client.get("/v1/missions", headers=h)).json()["chest_streak"] == 0


async def test_spending_missions_count(client, clock, monkeypatch):
    picked = [missions.BY_ID["riddle_unlock"], missions.BY_ID["case_no_hint"], missions.BY_ID["hint_use"]]
    monkeypatch.setattr(missions, "for_day", lambda day: picked)
    c = content.by_id("c021")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    p = await new_player(client, "missioner-2")
    h = p["headers"]
    items = (await client.get("/v1/riddles", headers=h)).json()["items"]
    u = (await client.post(f"/v1/riddles/{items[-1]['id']}/unlock", headers=h)).json()
    assert u["gains"]["missions_done"] == ["یک معمای قفل را باز کن"]
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    hint = (await client.post(f"/v1/cases/{c.id}/hint", headers=h)).json()
    assert hint["gains"]["missions_done"] == ["یک سرنخ بخر"]
    # solved with a hint: "without hints" is not done
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["gains"]["missions_done"] == []
    m = (await client.get("/v1/missions", headers=h)).json()
    assert [x["done"] for x in m["missions"]] == [True, False, True]
