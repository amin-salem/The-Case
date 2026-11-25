"""«کی کجا؟» (app/kikoja.py, Amin 25 Nov 2026): hidden unless the config shows it, the answer never leaks before the puzzle is solved,
the proof needs the witness when the contradiction alone does not clear the other speaker, three mistakes fail the file, the
reward and the hint price are paid once, and every pooled puzzle really has one thief and only true statements besides his lie.
SQLite and PostgreSQL."""
import asyncio

import pytest
from sqlalchemy import delete

from app import db, kikoja
from app.models import ConfigValue, KikojaRun
from app.services import remote_config
from .conftest import ADMIN, new_player
from .test_difficulty_economy import balance, fund


@pytest.fixture(autouse=True)
async def clean():
    async def wipe():
        async with db.SessionLocal() as s:
            await s.execute(delete(ConfigValue).where(ConfigValue.key == "kikoja"))
            await s.execute(delete(KikojaRun))
            await s.commit()
        remote_config.invalidate()
    await wipe()
    yield
    await wipe()


async def configure(client, audience="testers"):
    r = await client.put("/admin/config", headers=ADMIN, json={"values": {"kikoja": {"audience": audience}}})
    assert r.status_code == 200, r.text


async def make_tester(client, device, coins=500):
    p = await new_player(client, device, aged=True)
    r = await client.post(f"/admin/api/players/{p['player_id']}/tester", headers=ADMIN, json={"tester": True})
    assert r.status_code == 200, r.text
    await fund(p["player_id"], coins)
    return p


def good_accusation(level="easy"):
    """A complete accusation for today's puzzle of the level (the first accepted contradiction, the first witness set)."""
    pz = kikoja.today_puzzle(level)
    a = pz["answer"]
    con, wits = next(iter(a["cons"].items()))
    return pz, {"who": a["thief"], "lie": a["lie"], "con": con, "wit": wits[0] if wits else []}


def wrong_who(pz):
    return (pz["answer"]["thief"] + 1) % pz["n"]


def url(level, action=""):
    return f"/v1/kikoja/{level}" + (f"/{action}" if action else "")


# ---- the pool itself: a small independent solver (the page and the generator are JavaScript) ---------------------------------
def feasible(cons, n, T, nb, rooms, locks):
    for p in range(n):
        allow, any_ = {}, False
        for q, t, r, neg in cons:
            if q == p:
                any_ = True
                a = allow.setdefault(t, {"pos": set(), "neg": set()})
                a["neg" if neg else "pos"].add(r)
        if not any_:
            continue
        reach = None
        for t in range(T):
            a = allow.get(t)
            if a and len(a["pos"]) > 1:
                return False
            s = set(a["pos"]) if a and a["pos"] else set(rooms)
            if a:
                s -= a["neg"]
            if reach is not None:
                s = {r for r in s if any(r in nb[q] and not (q != r and (q, r, t - 1) in locks) for q in reach)}
            if not s:
                return False
            reach = s
    return True


def house_graph(pz):
    import json
    from pathlib import Path
    doors = json.loads((Path(kikoja.__file__).parent / "content" / "kikoja" / "houses.json").read_text(encoding="utf-8"))[pz["house"]]
    rooms = [r["id"] for r in doors["rooms"]]
    nb = {r: {r} for r in rooms}
    for a, b in doors["doors"]:
        nb[a].add(b)
        nb[b].add(a)
    locks = set()
    for a, b, t in pz["locks"]:
        locks.add((a, b, t))
        locks.add((b, a, t))
    return rooms, nb, locks


def candidate_ok(pz, x, rooms, nb, locks):
    cons = [c for s in pz["S"] if s["p"] != x for c in s["cons"]]
    cons.append([x, pz["k"], pz["target"], False])
    cons += [[q, pz["k"], pz["target"], True] for q in range(pz["n"]) if q != x]
    return feasible(cons, pz["n"], pz["T"], nb, rooms, locks)


