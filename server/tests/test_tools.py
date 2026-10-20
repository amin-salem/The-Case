"""Detective tools «ابزارهای کارآگاهی»: logic on the real case files, stock/spend atomicity, once per case, the
tutorial tool, the kill switch and the abuse paths."""
import asyncio
import copy
import re
from datetime import timedelta

import pytest
from sqlalchemy import delete, func, select, update

from app import content, db, economy as eco, progress, tools
from app.config import get_settings
from app.models import CaseToolUse, CoinLog, MissionDay, Player, PlayerTool
from app.services import ratelimit as rl
from .conftest import new_player
from .test_anticheat import fail_case
from .test_ratelimit import auth, clock, mk  # noqa: F401  (the limiter's deterministic clock fixture)
from .test_difficulty_economy import balance, fund

REAL = [c for c in content.all_cases()]


def spare_cards(data):
    """Cards that are neither proof nor cited by id in the explanation (all of them are fine to certify in a test)."""
    cited = set(re.findall(r"\be\d+\b", data["solution"]["explanation"]))
    return [e["id"] for e in data["evidence"] if e["id"] not in data["solution"]["proof"] and e["id"] not in cited]


def tooled(case_id="c020"):
    """A real case plus the optional tool data an author would add."""
    base = content.by_id(case_id)
    d = copy.deepcopy(base.data)
    d["solution"]["irrelevant"] = spare_cards(d)[:1]
    assert d["solution"]["irrelevant"], "pick a case with a spare card"
    for s in d["suspects"][:2]:
        s["camera"] = [f"{s['name']} هنگام انتظار چند بار به ساعت مچی‌اش نگاه کرد و بعد دوباره نشست."]
    content.validate(d)
    return content.Case(base.id, base.number, base.publish, d)


@pytest.fixture
def today(monkeypatch):
    c = tooled()
    monkeypatch.setattr(content, "all_cases", lambda: (c,))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(c) + timedelta(hours=1))
    return c


async def start(client, today, name, coins=500):
    p = await new_player(client, name)
    await fund(p["player_id"], coins)
    assert (await client.get(f"/v1/cases/{today.id}", headers=p["headers"])).status_code == 200
    return p


def url(c, kind, how):
    return f"/v1/cases/{c.id}/tools/{kind}/{how}"


async def coin_rows(pid, prefix):
    async with db.SessionLocal() as s:
        return (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid, CoinLog.reason.like(prefix + "%")))).all()


async def uses(pid):
    async with db.SessionLocal() as s:
        return (await s.scalars(select(CaseToolUse).where(CaseToolUse.player_id == pid))).all()


async def give(pid, kind, n=1, free_used=False):
    async with db.SessionLocal() as s:
        await s.merge(PlayerTool(player_id=pid, kind=kind, count=n, free_used=free_used))
        await s.commit()


# ---- the logic on the REAL case files ---------------------------------------------------------------------------------

def test_fingerprint_on_every_real_case_never_singles_out_the_culprit():
    offered = 0
    for c in REAL:
        d = c.data
        if not tools.fingerprint_safe(d):
            continue
        offered += 1
        touched = tools.touched_ids(d)
        assert d["solution"]["culprit"] in touched
        assert 2 <= len(touched) <= len(d["suspects"]) - 1, c.id
        answers = {s["id"]: tools.compute("fingerprint", d, "p", s["id"]) for s in d["suspects"]}
        assert all(a is not None and a["main"] == (sid in touched) for sid, a in answers.items())
        assert sum(a["main"] for a in answers.values()) >= 2  # a "yes" is never "this is the culprit"
        assert "گناهکار" not in str(answers) and "بی‌گناه" not in str(answers)
    assert offered >= 25, offered  # the tool is on offer in most of the archive


def test_real_cases_without_authored_data_offer_neither_magnifier_nor_camera():
    for c in REAL:
        av = tools.availability(c.data)
        assert not av["magnifier"]["available"] and not av["camera"]["available"], c.id
        assert tools.compute("magnifier", c.data, "p", None) is None
        assert tools.compute("camera", c.data, "p", c.data["suspects"][0]["id"]) is None


