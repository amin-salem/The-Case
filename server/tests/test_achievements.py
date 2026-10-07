"""Achievements: definitions, earned once with coins and XP, progress listed, late ones granted on /me."""
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from app import achievements, content, missions, riddles
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def test_definitions():
    assert 28 <= len(achievements.ALL) <= 40
    assert len(achievements.BY_ID) == len(achievements.ALL)
    assert len({a.title for a in achievements.ALL}) == len(achievements.ALL)
    for a in achievements.ALL:
        assert a.metric in achievements.METRICS and a.target > 0 and a.coins >= 0
    # the rank badges point at the right ranks
    assert eco.RANKS[achievements.BY_ID["rank_inspector"].target][1] == "بازرس"
    assert achievements.BY_ID["rank_legend"].target == len(eco.RANKS) - 1


async def test_earned_once_with_rewards(client, clock, monkeypatch):
    monkeypatch.setattr(missions, "RIDDLES_ON", True)  # this test uses riddles, so they count again
    c = content.by_id("c030")
    publish = datetime(c.publish.year, c.publish.month, c.publish.day, 21, 10, tzinfo=TEHRAN)
    clock(publish)
    p = await new_player(client, "achiever-1")
    h = p["headers"]
    lst = (await client.get("/v1/achievements", headers=h)).json()
    assert lst["earned"] == 0 and lst["total"] == len(achievements.ALL)

    # three right riddles in a row: first riddle + a day without mistakes
    truth = {r.id: r.answer for r in riddles.for_day(content.today_str())}
    items = (await client.get("/v1/riddles", headers=h)).json()["items"]
    got = []
    for it in items[:3]:
        r = (await client.post(f"/v1/riddles/{it['id']}/answer", headers=h, json={"choice": truth[it["id"]], "seconds": 10})).json()
        got += [a["id"] for a in r["gains"]["achievements"]]
    assert got == ["riddle_1", "riddle_day_1"]

    # today's case, quickly, first try, no hints, within half an hour of opening
    await client.get(f"/v1/cases/{c.id}", headers=h)
    me_before = (await client.get("/v1/me", headers=h)).json()
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    ids = {a["id"] for a in r["gains"]["achievements"]}
    assert {"first_case", "stars_1", "fast_5", "fast_2", "early_daily"} <= ids
    expected = r["reward"] + sum(achievements.BY_ID[i].coins for i in ids)
    assert r["coins"] == me_before["coins"] + expected

    lst = (await client.get("/v1/achievements", headers=h)).json()
    rows = {x["id"]: x for x in lst["items"]}
    assert rows["first_case"]["earned"] and rows["first_case"]["earned_at"]
    assert not rows["cases_10"]["earned"] and rows["cases_10"]["progress"] == 1 and rows["cases_10"]["target"] == 10
    assert lst["earned"] == len(ids) + 2
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["achievements"] == lst["earned"] and me.get("gains") is None


async def test_late_achievement_on_me(client):
    p = await new_player(client, "achiever-2")
    h = p["headers"]
    await client.get("/v1/me", headers=h)
    r = await client.post("/v1/auth/email", headers=h, json={"email": "late@example.com", "password": "secret1"})
    assert r.status_code == 200
    me = (await client.get("/v1/me", headers=h)).json()
    assert [a["id"] for a in me["gains"]["achievements"]] == ["secured"]
    again = (await client.get("/v1/me", headers=h)).json()
    assert again.get("gains") is None