def true_of(s, paths):
    return all((paths[p][t] == r) != neg for p, t, r, neg in s["cons"])


def test_every_pooled_puzzle_has_one_thief_and_one_lie():
    pool = kikoja.pool()
    assert len(pool) >= 30
    assert {lv: sum(1 for p in pool if p['level'] == lv) for lv in kikoja.LEVELS} == {lv: 10 for lv in kikoja.LEVELS}
    assert len({p['id'] for p in pool}) == len(pool)
    for pz in pool:
        rooms, nb, locks = house_graph(pz)
        a = pz["answer"]
        ok = [x for x in range(pz["n"]) if candidate_ok(pz, x, rooms, nb, locks)]
        assert ok == [a["thief"]], pz["id"]
        for s in pz["S"]:
            assert true_of(s, a["paths"]) == (s["id"] != a["lie"]), (pz["id"], s["id"])
        assert next(s for s in pz["S"] if s["id"] == a["lie"])["p"] == a["thief"]
        assert a["cons"], pz["id"]
        assert a["paths"][a["thief"]][pz["k"]] == pz["target"]
        assert sum(1 for p in a["paths"] if p[pz["k"]] == pz["target"]) == 1       # the thief was alone with it


def test_every_accepted_proof_is_sound_and_leaks_nothing_wrong():
    for pz in kikoja.pool():
        rooms, nb, locks = house_graph(pz)
        a = pz["answer"]
        by = {s["id"]: s for s in pz["S"]}
        lie = by[a["lie"]]
        for con, wits in a["cons"].items():
            c = by[con]
            assert c["p"] != a["thief"]
            assert not feasible(lie["cons"] + c["cons"], pz["n"], pz["T"], nb, rooms, locks)
            for w in wits[:6]:
                cons = list(lie["cons"]) + [x for i in w for x in by[i]["cons"]]
                cons.append([c["p"], pz["k"], pz["target"], False])
                cons += [[q, pz["k"], pz["target"], True] for q in range(pz["n"]) if q != c["p"]]
                assert not feasible(cons, pz["n"], pz["T"], nb, rooms, locks), (pz["id"], con, w)
                assert all(by[i]["p"] != c["p"] for i in w)


def test_levels_have_the_agreed_shape_and_the_day_turns_at_nine_in_the_morning():
    from datetime import datetime
    from zoneinfo import ZoneInfo
    tz = ZoneInfo("Asia/Tehran")
    shape = {"easy": ("qolhak", 4, 4), "medium": ("qolhak", 5, 5), "hard": ("kashan", 6, 5)}
    for lv, (house, n, T) in shape.items():
        assert all((p["house"], p["n"], p["T"]) == (house, n, T) for p in kikoja.level_pool(lv)), lv
    assert kikoja.day(datetime(2026, 11, 26, 8, 59, tzinfo=tz)).isoformat() == "2026-11-25"
    assert kikoja.day(datetime(2026, 11, 26, 9, 0, tzinfo=tz)).isoformat() == "2026-11-26"
    assert kikoja.day(datetime(2026, 11, 26, 20, 59, tzinfo=tz)) == kikoja.day(datetime(2026, 11, 26, 21, 1, tzinfo=tz))   # 21:00 is NOT a turn
    assert kikoja.next_open(datetime(2026, 11, 26, 8, 0, tzinfo=tz)).isoformat().startswith("2026-11-26T09:00")
    assert kikoja.next_open(datetime(2026, 11, 26, 9, 0, tzinfo=tz)).isoformat().startswith("2026-11-27T09:00")
    # a week of days gives a week of different puzzles on every level
    from datetime import timedelta
    for lv in kikoja.LEVELS:
        ids = []
        for d in range(7):
            gameclock_now = datetime(2026, 11, 26, 12, 0, tzinfo=tz) + timedelta(days=d)
            from app import gameclock
            gameclock.set_clock(lambda n=gameclock_now: n)
            try:
                ids.append(kikoja.today_puzzle(lv)["id"])
            finally:
                gameclock.set_clock(None)
        assert len(set(ids)) == 7, (lv, ids)