def test_magnifier_never_marks_a_proof_or_cited_card(today):
    d = today.data
    cited = set(re.findall(r"\be\d+\b", d["solution"]["explanation"]))
    for pid in ("a", "b", "c", "d"):
        r = tools.compute("magnifier", d, pid, None)
        assert r["card"] in d["solution"]["irrelevant"]
        assert r["card"] not in d["solution"]["proof"] and r["card"] not in cited
        assert d["solution"]["culprit"] not in r["text"]
    assert tools.compute("magnifier", d, "a", None) == tools.compute("magnifier", d, "a", None)


def test_tool_data_validation_refuses_unsafe_files():
    base = content.by_id("c020").data
    def bad(mutate):
        d = copy.deepcopy(base)
        mutate(d)
        with pytest.raises(content.CaseError):
            content.validate(d)
    bad(lambda d: d["solution"].__setitem__("irrelevant", [d["solution"]["proof"][0]]))      # a proof card
    cited = sorted(set(re.findall(r"\be\d+\b", base["solution"]["explanation"])))[0]
    bad(lambda d: d["solution"].__setitem__("irrelevant", [cited]))                          # cited by the explanation
    bad(lambda d: d["solution"].__setitem__("irrelevant", ["e99"]))                          # unknown card
    bad(lambda d: d["solution"].__setitem__("irrelevant", spare_cards(d) * 3))               # too many / duplicates
    bad(lambda d: d["suspects"][0].__setitem__("camera", "کوتاه"))                            # too short
    bad(lambda d: d["suspects"][0].__setitem__("camera", ["x" * 30] * 4))                    # too many lines


def test_public_case_never_carries_tool_secrets(today):
    pub = today.public()
    assert "solution" not in pub
    assert all("camera" not in s for s in pub["suspects"])
    assert any("camera" in s for s in today.data["suspects"])  # the private copy keeps them


# ---- tray, tutorial, buying, once per case ------------------------------------------------------------------------------

async def test_tray_lists_three_tools_with_prices(client, today):
    p = await start(client, today, "tray")
    r = (await client.get(f"/v1/cases/{today.id}/tools", headers=p["headers"])).json()
    assert r["enabled"] and [t["kind"] for t in r["tools"]] == list(tools.KINDS)
    assert {t["kind"]: t["price"] for t in r["tools"]} == eco.TOOL_PRICES
    assert all(t["free_available"] and t["usable"] and t["count"] == 0 and not t["used"] for t in r["tools"])
    assert all(eco.TOOL_PRICES[k] < eco.HINT_COSTS[i] for i, k in enumerate(tools.KINDS))  # a bit under the hint price


async def test_first_of_each_kind_is_free_once_and_costs_no_coins(client, today):
    p = await start(client, today, "tutorial")
    h, pid = p["headers"], p["player_id"]
    r = await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s1"})
    assert r.status_code == 200 and r.json()["consumed"] and r.json()["source"] == "free"
    assert await balance(pid) == 500
    # the tutorial tool is spent: on another case the same kind now needs a purchase (simulate "another case")
    async with db.SessionLocal() as s:
        await s.execute(delete(CaseToolUse).where(CaseToolUse.player_id == pid))
        await s.commit()
    again = await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s1"})
    assert again.status_code == 409 and again.json()["detail"] == {"error": "no_tool", "price": eco.TOOL_PRICES["fingerprint"]}
    assert await uses(pid) == [] and await balance(pid) == 500
    # a different kind still has its own free tutorial tool
    m = await client.post(url(today, "magnifier", "use"), headers=h, json={})
    assert m.status_code == 200 and m.json()["source"] == "free"


async def test_free_tutorial_tool_is_claimed_once_even_when_asked_twice_at_once(client, today):
    p = await start(client, today, "tutorial-twice")
    rs = await asyncio.gather(*[client.post(url(today, "magnifier", "use"), headers=p["headers"], json={}) for _ in range(3)])
    assert sorted(r.status_code for r in rs) == [200, 409, 409]
    assert len(await uses(p["player_id"])) == 1
    async with db.SessionLocal() as s:
        assert await tools.claim_free(s, p["player_id"], "magnifier") is False
        assert await tools.claim_free(s, p["player_id"], "camera") is True
        assert await tools.claim_free(s, p["player_id"], "camera") is False


