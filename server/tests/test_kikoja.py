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


def good_accusation():
    """A complete accusation for today's puzzle (the first accepted contradiction, the first witness set)."""
    pz = kikoja.today_puzzle()
    a = pz["answer"]
    con, wits = next(iter(a["cons"].items()))
    return pz, {"who": a["thief"], "lie": a["lie"], "con": con, "wit": wits[0] if wits else []}


def wrong_who(pz):
    return (pz["answer"]["thief"] + 1) % pz["n"]


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
    assert len(pool) >= 40
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
    for pz in kikoja.pool()[:20]:
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


# ---- the game through the API --------------------------------------------------------------------------------------------------
async def test_hidden_from_players_who_are_not_testers_and_off_by_default(client):
    plain = await new_player(client, "kk-plain-1", aged=True)
    t = await make_tester(client, "kk-off-1")
    assert (await client.get("/v1/kikoja", headers=t["headers"])).json() == {"visible": False}   # off, even for testers
    await configure(client)
    assert (await client.get("/v1/kikoja", headers=plain["headers"])).json() == {"visible": False}
    for path in ("hint", "accuse", "reopen"):
        r = await client.post(f"/v1/kikoja/{path}", headers=plain["headers"], json={"kind": "time", "who": 0, "lie": "s0", "con": "s1"})
        assert r.status_code == 404, path


async def test_a_tester_sees_the_puzzle_without_the_answer(client):
    await configure(client)
    t = await make_tester(client, "kk-view-1")
    j = (await client.get("/v1/kikoja", headers=t["headers"])).json()
    assert j["visible"] and j["puzzle"]["S"] and "answer" not in j["puzzle"] and "reveal" not in j
    assert "paths" not in str(j) and j["run"] == {"mistakes": 0, "hints": [], "reopened": False, "solved": False,
                                                    "failed": False, "stars": 0, "secs": 0, "paid": 0}
    await configure(client, "all")
    plain = await new_player(client, "kk-all-1", aged=True)
    assert (await client.get("/v1/kikoja", headers=plain["headers"])).json()["visible"] is True


async def test_wrong_accusations_say_the_step_and_three_fail_the_file(client):
    await configure(client)
    t = await make_tester(client, "kk-fail-1")
    pz, ok = good_accusation()
    r = await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok | {"who": wrong_who(pz)})
    j = r.json()
    assert r.status_code == 200 and j["ok"] is False and j["step"] == "who" and j["run"]["mistakes"] == 1
    r = await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok | {"lie": next(s["id"] for s in pz["S"] if s["id"] != ok["lie"])})
    assert r.json()["step"] == "lie" and r.json()["run"]["mistakes"] == 2
    r = await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok | {"con": "zz"})
    j = r.json()
    assert j["step"] == "con" and j["run"]["failed"] is True and "reveal" not in j and "paths" not in str(j)
    r = await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok)
    assert r.status_code == 409 and r.json()["detail"]["error"] == "failed"


async def test_reopen_costs_once_and_the_win_is_worth_one_star_and_no_reward(client):
    await configure(client)
    t = await make_tester(client, "kk-reopen-1")
    pz, ok = good_accusation()
    for _ in range(3):
        await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok | {"who": wrong_who(pz)})
    assert (await client.post("/v1/kikoja/reopen", headers=t["headers"])).status_code == 200
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["reopen"]
    again = await client.post("/v1/kikoja/reopen", headers=t["headers"])
    assert again.status_code == 409 and again.json()["detail"]["error"] == "not_failed"
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok)).json()
    assert j["ok"] and j["run"]["stars"] == 1 and j["run"]["paid"] == 0
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["reopen"]


