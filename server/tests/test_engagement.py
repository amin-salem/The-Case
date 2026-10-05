"""Login calendar, streak insurance, streak badges and "what others thought" stats."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content, economy

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    """clock(dt) moves the server's clock (Tehran time)."""
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def evening_of(case_id: str) -> datetime:
    c = content.by_id(case_id)
    return datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN)


async def solve_today(client, h, case_id: str) -> dict:
    lst = (await client.get("/v1/cases", headers=h)).json()
    assert lst["today"]["id"] == case_id
    assert (await client.get(f"/v1/cases/{case_id}", headers=h)).status_code == 200
    c = content.by_id(case_id)
    r = (await client.post(f"/v1/cases/{case_id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved", r
    return r


async def test_login_calendar_grows_and_resets(client, clock):
    p = await new_player(client, "calendar-1")
    h = p["headers"]
    start = datetime(2026, 10, 20, 10, 0, tzinfo=TEHRAN)
    got = []
    for d in range(7):
        clock(start + timedelta(days=d))
        me = (await client.get("/v1/me", headers=h)).json()
        got.append((me["login_day"], me["login_reward"]))
        again = (await client.get("/v1/me", headers=h)).json()
        assert again["login_reward"] == 0 and again["login_day"] == me["login_day"]
    assert [d for d, _ in got] == [1, 2, 3, 4, 5, 6, 7]
    assert [r for _, r in got[:6]] == economy.LOGIN_CALENDAR
    assert got[6][1] in economy.LOGIN_ENVELOPE
    # day 8 starts a new week
    clock(start + timedelta(days=7))
    assert (await client.get("/v1/me", headers=h)).json()["login_day"] == 1
    # missing a day starts again from day 1
    clock(start + timedelta(days=8))
    assert (await client.get("/v1/me", headers=h)).json()["login_day"] == 2
    clock(start + timedelta(days=10))
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["login_day"] == 1 and me["login_reward"] == economy.LOGIN_CALENDAR[0]


async def test_streak_insurance_and_badge(client, clock):
    p = await new_player(client, "streaker-1")
    h = p["headers"]
    ids = [c.id for c in content.all_cases()]
    i = ids.index("c010")

    clock(evening_of(ids[i]))
    assert (await solve_today(client, h, ids[i]))["streak"] == 1
    clock(evening_of(ids[i + 1]))
    assert (await solve_today(client, h, ids[i + 1]))["streak"] == 2

    # buy one insurance; a second is fine, a third is refused
    me = (await client.post("/v1/wallet/streak-freeze", headers=h)).json()
    assert me["streak_freezes"] == 1
    coins_before = me["coins"]
    me = (await client.post("/v1/wallet/streak-freeze", headers=h)).json()
    assert me["streak_freezes"] == 2 and me["coins"] == coins_before - economy.FREEZE_COST
    r = await client.post("/v1/wallet/streak-freeze", headers=h)
    assert r.status_code == 409

    # miss one case: insurance keeps the streak
    clock(evening_of(ids[i + 3]))
    r = await solve_today(client, h, ids[i + 3])
    assert r["streak"] == 3 and r["freezes_used"] == 1
    assert (await client.get("/v1/me", headers=h)).json()["streak_freezes"] == 1

    # miss two cases with only one insurance left: the streak starts again, insurance is kept
    clock(evening_of(ids[i + 6]))
    r = await solve_today(client, h, ids[i + 6])
    assert r["streak"] == 1 and r["freezes_used"] == 0
    assert (await client.get("/v1/me", headers=h)).json()["streak_freezes"] == 1

    # seven in a row gives the first badge
    badges = []
    for k in range(i + 7, i + 13):
        clock(evening_of(ids[k]))
        r = await solve_today(client, h, ids[k])
        badges.append((r["streak"], r["badge"]))
    assert badges[-1] == (7, 7)
    assert all(b is None for _, b in badges[:-1])


async def test_buying_insurance_needs_coins(client, clock, monkeypatch):
    p = await new_player(client, "poor-detective")
    monkeypatch.setattr(economy, "FREEZE_COST", 10_000)
    r = await client.post("/v1/wallet/streak-freeze", headers=p["headers"])
    assert r.status_code == 402 and r.json()["detail"]["error"] == "not_enough_coins"


async def test_what_others_thought(client, clock):
    case_id = "c030"
    clock(evening_of(case_id))
    c = content.by_id(case_id)
    innocent = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    proof = sorted(c.proof)[0]

    a = await new_player(client, "stats-a")
    b = await new_player(client, "stats-b")
    late = await new_player(client, "stats-late")
    for pl in (a, b, late):
        assert (await client.get(f"/v1/cases/{case_id}", headers=pl["headers"])).status_code == 200

    # no stats before finishing (they would give the answer away)
    r = await client.get(f"/v1/cases/{case_id}/stats", headers=late["headers"])
    assert r.status_code == 409

    await client.post(f"/v1/cases/{case_id}/accuse", headers=a["headers"], json={"suspect": innocent, "evidence": proof})
    await client.post(f"/v1/cases/{case_id}/accuse", headers=a["headers"], json={"suspect": c.culprit, "evidence": proof})
    await client.post(f"/v1/cases/{case_id}/accuse", headers=b["headers"], json={"suspect": c.culprit, "evidence": proof})

    s = (await client.get(f"/v1/cases/{case_id}/stats", headers=a["headers"])).json()
    assert s["culprit"] == c.culprit and s["players"] >= 2
    assert {x["id"] for x in s["suspects"]} == {x["id"] for x in c.data["suspects"]}
    pct = {x["id"]: x["pct"] for x in s["suspects"]}
    assert pct[c.culprit] > 0 and pct[innocent] > 0
    assert 100 - len(pct) <= sum(pct.values()) <= 100 + len(pct)
    assert 0 < s["first_try_pct"] <= s["solved_pct"] <= 100


async def test_config_has_engagement_numbers(client):
    cfg = (await client.get("/v1/config")).json()
    e = cfg["economy"]
    assert e["login_calendar"] == economy.LOGIN_CALENDAR and e["freeze_cost"] == economy.FREEZE_COST
    assert e["streak_badges"] == list(economy.STREAK_BADGES) and cfg["share_url"].startswith("https://")


async def test_delete_account_and_public_pages(client):
    p = await new_player(client, "leaving-player")
    assert (await client.post("/v1/me/delete", headers=p["headers"])).status_code == 200
    assert (await client.get("/v1/me", headers=p["headers"])).status_code == 401
    for path in ("/privacy", "/terms", "/delete-account"):
        r = await client.get(path)
        assert r.status_code == 200 and "پرونده" in r.text