async def test_buying_charges_the_price_once_and_double_tap_is_safe(client, today):
    p = await start(client, today, "buy-1")
    h, pid = p["headers"], p["player_id"]
    rs = await asyncio.gather(*[client.post(url(today, "fingerprint", "buy"), headers=h, json={"suspect": "s2"}) for _ in range(3)])
    assert sorted(r.status_code for r in rs) == [200, 409, 409]
    assert await balance(pid) == 500 - eco.TOOL_PRICES["fingerprint"]
    rows = await coin_rows(pid, "tool_")
    assert len(rows) == 1 and rows[0].amount == -eco.TOOL_PRICES["fingerprint"] and rows[0].reason == f"tool_fingerprint:{today.id}"
    ok = next(r for r in rs if r.status_code == 200).json()
    assert ok["source"] == "coins" and ok["coins"] == 500 - eco.TOOL_PRICES["fingerprint"]
    assert len(await uses(pid)) == 1


async def test_not_enough_coins_changes_nothing(client, today):
    p = await start(client, today, "poor", coins=eco.TOOL_PRICES["camera"] - 1)
    r = await client.post(url(today, "camera", "buy"), headers=p["headers"], json={"suspect": "s1"})
    assert r.status_code == 402 and r.json()["detail"] == {"error": "not_enough_coins", "need": eco.TOOL_PRICES["camera"]}
    assert await balance(p["player_id"]) == eco.TOOL_PRICES["camera"] - 1
    assert await uses(p["player_id"]) == [] and await coin_rows(p["player_id"], "tool_") == []


async def test_once_per_case_and_the_result_is_pinned(client, today):
    p = await start(client, today, "pinned")
    h = p["headers"]
    first = await client.post(url(today, "magnifier", "buy"), headers=h, json={})
    assert first.status_code == 200
    card = first.json()["result"]["card"]
    assert card not in today.proof
    after = await balance(p["player_id"])
    for how in ("buy", "use"):
        r = await client.post(url(today, "magnifier", how), headers=h, json={})
        assert r.status_code == 409 and r.json()["detail"]["error"] == "already_used"
        assert r.json()["detail"]["result"]["card"] == card
    assert await balance(p["player_id"]) == after
    tray = (await client.get(f"/v1/cases/{today.id}/tools", headers=h)).json()
    mag = next(t for t in tray["tools"] if t["kind"] == "magnifier")
    assert mag["used"] and not mag["usable"] and mag["result"]["card"] == card
    # reopening the case later still shows it, even for a brand new session of the same player
    assert (await client.get(f"/v1/cases/{today.id}/tools", headers=h)).json()["tools"][0]["result"]["card"] == card