# ---- the game through the API --------------------------------------------------------------------------------------------------
async def test_hidden_from_players_who_are_not_testers_and_off_by_default(client):
    plain = await new_player(client, "kk-plain-1", aged=True)
    t = await make_tester(client, "kk-off-1")
    assert (await client.get("/v1/kikoja", headers=t["headers"])).json() == {"visible": False}   # off, even for testers
    await configure(client)
    assert (await client.get("/v1/kikoja", headers=plain["headers"])).json() == {"visible": False}
    for path in ("hint", "accuse", "reopen", "unlock"):
        r = await client.post(url("easy", path), headers=plain["headers"], json={"kind": "time", "who": 0, "lie": "s0", "con": "s1"})
        assert r.status_code == 404, path
    assert (await client.get(url("easy"), headers=plain["headers"])).status_code == 404
    assert (await client.get("/v1/kikoja/impossible", headers=t["headers"])).status_code == 422


async def test_a_tester_sees_three_tiles_and_the_free_puzzle_without_the_answer(client):
    await configure(client)
    t = await make_tester(client, "kk-view-1")
    j = (await client.get("/v1/kikoja", headers=t["headers"])).json()
    assert j["visible"] and [x["level"] for x in j["levels"]] == ["easy", "medium", "hard"] and j["next_at"]
    assert [(x["price"], x["open"]) for x in j["levels"]] == [(0, True), (30, False), (50, False)]
    assert "puzzle" not in str(j) and "answer" not in str(j) and "paths" not in str(j)
    e = (await client.get(url("easy"), headers=t["headers"])).json()
    assert e["puzzle"]["S"] and "answer" not in e["puzzle"] and "reveal" not in e and "paths" not in str(e)
    assert e["run"] == {"mistakes": 0, "hints": [], "reopened": False, "solved": False, "failed": False, "stars": 0, "secs": 0, "paid": 0}
    await configure(client, "all")
    plain = await new_player(client, "kk-all-1", aged=True)
    assert (await client.get("/v1/kikoja", headers=plain["headers"])).json()["visible"] is True


async def test_a_paid_level_stays_closed_until_unlocked_and_never_leaks(client):
    await configure(client)
    t = await make_tester(client, "kk-lock-1")
    for lv in ("medium", "hard"):
        j = (await client.get(url(lv), headers=t["headers"])).json()
        assert j["open"] is False and "puzzle" not in j and "run" not in j and "S" not in str(j) and j["price"] == kikoja.UNLOCK[lv]
        for action, body in (("hint", {"kind": "time"}), ("accuse", {"who": 0, "lie": "s0", "con": "s1"}), ("reopen", None)):
            r = await client.post(url(lv, action), headers=t["headers"], json=body)
            assert r.status_code == 403 and r.json()["detail"]["error"] == "locked", (lv, action)
    assert await balance(t["player_id"]) == 500


async def test_unlock_takes_the_coins_once_even_with_retries_and_races(client):
    await configure(client)
    t = await make_tester(client, "kk-unl-1")
    r = await client.post(url("medium", "unlock"), headers=t["headers"])
    j = r.json()
    assert r.status_code == 200 and j["open"] is True and j["puzzle"]["S"] and "answer" not in j["puzzle"]
    assert await balance(t["player_id"]) == 500 - kikoja.UNLOCK["medium"]
    again = await asyncio.gather(*[client.post(url("medium", "unlock"), headers=t["headers"]) for _ in range(3)])
    assert [x.status_code for x in again] == [200, 200, 200]
    assert await balance(t["player_id"]) == 500 - kikoja.UNLOCK["medium"]
    hard = await asyncio.gather(*[client.post(url("hard", "unlock"), headers=t["headers"]) for _ in range(3)])
    assert [x.status_code for x in hard] == [200, 200, 200]
    assert await balance(t["player_id"]) == 500 - kikoja.UNLOCK["medium"] - kikoja.UNLOCK["hard"]
    tiles = (await client.get("/v1/kikoja", headers=t["headers"])).json()["levels"]
    assert [x["open"] for x in tiles] == [True, True, True]


