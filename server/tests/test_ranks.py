"""Detective rank: XP from cases, riddles and the mission chest; rank-ups; titles on leaderboards."""
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from app import achievements, content, economy as eco, missions, riddles

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


def ach_xp(gains: dict) -> int:
    """XP that came from achievements earned in the same action."""
    return sum(achievements.BY_ID[a["id"]].xp for a in gains["achievements"])


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def test_rank_table():
    assert eco.rank_of(0) == 0 and eco.RANKS[0][1] == "کارآگاه تازه‌کار"
    assert eco.RANKS[-1][1] == "افسانه"
    assert [x for x, _ in eco.RANKS] == sorted({x for x, _ in eco.RANKS})
    for i, (need, _) in enumerate(eco.RANKS):
        assert eco.rank_of(need) == i
        if need:
            assert eco.rank_of(need - 1) == i - 1
    assert eco.rank_of(10**9) == len(eco.RANKS) - 1


async def test_xp_from_actions_and_rank_up(client, clock, monkeypatch):
    c = content.by_id("c025")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    monkeypatch.setattr(missions, "for_day", lambda day: [missions.BY_ID["riddle_play3"], missions.BY_ID["daily_case"],
                                                          missions.BY_ID["case_solve2"]])
    p = await new_player(client, "ranker-1")
    h = p["headers"]
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["xp"] == 0 and me["rank"] == 0 and me["rank_title"] == eco.RANKS[0][1]
    assert me["next_rank_xp"] == eco.RANKS[1][0] and me["next_rank_title"] == eco.RANKS[1][1]

    # riddles: right and wrong answers both give some XP
    truth = {r.id: r.answer for r in riddles.for_day(content.today_str())}
    items = (await client.get("/v1/riddles", headers=h)).json()["items"]
    right = (await client.post(f"/v1/riddles/{items[0]['id']}/answer", headers=h, json={"choice": truth[items[0]['id']]})).json()
    wrong = (await client.post(f"/v1/riddles/{items[1]['id']}/answer", headers=h,
                               json={"choice": (truth[items[1]['id']] + 1) % 3})).json()
    assert right["gains"]["xp"] - ach_xp(right["gains"]) == eco.XP_RIDDLE_RIGHT
    assert wrong["gains"]["xp"] - ach_xp(wrong["gains"]) == eco.XP_RIDDLE_WRONG

    # today's case with 3 stars: enough for the second rank
    monkeypatch.setattr(eco, "RANKS", [(0, "یک"), (50, "دو"), (10**6, "سه")])
    await client.get(f"/v1/cases/{c.id}", headers=h)
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["stars"] == 3 and r["gains"]["xp"] - ach_xp(r["gains"]) == eco.XP_CASE[3] + eco.XP_DAILY_BONUS
    assert r["gains"]["rank_up"] == "دو"
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["xp"] == right["gains"]["xp"] + wrong["gains"]["xp"] + r["gains"]["xp"]
    assert me["rank_title"] == "دو" and me["rank_xp"] == 50 and me["next_rank_title"] == "سه"

    # leaderboards carry the title
    lb = (await client.get("/v1/leaderboard?period=daily", headers=h)).json()
    assert lb["me"]["rank_title"] == "دو"


async def test_failed_case_gives_a_little_xp(client, clock):
    c = content.by_id("c026")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    p = await new_player(client, "ranker-2")
    h = p["headers"]
    await client.get(f"/v1/cases/{c.id}", headers=h)
    innocent = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    last = None
    for _ in range(eco.MAX_ATTEMPTS):
        last = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                                  json={"suspect": innocent, "evidence": sorted(c.proof)[0]})).json()
    assert last["result"] == "failed" and last["gains"]["xp"] == eco.XP_CASE_FAILED


async def test_config_lists_ranks(client):
    e = (await client.get("/v1/config")).json()["economy"]
    assert e["ranks"][0] == {"xp": 0, "title": eco.RANKS[0][1]} and len(e["ranks"]) == len(eco.RANKS)
