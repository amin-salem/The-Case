"""Weekend case, new format (14 Oct 2026): two chapters, evidence shown to suspects, two-part accusation (who + why/how),
early accusation bonus, and expired weekend cases in the archive at a higher price."""
import copy
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")
WED = date(2026, 11, 4)  # a Wednesday


def make_case() -> content.Case:
    """A format-2 weekend case built from w001: 2 chapters (0 h, 24 h), reactions for every suspect."""
    base = content.weekly_cases()[0]
    d = copy.deepcopy(base.data)
    later = [e["id"] for e in d["evidence"] if e["id"] not in {"e1", "e2", "e3", "e4", "e5", "e6", "e7"}]
    d.update({"id": "w099", "number": 99, "publish": WED.isoformat(), "format": 2, "open_hour": 21, "closes_hours": 48})
    d["chapters"] = [{"title": "فصل اول", "at_hours": 0}, {"title": "فصل دوم", "at_hours": 24, "text": "مدارک تازه", "evidence": later}]
    for s in d["suspects"]:
        s["reactions"] = {"e1": "این رو نمی‌دونم از کجاست."}
    next(s for s in d["suspects"] if s["id"] == d["solution"]["culprit"])["reactions"]["e14"] = "خب... اون شب اونجا بودم."
    return content.Case(id="w099", number=99, publish=WED, data=d)


@pytest.fixture
def wk(monkeypatch):
    c = make_case()
    monkeypatch.setattr(content, "weekly_cases", lambda: (c,))
    monkeypatch.setattr(content, "is_weekly", lambda cid: cid.startswith("w"))
    return c


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def test_new_weekend_timing_and_validation(wk):
    assert content.opens_at(wk) == datetime(2026, 11, 4, 21, tzinfo=TEHRAN)  # Wednesday 21:00
    assert content.weekly_closes_at(wk) == datetime(2026, 11, 6, 21, tzinfo=TEHRAN)  # Friday 21:00
    assert content.weekly_all_open_at(wk) == datetime(2026, 11, 5, 21, tzinfo=TEHRAN)
    content.validate_weekly(wk.data)
    bad = copy.deepcopy(wk.data)
    del bad["suspects"][0]["reactions"]
    with pytest.raises(content.CaseError):
        content.validate_weekly(bad)
    bad = copy.deepcopy(wk.data)
    for s in bad["suspects"]:
        s["reactions"].pop("e14", None)  # the culprit never reacts to a proof card
    with pytest.raises(content.CaseError):
        content.validate_weekly(bad)
    # without closes_hours a case closes WEEKLY_HOURS (36 h: Thursday 09:00 -> Friday 21:00) after it opens
    d = copy.deepcopy(wk.data)
    del d["closes_hours"]
    assert content.weekly_closes_at(content.Case(id="w099", number=99, publish=WED, data=d)) == content.opens_at(wk) + timedelta(hours=content.WEEKLY_HOURS)


async def test_reactions_are_never_in_the_public_case(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(minutes=5))
    h = (await new_player(client, "wk2-public"))["headers"]
    case = (await client.get("/v1/cases/w099", headers=h)).json()["case"]
    assert all("reactions" not in s for s in case["suspects"]) and case["format"] == 2
    assert case["shows_per_chapter"] == eco.WEEKEND_SHOWS_PER_CHAPTER and case["chapters_total"] == 2


