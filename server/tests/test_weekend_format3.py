"""Weekend format 3 (18 Oct 2026): two nights. Night 1 has its own question («کی دروغ می‌گه؟»), the newcomer suspect and the
night-2 cards stay hidden until chapter 2, a solve on night 1 pays a bigger early bonus and earns a plaque. Deterministic
clocks, a case built from w001 inside the test (no story is written here)."""
import copy
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")
THU = date(2026, 11, 5)  # a Thursday
NIGHT1_CARDS = {"e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8"}


def make_case3() -> content.Case:
    base = content.weekly_cases()[0]
    d = copy.deepcopy(base.data)
    culprit = d["solution"]["culprit"]
    others = [s["id"] for s in d["suspects"] if s["id"] != culprit]
    newcomer, liar = others[0], others[1]
    later = [e["id"] for e in d["evidence"] if e["id"] not in NIGHT1_CARDS]
    d.update({"id": "w098", "number": 98, "publish": THU.isoformat(), "format": 3, "open_hour": 9, "closes_hours": 36})
    d["chapters"] = [{"title": "شب اول", "at_hours": 0},
                     {"title": "شب دوم", "at_hours": 12, "text": "مظنون تازه و مدارک جدید", "evidence": later}]
    for s in d["suspects"]:
        s["reactions"] = {"e1": "این رو نمی‌دونم از کجاست."}
        s["appears_chapter"] = 1 if s["id"] == newcomer else 0
    next(s for s in d["suspects"] if s["id"] == culprit)["reactions"]["e14"] = "خب... اون شب اونجا بودم."
    d["night1"] = {"question": "کی دروغ می‌گه؟", "liar": liar, "card": "e3", "explanation": "کارت ۳ حرف او را رد می‌کند."}
    return content.Case(id="w098", number=98, publish=THU, data=d)


@pytest.fixture
def wk(monkeypatch):
    c = make_case3()
    monkeypatch.setattr(content, "weekly_cases", lambda: (c,))
    monkeypatch.setattr(content, "is_weekly", lambda cid: cid.startswith("w"))
    return c


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def _newcomer(c):
    return next(s["id"] for s in c.data["suspects"] if s.get("appears_chapter") == 1)


async def _coins(client, h) -> int:
    return (await client.get("/v1/me", headers=h)).json()["coins"]


def test_new_schedule_thursday_morning_to_friday_night():
    assert (content.WEEKEND_OPEN_WEEKDAY, content.WEEKEND_OPEN_HOUR, content.WEEKLY_HOURS) == (3, 9, 36)
    assert content.weekend_schedule()["text"] == "هر هفته پنجشنبه صبح ساعت ۹ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری."
    # w001 keeps its own 48 h window (it says so in its file)
    w1 = content.weekly_by_id("w001")
    assert content.weekly_closes_at(w1) - content.opens_at(w1) == timedelta(hours=48)


def test_format3_timing_and_validation(wk):
    assert content.opens_at(wk) == datetime(2026, 11, 5, 9, tzinfo=TEHRAN)
    assert content.weekly_all_open_at(wk) == datetime(2026, 11, 5, 21, tzinfo=TEHRAN)  # chapter 2 at 21:00
    assert content.weekly_closes_at(wk) == datetime(2026, 11, 6, 21, tzinfo=TEHRAN)    # Friday 21:00
    content.validate_weekly(wk.data)

    def broken(mutate):
        d = copy.deepcopy(wk.data)
        mutate(d)
        with pytest.raises(content.CaseError):
            content.validate_weekly(d)

    culprit = wk.culprit
    two_new = [s["id"] for s in wk.data["suspects"] if s["id"] not in (culprit, _newcomer(wk), wk.data["night1"]["liar"])][0]
    broken(lambda d: next(s for s in d["suspects"] if s["id"] == two_new).update(appears_chapter=1))   # two newcomers
    broken(lambda d: [s.update(appears_chapter=0) for s in d["suspects"]])                              # no newcomer
    broken(lambda d: next(s for s in d["suspects"] if s["id"] == culprit).update(appears_chapter=1))   # culprit is the newcomer
    broken(lambda d: next(s for s in d["suspects"] if s.get("appears_chapter") == 1).update(appears_chapter=2))
    broken(lambda d: d["night1"].update(liar=culprit))                                                  # liar = culprit
    broken(lambda d: d["night1"].update(liar=_newcomer(wk)))                                            # liar not there on night 1
    broken(lambda d: d["night1"].update(card="e14"))                                                    # card from night 2
    broken(lambda d: d["night1"].update(card="zz"))
    broken(lambda d: d["night1"].pop("explanation"))
    broken(lambda d: d.pop("night1"))
    broken(lambda d: d["chapters"].append({"title": "x", "at_hours": 20}))                              # three chapters
    broken(lambda d: d["chapters"][1].pop("text"))
    # the older formats still load without any of this (w001 has no format, w002 is format 2)
    import json
    for name, fmt in (("w001", None), ("w002", 2)):
        data = json.loads((content.WEEKLY_DIR / f"{name}.json").read_text(encoding="utf-8"))
        assert data.get("format") == fmt
        content.validate_weekly(data)