async def test_clean_win_pays_five_coins_once_and_reveals_the_answer(client):
    await configure(client)
    t = await make_tester(client, "kk-win-1")
    pz, ok = good_accusation()
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok | {"secs": 95})).json()
    assert j["ok"] and j["run"]["stars"] == 3 and j["run"]["secs"] == 95 and j["run"]["paid"] == kikoja.REWARD
    assert j["reveal"]["thief"] == pz["answer"]["thief"] and j["reveal"]["paths"] == pz["answer"]["paths"]
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD
    again = await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok)
    assert again.status_code == 409 and again.json()["detail"]["error"] == "already_solved"
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD
    j = (await client.get("/v1/kikoja", headers=t["headers"])).json()
    assert j["run"]["solved"] and j["reveal"]["thief"] == pz["answer"]["thief"]


async def test_two_simultaneous_correct_accusations_pay_once(client):
    await configure(client)
    t = await make_tester(client, "kk-race-1")
    _, ok = good_accusation()
    a, b = await asyncio.gather(client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok),
                                client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok))
    assert sorted([a.status_code, b.status_code]) == [200, 409]
    assert await balance(t["player_id"]) == 500 + kikoja.REWARD


async def test_witness_is_required_when_the_contradiction_alone_does_not_clear_the_speaker(client, monkeypatch):
    await configure(client)
    t = await make_tester(client, "kk-wit-1")
    pz = next(p for p in kikoja.pool() if any(w for w in p["answer"]["cons"].values()))
    monkeypatch.setattr(kikoja, "today_puzzle", lambda: pz)
    a = pz["answer"]
    con = next((c for c, w in a["cons"].items() if w), None)
    base = {"who": a["thief"], "lie": a["lie"], "con": con}
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=base | {"wit": []})).json()
    assert j["ok"] is False and j["step"] == "wit"
    bad = next(s["id"] for s in pz["S"] if [s["id"]] not in a["cons"][con] and s["id"] not in (a["lie"], con))
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=base | {"wit": [bad]})).json()
    assert j["ok"] is False and j["step"] == "wit" and j["run"]["mistakes"] == 2
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=base | {"wit": a["cons"][con][0]})).json()
    assert j["ok"] is True and j["run"]["stars"] == 1 and j["run"]["paid"] == 0       # two mistakes: one star, no reward


async def test_hint_is_paid_once_and_costs_a_star(client):
    await configure(client)
    t = await make_tester(client, "kk-hint-1")
    r = await client.post("/v1/kikoja/hint", headers=t["headers"], json={"kind": "time"})
    assert r.status_code == 200 and r.json()["hint_data"]["time"] == kikoja.today_puzzle()["answer"]["hints"]["time"]
    again = await client.post("/v1/kikoja/hint", headers=t["headers"], json={"kind": "time"})
    assert again.status_code == 200
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["time"]
    two = await asyncio.gather(*[client.post("/v1/kikoja/hint", headers=t["headers"], json={"kind": "pair"}) for _ in range(2)])
    assert [x.status_code for x in two] == [200, 200]
    assert await balance(t["player_id"]) == 500 - kikoja.PRICES["time"] - kikoja.PRICES["pair"]
    _, ok = good_accusation()
    j = (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=ok)).json()
    assert j["ok"] and j["run"]["stars"] == 2 and j["run"]["paid"] == 0


async def test_hint_needs_coins(client):
    await configure(client)
    t = await make_tester(client, "kk-poor-1", coins=10)
    r = await client.post("/v1/kikoja/hint", headers=t["headers"], json={"kind": "pair"})
    assert r.status_code == 402 and await balance(t["player_id"]) == 10


async def test_bad_input_is_refused(client):
    await configure(client)
    t = await make_tester(client, "kk-bad-1")
    for body in ({"who": 99, "lie": "s0", "con": "s1"}, {"who": 0, "lie": "x" * 40, "con": "s1"},
                 {"who": 0, "lie": "s0", "con": "s1", "wit": ["a", "b", "c"]}, {"who": -1, "lie": "s0", "con": "s1"}):
        assert (await client.post("/v1/kikoja/accuse", headers=t["headers"], json=body)).status_code == 422