async def test_showing_evidence_is_limited_per_chapter_and_repeats_are_free(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(minutes=5))
    h = (await new_player(client, "wk2-show"))["headers"]
    await client.get("/v1/cases/w099", headers=h)
    culprit = wk.culprit
    r = await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e1"})
    assert r.status_code == 200 and r.json()["text"] == "این رو نمی‌دونم از کجاست."
    assert r.json()["shows_left"] == eco.WEEKEND_SHOWS_PER_CHAPTER - 1
    # the same card to the same suspect again (a double tap) costs nothing
    again = (await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e1"})).json()
    assert again["shows_left"] == eco.WEEKEND_SHOWS_PER_CHAPTER - 1
    # a card without a written reaction gets the neutral line
    n = (await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e2"})).json()
    assert n["text"] and "e2" not in n["text"]
    await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e3"})
    r = await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e4"})
    assert r.status_code == 409 and r.json()["detail"] == "no_shows_left"
    # a card from the second chapter is not open yet; unknown ids are refused
    assert (await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e14"})).status_code == 404
    assert (await client.post("/v1/cases/w099/show", headers=h, json={"suspect": "zz", "evidence": "e1"})).status_code == 404
    # the saved shows come back with the case
    prog = (await client.get("/v1/cases/w099", headers=h)).json()["progress"]
    assert {(x["s"], x["e"]) for x in prog["shows"]} == {(culprit, "e1"), (culprit, "e2"), (culprit, "e3")} and prog["shows_left"] == 0
    # chapter 2 opens: three more shows, and the culprit's slip on the proof card
    clock(content.opens_at(wk) + timedelta(hours=25))
    r = await client.post("/v1/cases/w099/show", headers=h, json={"suspect": culprit, "evidence": "e14"})
    assert r.status_code == 200 and r.json()["text"] == "خب... اون شب اونجا بودم." and r.json()["shows_left"] == 2


async def test_two_part_accusation_stars_and_early_bonus(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))  # chapter 1 only
    sol = wk.data["solution"]
    wrong_how = next(m["id"] for m in wk.data["motives"] if m["id"] != sol["motive"])
    wrong_who = next(s["id"] for s in wk.data["suspects"] if s["id"] != wk.culprit)

    # who + why/how both right, before the last chapter: 3 stars, reward + early bonus, once
    a = await new_player(client, "wk2-a")
    await client.get("/v1/cases/w099", headers=a["headers"])
    r = (await client.post("/v1/cases/w099/accuse", headers=a["headers"],
                           json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert r["result"] == "solved" and r["stars"] == 3 and r["how_right"] is True
    assert r["early_bonus"] == eco.WEEKLY_EARLY_BONUS and r["reward"] == eco.solve_reward(wk.data.get("difficulty"), 3, live_weekend=True) + eco.WEEKLY_EARLY_BONUS
    r2 = await client.post("/v1/cases/w099/accuse", headers=a["headers"], json={"suspect": wk.culprit, "motive": sol["motive"]})
    assert r2.status_code == 409  # solved: no second payout

    # culprit right, why/how wrong: solved with 2 stars at most, no early bonus
    b = await new_player(client, "wk2-b")
    await client.get("/v1/cases/w099", headers=b["headers"])
    r = (await client.post("/v1/cases/w099/accuse", headers=b["headers"],
                           json={"suspect": wk.culprit, "motive": wrong_how})).json()
    assert r["result"] == "solved" and r["stars"] == 2 and r["how_right"] is False and r["early_bonus"] == 0
    assert r["reward"] == eco.solve_reward(wk.data.get("difficulty"), 2, live_weekend=True)

    # wrong culprit: a try is lost and the case stays open
    c = await new_player(client, "wk2-c")
    await client.get("/v1/cases/w099", headers=c["headers"])
    r = (await client.post("/v1/cases/w099/accuse", headers=c["headers"], json={"suspect": wrong_who, "motive": sol["motive"]})).json()
    assert r["result"] == "wrong_suspect" and r["attempts_left"] == eco.MAX_ATTEMPTS - 1
    prog = (await client.get("/v1/cases/w099", headers=c["headers"])).json()["progress"]
    assert not prog["solved"] and not prog["failed"] and prog["wrong_tries"][0]["s"] == wrong_who

    # the second part is required
    r = await client.post("/v1/cases/w099/accuse", headers=c["headers"], json={"suspect": wk.culprit})
    assert r.status_code == 422 and r.json()["detail"] == "how_needed"

    # after the last chapter opened there is no early bonus any more
    clock(content.weekly_all_open_at(wk))
    d = await new_player(client, "wk2-d")
    await client.get("/v1/cases/w099", headers=d["headers"])
    r = (await client.post("/v1/cases/w099/accuse", headers=d["headers"],
                           json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert r["result"] == "solved" and r["early_bonus"] == 0 and r["reward"] == eco.solve_reward(wk.data.get("difficulty"), 3, live_weekend=True)


async def test_no_shows_after_the_case_is_solved(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))
    h = (await new_player(client, "wk2-done"))["headers"]
    await client.get("/v1/cases/w099", headers=h)
    await client.post("/v1/cases/w099/accuse", headers=h, json={"suspect": wk.culprit, "motive": wk.data["solution"]["motive"]})
    r = await client.post("/v1/cases/w099/show", headers=h, json={"suspect": wk.culprit, "evidence": "e1"})
    assert r.status_code == 409 and r.json()["detail"] == "case_finished"


async def test_expired_weekend_case_is_an_archive_case_with_a_higher_price(client, clock, wk, monkeypatch):
    monkeypatch.setattr(eco, "archive_unlock_cost", lambda difficulty, *, weekend=False: 100)  # new players start with 100 coins
    start = content.opens_at(wk)
    live = await new_player(client, "wk2-live")
    late = await new_player(client, "wk2-late")
    clock(start + timedelta(hours=26))
    await client.get("/v1/cases/w099", headers=live["headers"])
    sol = wk.data["solution"]
    solved = (await client.post("/v1/cases/w099/accuse", headers=live["headers"],
                                json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert solved["result"] == "solved"

    # while it is open: free, not in the archive, and "unlock" does not charge
    lst = (await client.get("/v1/cases", headers=late["headers"])).json()
    assert lst["weekly"]["id"] == "w099" and all(r["id"] != "w099" for r in lst["archive"])
    coins = (await client.get("/v1/me", headers=late["headers"])).json()["coins"]
    await client.post("/v1/cases/w099/unlock", headers=late["headers"])
    assert (await client.get("/v1/me", headers=late["headers"])).json()["coins"] == coins

    # after it closed: archive card, locked, with the weekend price
    clock(content.weekly_closes_at(wk) + timedelta(minutes=1))
    coins = (await client.get("/v1/me", headers=late["headers"])).json()["coins"]  # a new day: its login reward is in already
    lst = (await client.get("/v1/cases", headers=late["headers"])).json()
    row = next(r for r in lst["archive"] if r["id"] == "w099")
    assert row["weekend"] is True and row["locked"] is True and row["unlock_cost"] == 100 and lst["weekly"] is None
    r = await client.get("/v1/cases/w099", headers=late["headers"])
    assert r.status_code == 402 and r.json()["detail"] == {"error": "locked", "cost": 100, "lost": False}
    # the player who solved it live keeps it, free
    mine = next(r for r in (await client.get("/v1/cases", headers=live["headers"])).json()["archive"] if r["id"] == "w099")
    assert mine["locked"] is False and mine["solved"] is True

    # buying it: once only, even if asked twice
    r1 = await client.post("/v1/cases/w099/unlock", headers=late["headers"])
    r2 = await client.post("/v1/cases/w099/unlock", headers=late["headers"])
    assert r1.status_code == 200 and r2.status_code == 200
    assert (await client.get("/v1/me", headers=late["headers"])).json()["coins"] == coins - 100
    case = (await client.get("/v1/cases/w099", headers=late["headers"])).json()["case"]
    assert len(case["chapters"]) == 2  # every chapter is open

    # solving it in the archive pays like a normal archive case: no weekend reward, no early bonus
    r = (await client.post("/v1/cases/w099/accuse", headers=late["headers"],
                           json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert r["result"] == "solved" and r["reward"] == eco.solve_reward(wk.data.get("difficulty"), 3) and r["early_bonus"] == 0


async def test_not_enough_coins_for_the_weekend_archive(client, clock, wk):
    clock(content.weekly_closes_at(wk) + timedelta(minutes=1))
    h = (await new_player(client, "wk2-poor"))["headers"]  # 100 coins, the price is 250
    r = await client.post("/v1/cases/w099/unlock", headers=h)
    assert r.status_code == 402 and r.json()["detail"] == {"error": "not_enough_coins", "need": eco.archive_unlock_cost(wk.data.get("difficulty"), weekend=True)}