async def test_night1_hides_the_newcomer_and_the_night2_cards(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))
    h = (await new_player(client, "f3-public"))["headers"]
    data = (await client.get("/v1/cases/w098", headers=h)).json()
    case = data["case"]
    ids = {s["id"] for s in case["suspects"]}
    assert _newcomer(wk) not in ids and len(ids) == len(wk.data["suspects"]) - 1
    assert {e["id"] for e in case["evidence"]} == NIGHT1_CARDS and all(e["chapter"] == 1 for e in case["evidence"])
    # nothing about the answer leaks: no liar, card or explanation, no reactions
    n1 = case["night1"]
    assert n1 == {"question": "کی دروغ می‌گه؟", "open": True, "reward": eco.WEEKEND_LIAR_REWARD}
    assert "liar" not in str(case) and "explanation" not in n1 and all("reactions" not in s for s in case["suspects"])
    # a teaser for night 2 with counts only (no names)
    n2 = case["night2"]
    assert n2["new_suspects"] == 1 and n2["new_cards"] == len(wk.data["evidence"]) - len(NIGHT1_CARDS) and n2["open"] is False
    assert n2["opens_at"] == int(content.weekly_all_open_at(wk).timestamp())
    assert data["progress"]["night1"] is None

    # chapter 2: the newcomer and the new cards (marked as night 2) appear, the question is closed
    clock(content.opens_at(wk) + timedelta(hours=13))
    case = (await client.get("/v1/cases/w098", headers=h)).json()["case"]
    assert _newcomer(wk) in {s["id"] for s in case["suspects"]} and len(case["suspects"]) == len(wk.data["suspects"])
    assert {e["chapter"] for e in case["evidence"]} == {1, 2}
    assert case["night1"]["open"] is False and case["night2"]["open"] is True


async def test_the_newcomer_cannot_be_accused_questioned_or_shown_cards_on_night_1(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))
    h = (await new_player(client, "f3-hidden"))["headers"]
    await client.get("/v1/cases/w098", headers=h)
    new = _newcomer(wk)
    assert (await client.post("/v1/cases/w098/accuse", headers=h, json={"suspect": new, "motive": "m1"})).status_code == 404
    assert (await client.post("/v1/cases/w098/show", headers=h, json={"suspect": new, "evidence": "e1"})).status_code == 404
    assert (await client.post("/v1/cases/w098/seen", headers=h, json={"suspect": new})).status_code == 404
    assert (await client.post("/v1/cases/w098/liar", headers=h, json={"suspect": new})).status_code == 404
    clock(content.opens_at(wk) + timedelta(hours=13))
    assert (await client.post("/v1/cases/w098/show", headers=h, json={"suspect": new, "evidence": "e1"})).status_code == 200
    assert (await client.post("/v1/cases/w098/seen", headers=h, json={"suspect": new})).status_code == 200


async def test_liar_question_pays_once_and_has_one_try(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))
    liar = wk.data["night1"]["liar"]
    wrong = next(s["id"] for s in wk.data["suspects"] if s["id"] not in (liar, _newcomer(wk)))

    a = (await new_player(client, "f3-liar-a"))["headers"]
    await client.get("/v1/cases/w098", headers=a)
    before = await _coins(client, a)
    r = (await client.post("/v1/cases/w098/liar", headers=a, json={"suspect": liar})).json()
    assert r["ok"] is True and r["reward"] == eco.WEEKEND_LIAR_REWARD and r["coins"] == before + eco.WEEKEND_LIAR_REWARD
    n1 = r["progress"]["night1"]
    assert n1["ok"] and n1["card"] == "e3" and n1["explanation"] and n1["pick"] == liar
    # one try: a second tap (or a double request) pays nothing more
    again = await client.post("/v1/cases/w098/liar", headers=a, json={"suspect": liar})
    assert again.status_code == 409 and again.json()["detail"] == "already_answered"
    assert await _coins(client, a) == before + eco.WEEKEND_LIAR_REWARD
    assert (await client.get("/v1/cases/w098", headers=a)).json()["progress"]["night1"]["ok"] is True

    # a wrong pick pays nothing, still reveals the answer, and cannot be retried
    b = (await new_player(client, "f3-liar-b"))["headers"]
    await client.get("/v1/cases/w098", headers=b)
    before = await _coins(client, b)
    r = (await client.post("/v1/cases/w098/liar", headers=b, json={"suspect": wrong})).json()
    assert r["ok"] is False and r["reward"] == 0 and r["progress"]["night1"]["liar"] == liar
    assert (await client.post("/v1/cases/w098/liar", headers=b, json={"suspect": liar})).status_code == 409
    assert await _coins(client, b) == before

    # it does not touch the main case: still open, no tries lost
    prog = (await client.get("/v1/cases/w098", headers=b)).json()["progress"]
    assert not prog["solved"] and prog["attempts_left"] == eco.MAX_ATTEMPTS

    # closed once chapter 2 opens; needs the case opened first
    c = (await new_player(client, "f3-liar-c"))["headers"]
    assert (await client.post("/v1/cases/w098/liar", headers=c, json={"suspect": liar})).status_code == 409
    await client.get("/v1/cases/w098", headers=c)
    clock(content.opens_at(wk) + timedelta(hours=13))
    r = await client.post("/v1/cases/w098/liar", headers=c, json={"suspect": liar})
    assert r.status_code == 409 and r.json()["detail"] == "night1_closed"