async def test_stock_is_spent_atomically(client, today):
    p = await start(client, today, "stock")
    pid, h = p["player_id"], p["headers"]
    await give(pid, "fingerprint", 1, free_used=True)
    rs = await asyncio.gather(*[client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s3"}) for _ in range(3)])
    assert sorted(r.status_code for r in rs) == [200, 409, 409]
    assert next(r for r in rs if r.status_code == 200).json()["source"] == "stock"
    async with db.SessionLocal() as s:
        row = await s.get(PlayerTool, (pid, "fingerprint"))
        assert row.count == 0
        assert await tools.spend_stock(s, pid, "fingerprint") is False  # never below zero
    assert await balance(pid) == 500


async def test_nothing_new_is_not_consumed(client, today):
    p = await start(client, today, "nothing")
    h, pid = p["headers"], p["player_id"]
    bare = today.data["suspects"][-1]["id"]  # no camera line on this suspect
    for how in ("use", "buy"):
        r = await client.post(url(today, "camera", how), headers=h, json={"suspect": bare})
        assert r.status_code == 200 and r.json()["consumed"] is False and r.json()["nothing_new"] is True
    assert await balance(pid) == 500 and await uses(pid) == []
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(PlayerTool).where(PlayerTool.player_id == pid, PlayerTool.free_used.is_(True))) == 0
    ok = await client.post(url(today, "camera", "use"), headers=h, json={"suspect": today.data["suspects"][0]["id"]})
    assert ok.status_code == 200 and ok.json()["consumed"] and "دوربین مخفی" in ok.json()["result"]["text"]


async def test_tools_never_change_stars_and_never_count_as_investigation(client, today, monkeypatch):
    monkeypatch.setattr(eco, "MIN_ACTIVE_SECONDS", 90)
    monkeypatch.setattr(eco, "MIN_SUSPECTS_SEEN", 2)
    p = await start(client, today, "ranked")
    h = p["headers"]
    for kind, body in (("magnifier", {}), ("fingerprint", {"suspect": "s1"}), ("camera", {"suspect": "s1"})):
        assert (await client.post(url(today, kind, "buy"), headers=h, json=body)).status_code == 200
    r = await client.post(f"/v1/cases/{today.id}/accuse", headers=h,
                          json={"suspect": today.culprit, "evidence": sorted(today.proof)[0]})
    assert r.status_code == 200
    body = r.json()
    # right at once, with no hints and no wrong tries, but no real investigating time: unranked, 1 star (as without tools)
    assert body["result"] == "solved" and body["unranked"] is True and body["stars"] == 1


async def test_finished_case_refuses_tools_but_shows_results(client, today):
    p = await start(client, today, "finished")
    h = p["headers"]
    assert (await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s1"})).status_code == 200
    r = await client.post(f"/v1/cases/{today.id}/accuse", headers=h,
                          json={"suspect": today.culprit, "evidence": sorted(today.proof)[0]})
    assert r.json()["result"] == "solved"
    r = await client.post(url(today, "magnifier", "use"), headers=h, json={})
    assert r.status_code == 409 and r.json()["detail"] == "case_finished"
    tray = (await client.get(f"/v1/cases/{today.id}/tools", headers=h)).json()
    assert next(t for t in tray["tools"] if t["kind"] == "fingerprint")["result"] is not None
    assert not any(t["usable"] for t in tray["tools"])


async def test_lost_case_refuses_tools(client, today):
    p = await start(client, today, "lost-tools")
    await fail_case(client, p["headers"], today)
    r = await client.post(url(today, "magnifier", "buy"), headers=p["headers"], json={})
    assert r.status_code == 409 and await balance(p["player_id"]) == 500


# ---- off switches and abuse -----------------------------------------------------------------------------------------------

async def test_kill_switch(client, today, monkeypatch):
    p = await start(client, today, "kill")
    monkeypatch.setattr(get_settings(), "detective_tools_enabled", False)
    r = await client.post(url(today, "fingerprint", "buy"), headers=p["headers"], json={"suspect": "s1"})
    assert r.status_code == 503 and r.json()["detail"] == "tools_disabled"
    tray = (await client.get(f"/v1/cases/{today.id}/tools", headers=p["headers"])).json()
    assert tray["enabled"] is False and tray["tools"] == [] and tray["message"]
    assert await balance(p["player_id"]) == 500 and await uses(p["player_id"]) == []
    async with db.SessionLocal() as s:  # no drops either while it is off
        await tools_drop_check(s, p["player_id"])


async def tools_drop_check(s, pid):
    pl = await s.get(Player, pid)
    pl.best_streak = 30
    await progress.check_achievements(s, pl, progress.Gains())
    await s.commit()
    assert await s.scalar(select(func.count()).select_from(PlayerTool).where(PlayerTool.player_id == pid, PlayerTool.count > 0)) == 0


async def test_weekend_and_story_cases_have_no_tools(client, monkeypatch):
    w = content.weekly_cases()[0]
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(w) + timedelta(hours=1))
    p = await new_player(client, "weekend-tools")
    h = p["headers"]
    tray = (await client.get(f"/v1/cases/{w.id}/tools", headers=h)).json()
    assert tray["enabled"] is False and tray["tools"] == [] and "روزانه" in tray["message"]
    r = await client.post(url(w, "fingerprint", "use"), headers=h, json={"suspect": "s1"})
    assert r.status_code == 409 and r.json()["detail"] == "tools_not_for_this_case"


async def test_bad_requests(client, today):
    p = await start(client, today, "abuse")
    h = p["headers"]
    assert (await client.post(url(today, "x-ray", "use"), headers=h, json={})).status_code == 404
    assert (await client.post(url(today, "fingerprint", "use"), headers=h, json={})).status_code == 422
    assert (await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s999"})).status_code == 422
    assert (await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": "s" * 5000})).status_code == 422
    assert (await client.post(url(today, "fingerprint", "use"), headers=h, json={"suspect": ["s1"]})).status_code == 422
    assert (await client.post(url(today, "fingerprint", "use"), json={"suspect": "s1"})).status_code == 401
    assert (await client.post(f"/v1/cases/c999/tools/camera/use", headers=h, json={})).status_code == 404
    other = await new_player(client, "abuse-2")  # never opened the case
    r = await client.post(url(today, "fingerprint", "buy"), headers=other["headers"], json={"suspect": "s1"})
    assert r.status_code == 409 and r.json()["detail"] == "open_case_first"
    assert await uses(p["player_id"]) == [] and await balance(p["player_id"]) == 500


async def test_results_belong_to_the_player_who_used_them(client, today):
    a = await start(client, today, "iso-a")
    b = await start(client, today, "iso-b")
    assert (await client.post(url(today, "fingerprint", "use"), headers=a["headers"], json={"suspect": "s1"})).status_code == 200
    tray = (await client.get(f"/v1/cases/{today.id}/tools", headers=b["headers"])).json()
    assert all(t["result"] is None and not t["used"] for t in tray["tools"])


async def test_buy_and_use_have_their_own_rate_limits(clock):
    routed = {n for m, rx, n in rl.ROUTES if "tools" in rx.pattern}
    assert routed == {"tool_buy", "tool_use"}
    assert rl.DEFAULTS["tool_buy"].store == "strict" and rl.DEFAULTS["tool_use"].store == "mem"
    buy, use = "/v1/cases/c001/tools/camera/buy", "/v1/cases/c001/tools/camera/use"
    async with mk() as c:
        h = auth("player-tools")
        codes = [(await c.post(buy, headers=h, json={})).status_code for _ in range(4)]  # 3 per 10 s
        assert 429 not in codes[:3] and codes[3] == 429
        clock.advance(10)
        assert (await c.post(buy, headers=h, json={})).status_code != 429
        got = [(await c.post(use, headers=h, json={})).status_code for _ in range(11)]  # using is relaxed: 10 per 10 s
        assert 429 not in got[:10] and got[10] == 429


# ---- the only other free sources: a rare drop at existing reward points ---------------------------------------------------

async def test_drop_from_an_achievement_is_once(client):
    p = await new_player(client, "drop-ach")
    pid = p["player_id"]
    async with db.SessionLocal() as s:
        pl = await s.get(Player, pid)
        pl.best_streak = 30
        gains = progress.Gains()
        await progress.check_achievements(s, pl, gains)
        await s.commit()
        again = progress.Gains()
        await progress.check_achievements(s, pl, again)
        await s.commit()
    assert any(a.get("tool") == "fingerprint" for a in gains.achievements)
    assert not again.achievements
    async with db.SessionLocal() as s:
        assert (await s.get(PlayerTool, (pid, "fingerprint"))).count == 1


async def test_drop_from_the_seventh_chest_day_is_once(client):
    p = await new_player(client, "drop-chest")
    pid, h = p["player_id"], p["headers"]
    day = content.mission_day_str()
    from datetime import date
    yesterday = (date.fromisoformat(day) - timedelta(days=1)).isoformat()
    from app import missions
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(chest_streak=6, last_chest_day=yesterday))
        s.add(MissionDay(player_id=pid, day=day, counts={m.event: m.target for m in missions.for_day(day)}, claimed=False))
        await s.commit()
    r = await client.post("/v1/missions/claim", headers=h)
    assert r.status_code == 200 and r.json()["tool"] in tools.KINDS
    assert (await client.post("/v1/missions/claim", headers=h)).status_code == 409
    async with db.SessionLocal() as s:
        total = await s.scalar(select(func.sum(PlayerTool.count)).where(PlayerTool.player_id == pid))
    assert total == 1