async def test_unlock_needs_coins_and_the_free_level_costs_nothing(client):
    await configure(client)
    t = await make_tester(client, "kk-unl-2", coins=20)
    r = await client.post(url("medium", "unlock"), headers=t["headers"])
    assert r.status_code == 402 and await balance(t["player_id"]) == 20
    assert (await client.get(url("medium"), headers=t["headers"])).json()["open"] is False
    r = await client.post(url("easy", "unlock"), headers=t["headers"])
    assert r.status_code == 200 and await balance(t["player_id"]) == 20


async def test_a_paid_level_wins_stars_but_never_pays_coins(client):
    await configure(client)
    t = await make_tester(client, "kk-paid-1")
    await client.post(url("hard", "unlock"), headers=t["headers"])
    pz, ok = good_accusation("hard")
    j = (await client.post(url("hard", "accuse"), headers=t["headers"], json=ok | {"secs": 200})).json()
    assert j["ok"] and j["run"]["stars"] == 3 and j["run"]["paid"] == 0 and j["reveal"]["thief"] == pz["answer"]["thief"]
    assert await balance(t["player_id"]) == 500 - kikoja.UNLOCK["hard"]
    tiles = (await client.get("/v1/kikoja", headers=t["headers"])).json()["levels"]
    assert tiles[2]["solved"] is True and tiles[2]["stars"] == 3 and tiles[0]["solved"] is False


async def test_wrong_accusations_say_the_step_and_three_fail_the_file(client):
    await configure(client)
    t = await make_tester(client, "kk-fail-1")
    pz, ok = good_accusation()
    r = await client.post(url("easy", "accuse"), headers=t["headers"], json=ok | {"who": wrong_who(pz)})
    j = r.json()
    assert r.status_code == 200 and j["ok"] is False and j["step"] == "who" and j["run"]["mistakes"] == 1
    r = await client.post(url("easy", "accuse"), headers=t["headers"], json=ok | {"lie": next(s["id"] for s in pz["S"] if s["id"] != ok["lie"])})
    assert r.json()["step"] == "lie" and r.json()["run"]["mistakes"] == 2
    r = await client.post(url("easy", "accuse"), headers=t["headers"], json=ok | {"con": "zz"})
    j = r.json()
    assert j["step"] == "con" and j["run"]["failed"] is True and "reveal" not in j and "paths" not in str(j)
    r = await client.post(url("easy", "accuse"), headers=t["headers"], json=ok)
    assert r.status_code == 409 and r.json()["detail"]["error"] == "failed"


async def test_reopen_costs_once_and_the_win_is_worth_one_star_and_no_reward(client):
    await configure(client)
    t = await make_tester(client, "kk-reopen-1")
    pz, ok = good_accusation()
    for _ in range(3):
        await client.post(url("easy", "accuse"), headers=t["headers"], json=ok | {"who": wrong_who(pz)})
    assert (await client.post(url("easy", "reopen"), headers=t["headers"])).status_code == 200
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["reopen"]
    again = await client.post(url("easy", "reopen"), headers=t["headers"])
    assert again.status_code == 409 and again.json()["detail"]["error"] == "not_failed"
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=ok)).json()
    assert j["ok"] and j["run"]["stars"] == 1 and j["run"]["paid"] == 0
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["reopen"]


async def test_clean_win_of_the_free_level_pays_five_coins_once_and_reveals_the_answer(client):
    await configure(client)
    t = await make_tester(client, "kk-win-1")
    pz, ok = good_accusation()
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=ok | {"secs": 95})).json()
    assert j["ok"] and j["run"]["stars"] == 3 and j["run"]["secs"] == 95 and j["run"]["paid"] == kikoja.REWARD
    assert j["reveal"]["thief"] == pz["answer"]["thief"] and j["reveal"]["paths"] == pz["answer"]["paths"]
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD
    again = await client.post(url("easy", "accuse"), headers=t["headers"], json=ok)
    assert again.status_code == 409 and again.json()["detail"]["error"] == "already_solved"
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD
    j = (await client.get(url("easy"), headers=t["headers"])).json()
    assert j["run"]["solved"] and j["reveal"]["thief"] == pz["answer"]["thief"]