async def test_liar_endpoint_only_exists_for_format_3(client, clock, monkeypatch):
    # an ordinary format-2 weekend case has no night-1 question
    base = content.weekly_cases()[0]
    d = copy.deepcopy(base.data)
    d.update({"id": "w097", "number": 97, "publish": THU.isoformat(), "format": 2, "open_hour": 9, "closes_hours": 36})
    d["chapters"] = [{"title": "a", "at_hours": 0}, {"title": "b", "at_hours": 12, "text": "t", "evidence": ["e14"]}]
    for s in d["suspects"]:
        s["reactions"] = {"e1": "x"}
    next(s for s in d["suspects"] if s["id"] == d["solution"]["culprit"])["reactions"]["e14"] = "y"
    c = content.Case(id="w097", number=97, publish=THU, data=d)
    monkeypatch.setattr(content, "weekly_cases", lambda: (c,))
    monkeypatch.setattr(content, "is_weekly", lambda cid: cid.startswith("w"))
    clock(content.opens_at(c) + timedelta(hours=1))
    h = (await new_player(client, "f3-fmt2"))["headers"]
    await client.get("/v1/cases/w097", headers=h)
    assert (await client.post("/v1/cases/w097/liar", headers=h, json={"suspect": "s1"})).status_code == 404
    assert "night1" not in (await client.get("/v1/cases/w097", headers=h)).json()["case"]


async def test_night1_solve_pays_the_bigger_bonus_and_earns_the_plaque(client, clock, wk):
    assert eco.WEEKLY_EARLY_BONUS == 80
    sol = wk.data["solution"]
    clock(content.opens_at(wk) + timedelta(hours=1))
    a = (await new_player(client, "f3-solve-a"))["headers"]
    await client.get("/v1/cases/w098", headers=a)
    r = (await client.post("/v1/cases/w098/accuse", headers=a, json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert r["result"] == "solved" and r["stars"] == 3
    assert r["early_bonus"] == eco.WEEKLY_EARLY_BONUS and r["reward"] == eco.WEEKLY_REWARD[3] + eco.WEEKLY_EARLY_BONUS
    assert "weekend_night1" in {x["id"] for x in r["gains"]["achievements"]}

    # solved on night 2: the normal reward, no bonus, no plaque
    clock(content.opens_at(wk) + timedelta(hours=13))
    b = (await new_player(client, "f3-solve-b"))["headers"]
    await client.get("/v1/cases/w098", headers=b)
    r = (await client.post("/v1/cases/w098/accuse", headers=b, json={"suspect": wk.culprit, "motive": sol["motive"]})).json()
    assert r["result"] == "solved" and r["early_bonus"] == 0
    assert "weekend_night1" not in {x["id"] for x in r["gains"]["achievements"]}


async def test_case_list_tells_the_app_when_chapter_2_opens(client, clock, wk):
    clock(content.opens_at(wk) + timedelta(hours=1))
    h = (await new_player(client, "f3-list"))["headers"]
    lst = (await client.get("/v1/cases", headers=h)).json()
    assert lst["weekly"]["id"] == "w098" and lst["weekly"]["category"] in content.CATEGORIES
    assert lst["weekly_format"] == 3 and lst["weekly_next_chapter_at"] == int(content.weekly_all_open_at(wk).timestamp())
    clock(content.opens_at(wk) + timedelta(hours=13))
    lst = (await client.get("/v1/cases", headers=h)).json()
    assert lst["weekly_next_chapter_at"] is None
