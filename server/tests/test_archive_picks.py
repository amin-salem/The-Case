"""«پیشنهاد برای تو» (GET /v1/cases/picks) and the weekend-tab line of the admin economy report.

The choice is tested as a pure function and against a private database (SQLite, and PostgreSQL in CI), the route with the
shared numbers replaced, so rows never leak into the other tests' solver counts."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app import content, picks
from app.models import CaseProgress, Event, Player
from app.picks import CaseStat, choose
from app.services import economy_report as er

from .conftest import ADMIN, new_player, private_engine

NOW = datetime(2026, 11, 10, 12, 0)


def case(i, cat="", diff=3):
    return {"id": f"x{i:03d}", "number": i, "category": cat, "difficulty": diff}


def stat(players=30, solved=20, recent=0):
    return CaseStat(players, solved, recent)


# ------------------------------------------------------------------ the pure choice

def test_each_reason_needs_its_minimum_sample():
    cs = [case(1, diff=1), case(2, diff=2), case(3, cat="crime")]
    st = {"x001": stat(19, 19),            # one detective short: no «آسان» from it
          "x002": stat(25, 10),            # 40 % solved: not easy
          "x003": stat(19, 5, 19)}         # 19 recent solves: not popular
    assert choose(cs, {"crime": 5}, st, {"x003": (4.8, 19, 3)}) == []


def test_easy_popular_taste_distinct_cases_and_real_numbers():
    cs = [case(1, diff=1), case(2, cat="crime"), case(3, cat="crime", diff=4), case(4, cat="art")]
    st = {"x001": stat(40, 36), "x002": stat(30, 10, 5), "x003": stat(50, 20, 30), "x004": stat(30, 15)}
    got = choose(cs, {"crime": 2, "art": 1}, st, {"x002": (4.6, 25, 4)})
    assert [g["reason"] for g in got] == ["easy", "popular", "taste"]
    assert got[0] == {"case_id": "x001", "reason": "easy", "solve_rate": 90, "players": 40}
    assert got[1]["case_id"] == "x002" and got[1]["rating_avg"] == 4.6 and got[1]["rating_count"] == 25   # rating beats solves
    assert got[2]["case_id"] == "x003" and got[2]["category"] == "crime" and got[2]["category_solved"] == 2
    assert len({g["case_id"] for g in got}) == 3


def test_popular_falls_back_to_recent_solves_and_a_case_is_never_used_twice():
    cs = [case(1, diff=1), case(2)]
    st = {"x001": stat(40, 36, 50), "x002": stat(30, 10, 25)}
    got = choose(cs, {}, st, {})
    assert [(g["reason"], g["case_id"]) for g in got] == [("easy", "x001"), ("popular", "x002")]
    assert got[1]["solved_30d"] == 25
    assert choose([case(1, diff=1)], {}, {"x001": stat(40, 36, 50)}, {}) == [
        {"case_id": "x001", "reason": "easy", "solve_rate": 90, "players": 40}]


def test_taste_needs_two_solved_cases_of_the_topic():
    cs = [case(1, cat="crime")]
    st = {"x001": stat()}
    assert choose(cs, {"crime": 1}, st, {}) == []
    assert choose(cs, {"": 9}, st, {}) == []        # a case without a topic never makes a taste
    assert choose(cs, {"crime": 2}, st, {})[0]["reason"] == "taste"


def test_no_data_means_no_picks_and_at_most_three():
    assert choose([case(i) for i in range(5)], {}, {}, {}) == []
    cs = [case(i, cat="a", diff=1) for i in range(1, 9)]
    st = {c["id"]: stat(40, 36, 40) for c in cs}
    assert len(choose(cs, {"a": 3}, st, {c["id"]: (4.5, 30, 1) for c in cs})) == 3


# ------------------------------------------------------------------ against a database

@pytest.fixture
async def session(tmp_path):
    engine = await private_engine(tmp_path, "picks")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        picks.clear()
        yield s
        picks.clear()
    await engine.dispose()


def add_player(s, n):
    s.add(Player(id=f"p{n}", secret_hash="x", device_id=f"dev-{n}", invite_code=f"CODE{n}", nickname=f"nick{n}",
                 created_at=NOW - timedelta(days=30), last_seen=NOW))


async def test_stats_count_real_players_and_solves(session):
    for n in range(1, 25):
        add_player(session, n)
    await session.flush()
    for n in range(1, 25):   # 24 detectives played c1; 18 solved it, 6 lost it; 4 of the solves are older than 30 days
        solved = n <= 18
        session.add(CaseProgress(player_id=f"p{n}", case_id="c1", unlocked=True, solved=solved, failed=not solved,
                                 finished_at=NOW - timedelta(days=40 if n <= 4 else 2)))
    session.add(CaseProgress(player_id="p1", case_id="c2", unlocked=False))     # only viewed: not "played"
    await session.commit()
    st = await picks.case_stats(session, now=NOW)
    assert st["c1"] == CaseStat(players=24, solved=18, recent=14)
    assert st["c2"].players == 0


async def test_a_solved_or_lost_case_is_never_picked_and_a_new_solve_shows_at_once(session):
    for n in range(1, 31):
        add_player(session, n)
    await session.flush()
    for n in range(2, 31):
        session.add(CaseProgress(player_id=f"p{n}", case_id="x001", unlocked=True, solved=True, finished_at=NOW))
    await session.commit()
    cands = [case(1, diff=1), case(2, diff=1)]
    cats = {"x001": "", "x002": ""}
    assert [x["case_id"] for x in await picks.picks_for(session, "p1", cands, cats, {})] == ["x001"]
    session.add(CaseProgress(player_id="p1", case_id="x001", unlocked=True, failed=True))
    await session.commit()
    assert await picks.picks_for(session, "p1", cands, cats, {}) == []      # x002 has no data; x001 was lost


async def test_taste_comes_from_this_players_solves(session):
    for n in range(1, 26):
        add_player(session, n)
    await session.flush()
    for n in range(2, 26):
        session.add(CaseProgress(player_id=f"p{n}", case_id="x010", unlocked=True, solved=n % 2 == 0, finished_at=NOW))
    for cid in ("x001", "x002"):
        session.add(CaseProgress(player_id="p1", case_id=cid, unlocked=True, solved=True, finished_at=NOW))
    await session.commit()
    cands = [case(1, "crime"), case(2, "crime"), case(10, "crime", diff=4)]
    cats = {"x001": "crime", "x002": "crime", "x010": "crime"}
    got = await picks.picks_for(session, "p1", cands, cats, {})
    assert got == [{"case_id": "x010", "reason": "taste", "category": "crime", "category_solved": 2}]


# ------------------------------------------------------------------ the route

async def test_route_answers_an_empty_list_for_a_new_player_and_needs_login(client):
    me = await new_player(client, "picks-dev-1")
    r = await client.get("/v1/cases/picks", headers=me["headers"])
    assert r.status_code == 200 and r.json() == {"picks": []}
    assert (await client.get("/v1/cases/picks")).status_code in (401, 403)


async def test_route_returns_the_pick_with_this_players_price(client, monkeypatch):
    me = await new_player(client, "picks-dev-2", aged=True)
    today = content.todays_case()
    easy = next(c for c in content.opened() if c.data["difficulty"] <= 2 and (today is None or c.id != today.id))

    async def fake(session, now=None):
        return {easy.id: CaseStat(players=40, solved=32, recent=3)}
    monkeypatch.setattr(picks, "case_stats", fake)
    r = await client.get("/v1/cases/picks", headers=me["headers"])
    assert r.status_code == 200
    pick = next(p for p in r.json()["picks"] if p["case_id"] == easy.id)
    assert pick["reason"] == "easy" and pick["solve_rate"] == 80 and pick["players"] == 40
    rows = (await client.get("/v1/cases", headers=me["headers"])).json()["archive"]
    assert pick["unlock_cost"] == next(x for x in rows if x["id"] == easy.id)["unlock_cost"]   # the normal price, offers included


async def test_route_fails_open_with_the_stable_shape(client, monkeypatch):
    me = await new_player(client, "picks-dev-3")

    async def boom(*a, **k):
        raise RuntimeError("database down")
    monkeypatch.setattr(picks, "picks_for", boom)
    r = await client.get("/v1/cases/picks", headers=me["headers"])
    assert r.status_code == 200 and r.json() == {"picks": []}


# ------------------------------------------------------------------ the weekend tab line in the admin report

async def test_weekend_tab_opens_split_thu_sat_and_other_days(session):
    for n in (1, 2):
        add_player(session, n)
    session.add(Player(id="p3", secret_hash="x", device_id="smoke-3", invite_code="CODE3", nickname="n3",
                       created_at=NOW - timedelta(days=30), last_seen=NOW))
    await session.flush()
    # 2026-11-10 is a Tuesday; 2026-11-05 a Thursday, 2026-11-07 a Saturday (Tehran days; 12:00 UTC is 15:30 there)
    for day, pid in (("2026-11-10", "p1"), ("2026-11-10", "p1"), ("2026-11-05", "p1"), ("2026-11-05", "p2"),
                     ("2026-11-07", "p2"), ("2026-11-09", "p3")):
        session.add(Event(player_id=pid, name="weekend_tab_open", props={}, ts=datetime.fromisoformat(day + "T12:00:00")))
    session.add(Event(player_id="p1", name="weekend_tab_open", props={}, ts=NOW - timedelta(days=30)))   # outside the window
    session.add(Event(player_id="p1", name="other_event", props={}, ts=NOW))
    await session.commit()
    w = (await er.build(session, 14, now=NOW))["weekend_tab"]
    assert w["opens"] == 5 and w["players"] == 2
    assert w["thu_sat"] == {"days": 2, "opens": 3, "per_day": 1.5}
    assert w["other"] == {"days": 1, "opens": 2, "per_day": 2.0}
    assert [d["day"] for d in w["days"]] == ["2026-11-05", "2026-11-07", "2026-11-10"]
    assert "p1" not in str(w)


async def test_weekend_tab_is_empty_not_broken_and_the_admin_api_carries_it(session, client):
    w = (await er.build(session, 14, now=NOW))["weekend_tab"]
    assert w["opens"] == 0 and w["days"] == [] and w["thu_sat"]["per_day"] is None
    r = await client.get("/admin/api/economy?days=7", headers=ADMIN)
    assert r.status_code == 200 and "weekend_tab" in r.json()