async def test_two_simultaneous_correct_accusations_pay_once(client):
    await configure(client)
    t = await make_tester(client, "kk-race-1")
    _, ok = good_accusation()
    a, b = await asyncio.gather(client.post(url("easy", "accuse"), headers=t["headers"], json=ok),
                                client.post(url("easy", "accuse"), headers=t["headers"], json=ok))
    assert sorted([a.status_code, b.status_code]) == [200, 409]
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD


async def test_witness_is_required_when_the_contradiction_alone_does_not_clear_the_speaker(client, monkeypatch):
    await configure(client)
    t = await make_tester(client, "kk-wit-1")
    pz = next(p for p in kikoja.level_pool("easy") if any(w for w in p["answer"]["cons"].values()))
    monkeypatch.setattr(kikoja, "today_puzzle", lambda level="easy", back=0: pz)
    a = pz["answer"]
    con = next((c for c, w in a["cons"].items() if w), None)
    base = {"who": a["thief"], "lie": a["lie"], "con": con}
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=base | {"wit": []})).json()
    assert j["ok"] is False and j["step"] == "wit"
    bad = next(s["id"] for s in pz["S"] if [s["id"]] not in a["cons"][con] and s["id"] not in (a["lie"], con))
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=base | {"wit": [bad]})).json()
    assert j["ok"] is False and j["step"] == "wit" and j["run"]["mistakes"] == 2
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=base | {"wit": a["cons"][con][0]})).json()
    assert j["ok"] is True and j["run"]["stars"] == 1 and j["run"]["paid"] == 0       # two mistakes: one star, no reward


async def test_hint_is_paid_once_and_costs_a_star(client):
    await configure(client)
    t = await make_tester(client, "kk-hint-1")
    r = await client.post(url("easy", "hint"), headers=t["headers"], json={"kind": "time"})
    assert r.status_code == 200 and r.json()["hint_data"]["time"] == kikoja.today_puzzle("easy")["answer"]["hints"]["time"]
    again = await client.post(url("easy", "hint"), headers=t["headers"], json={"kind": "time"})
    assert again.status_code == 200
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["time"]
    two = await asyncio.gather(*[client.post(url("easy", "hint"), headers=t["headers"], json={"kind": "pair"}) for _ in range(2)])
    assert [x.status_code for x in two] == [200, 200]
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["time"] - kikoja.PRICES["pair"]
    _, ok = good_accusation()
    j = (await client.post(url("easy", "accuse"), headers=t["headers"], json=ok)).json()
    assert j["ok"] and j["run"]["stars"] == 2 and j["run"]["paid"] == 0


async def test_hint_needs_coins(client):
    await configure(client)
    t = await make_tester(client, "kk-poor-1", coins=10)
    r = await client.post(url("easy", "hint"), headers=t["headers"], json={"kind": "pair"})
    assert r.status_code == 402 and await balance(t["player_id"]) == 10


async def test_bad_input_is_refused(client):
    await configure(client)
    t = await make_tester(client, "kk-bad-1")
    for body in ({"who": 99, "lie": "s0", "con": "s1"}, {"who": 0, "lie": "x" * 40, "con": "s1"},
                 {"who": 0, "lie": "s0", "con": "s1", "wit": ["a", "b", "c"]}, {"who": -1, "lie": "s0", "con": "s1"}):
        assert (await client.post(url("easy", "accuse"), headers=t["headers"], json=body)).status_code == 422


async def test_admin_numbers_count_levels_and_unlocks(client):
    await configure(client)
    before = (await client.get("/admin/api/kikoja", headers=ADMIN)).json()["stats"]["coins_unlock"]   # the coin ledger keeps other tests' unlocks
    t = await make_tester(client, "kk-adm-1")
    await client.post(url("medium", "unlock"), headers=t["headers"])
    _, ok = good_accusation()
    await client.post(url("easy", "accuse"), headers=t["headers"], json=ok)
    j = (await client.get("/admin/api/kikoja", headers=ADMIN)).json()
    st = j["stats"]
    assert st["by_level"]["easy"]["solved"] == 1 and st["by_level"]["medium"]["unlocked"] == 1 and st["coins_unlock"] - before == 30
    assert st["by_level"]["hard"]["puzzles"] == 10 and st["by_level"]["hard"]["today"].startswith("h")


# ---- the archive (Amin, 25 Nov 2026): the last 7 days, same rules, no coins back for the free level -----------------------------------
def test_the_archive_never_reaches_today_and_its_days_are_all_different():
    for lv in kikoja.LEVELS:
        ids = [kikoja.today_puzzle(lv, b)["id"] for b in range(0, kikoja.ARCHIVE_DAYS + 1)]
        assert len(set(ids)) == kikoja.ARCHIVE_DAYS + 1, (lv, ids)   # room for more days later: the pool must stay bigger than the archive


async def test_archive_lists_seven_days_of_three_tiles_without_statements(client):
    await configure(client)
    t = await make_tester(client, "kk-arc-1")
    j = (await client.get("/v1/kikoja/archive", headers=t["headers"])).json()
    assert j["visible"] and j["total"] == 21 and j["solved"] == 0 and [d["back"] for d in j["days"]] == list(range(1, 8))
    assert all([x["level"] for x in d["levels"]] == ["easy", "medium", "hard"] for d in j["days"])
    assert [(x["price"], x["open"]) for x in j["days"][0]["levels"]] == [(0, True), (30, False), (50, False)]
    assert "puzzle" not in str(j) and "answer" not in str(j) and "paths" not in str(j)
    plain = await new_player(client, "kk-arc-2", aged=True)
    assert (await client.get("/v1/kikoja/archive", headers=plain["headers"])).json() == {"visible": False}
    assert (await client.get("/v1/kikoja/easy?back=8", headers=t["headers"])).status_code == 422


async def test_an_old_free_puzzle_is_played_for_plaques_and_pays_no_coins(client):
    await configure(client)
    t = await make_tester(client, "kk-arc-3")
    pz = kikoja.today_puzzle("easy", 2)
    e = (await client.get(url("easy") + "?back=2", headers=t["headers"])).json()
    assert e["id"] == pz["id"] and pz["id"] != kikoja.today_puzzle("easy")["id"]
    a = pz["answer"]
    con, wits = next(iter(a["cons"].items()))
    before = (await client.get("/v1/kikoja", headers=t["headers"])).json()["coins"]
    r = (await client.post(url("easy", "accuse") + "?back=2", headers=t["headers"], json={"who": a["thief"], "lie": a["lie"], "con": con, "wit": wits[0] if wits else []})).json()
    assert r["ok"] and r["run"]["stars"] == 3 and r["run"]["paid"] == 0 and r["coins"] == before
    j = (await client.get("/v1/kikoja/archive", headers=t["headers"])).json()
    assert j["solved"] == 1 and [x for x in j["days"][1]["levels"] if x["level"] == "easy"][0]["solved"] is True


async def test_an_old_paid_puzzle_opens_with_the_same_coins_once(client):
    await configure(client)
    t = await make_tester(client, "kk-arc-4", coins=100)
    u = url("hard", "unlock") + "?back=3"
    assert (await client.get(url("hard") + "?back=3", headers=t["headers"])).json().get("puzzle") is None
    a = (await client.post(u, headers=t["headers"])).json()
    b = (await client.post(u, headers=t["headers"])).json()
    assert a["open"] and a["coins"] == 50 and b["coins"] == 50 and b["puzzle"]["S"]
