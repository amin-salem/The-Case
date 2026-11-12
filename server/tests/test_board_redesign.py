"""The redesigned boards (UX pack, session 6): rank gaps, paging, tonight's solver stats, the streak board and the player sheet.
Abuse and failure paths first: hidden accounts, bad limits, unknown ids. Runs on SQLite and PostgreSQL (CI job server-postgres).
Boards share one database with other tests, so these tests use very large numbers / their own fake case ids and compare
places relative to their own players."""
from datetime import timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import update

from app import content, db
from app.routers import leaderboard as lb
from app.models import CaseProgress, Player, utcnow

from .conftest import new_player
from .test_fair_week import T, _points_order, clock, leagues, set_player, single_board, solve, week_of_fake_cases, wid  # noqa: F401
from .test_streak_longterm import _set, evening_of, ids_from
from .test_night_streak import pub


@pytest.fixture(autouse=True)
def _hide_new_accounts(monkeypatch):
    """The 48-hour rule is what makes a fresh guest «hidden»; the default switch shows new accounts."""
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "show_new_accounts_on_boards", False)


@pytest.fixture(autouse=True)
async def _undo_big_numbers():
    """These tests use huge plaque and streak numbers to stay on top of the shared database; other tests (the tester board)
    count on small ones, so everything above the marker is put back after each test."""
    yield
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where((Player.stars_total >= 90000) | (Player.streak >= 7000))
                        .values(stars_total=0, streak=0, best_streak=0, cases_solved=0))
        await s.commit()


async def get(client, p, url):
    return await client.get(url, headers=p["headers"])


# ------------------------------------------------------------------ all time
async def test_all_time_gap_paging_and_hidden_accounts(client):
    a, b, c = [await new_player(client, f"bd-all-{i}", aged=True) for i in range(3)]
    ghost = await new_player(client, "bd-all-ghost")      # a new unsecured guest: hidden from the boards for 48 h
    await set_player(a["player_id"], stars_total=90010, cases_solved=5)
    await set_player(b["player_id"], stars_total=90005, cases_solved=3)
    await set_player(c["player_id"], stars_total=90005, cases_solved=2)
    await set_player(ghost["player_id"], stars_total=95000, cases_solved=9)
    r = (await get(client, c, "/v1/leaderboard?period=all&limit=100")).json()
    assert r["me"]["me"] is True and r["me"]["pid"] == c["player_id"]
    above = r["me"]["rank"] - 1
    assert r["gap"]["next_rank"] == above and r["gap"]["unit"] == "plaque"
    assert r["gap"]["diff"] == 1                      # 90005 vs 90005: one more plaque passes the player above
    assert ghost["player_id"] not in {x["pid"] for x in r["top"]}
    top = (await get(client, a, "/v1/leaderboard?period=all&limit=100")).json()
    assert top["gap"] is None or top["gap"]["next_rank"] == top["me"]["rank"] - 1
    # paging: two pages never overlap and next_offset leads to the second
    p1 = (await get(client, a, "/v1/leaderboard?period=all&limit=2")).json()
    assert len(p1["top"]) == 2 and p1["next_offset"] == 2
    p2 = (await get(client, a, f"/v1/leaderboard?period=all&limit=2&offset={p1['next_offset']}")).json()
    assert {x["pid"] for x in p1["top"]}.isdisjoint({x["pid"] for x in p2["top"]})
    assert [x["rank"] for x in p2["top"]] == [3, 4][:len(p2["top"])]
    # my row is there even when I am far below the page
    far = (await get(client, c, "/v1/leaderboard?period=all&limit=1")).json()
    assert far["me"]["pid"] == c["player_id"] and far["gap"] is not None


async def test_the_ghost_has_no_place_and_no_gap(client):
    ghost = await new_player(client, "bd-ghost-2")
    await set_player(ghost["player_id"], stars_total=96000, cases_solved=9)
    r = (await get(client, ghost, "/v1/leaderboard?period=all")).json()
    assert r["me"] is None and r["gap"] is None


@pytest.mark.parametrize("url", ["/v1/leaderboard?period=all&limit=101", "/v1/leaderboard?period=all&limit=0",
                                 "/v1/leaderboard?period=all&offset=-1", "/v1/leaderboard?period=all&offset=1001",
                                 "/v1/leaderboard/streaks?limit=101", "/v1/leaderboard/streaks?offset=1001",
                                 "/v1/leaderboard?period=nope"])
async def test_limits_are_enforced(client, url):
    p = await new_player(client, "bd-limit", aged=True)
    assert (await get(client, p, url)).status_code == 422


async def test_boards_need_a_token(client):
    for url in ("/v1/leaderboard?period=all", "/v1/leaderboard/streaks", "/v1/players/abc/card"):
        assert (await client.get(url)).status_code == 401


# ------------------------------------------------------------------ daily
@pytest.fixture
def tonight(monkeypatch):
    fake = SimpleNamespace(id=f"zbd-{uuid4().hex[:10]}", data={"title": "پرونده‌ی آزمون"})   # its own id: no other test's rows
    monkeypatch.setattr(lb, "_tonight", lambda: fake)
    return fake


async def put_solve(pid, case_id, stars, seconds, ranked=True, daily=True):
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=case_id, solved=True, stars=stars, seconds=seconds, ranked=ranked,
                           was_daily=daily, finished_at=utcnow()))
        await s.commit()


async def test_daily_stats_gap_and_unranked_rushes(client, tonight):
    ps = [await new_player(client, f"bd-day-{i}", aged=True) for i in range(5)]
    await put_solve(ps[0]["player_id"], tonight.id, 3, 300)
    await put_solve(ps[1]["player_id"], tonight.id, 3, 500)
    await put_solve(ps[2]["player_id"], tonight.id, 2, 400)
    await put_solve(ps[3]["player_id"], tonight.id, 1, 5, ranked=False)       # a rush: counts as solved, never as the record
    await put_solve(ps[4]["player_id"], tonight.id, 3, 700, daily=False)      # solved later (archive): not tonight's
    r = (await get(client, ps[2], "/v1/leaderboard?period=daily")).json()
    assert r["daily"] == {"solved": 4, "fastest": 300, "median": 400}
    assert [x["pid"] for x in r["top"]] == [ps[0]["player_id"], ps[1]["player_id"], ps[2]["player_id"]]
    assert r["me"]["rank"] == 3
    assert r["gap"] == {"next_rank": 2, "diff": 2, "unit": "plaque"}          # one plaque more ties, two pass the three-plaque player
    r2 = (await get(client, ps[1], "/v1/leaderboard?period=daily")).json()
    assert r2["gap"] == {"next_rank": 1, "diff": 201, "unit": "seconds"}      # 200 s faster, +1 to pass
    first = (await get(client, ps[0], "/v1/leaderboard?period=daily")).json()
    assert first["gap"] is None
    # paging, and my row when I am below the page
    p1 = (await get(client, ps[2], "/v1/leaderboard?period=daily&limit=1")).json()
    assert len(p1["top"]) == 1 and p1["next_offset"] == 1 and p1["me"]["rank"] == 3 and p1["gap"]["next_rank"] == 2
    # the unranked rush has no place, no gap
    rush = (await get(client, ps[3], "/v1/leaderboard?period=daily")).json()
    assert rush["me"] is None and rush["gap"] is None


async def test_daily_board_with_nobody_has_zero_stats_not_an_error(client, tonight):
    p = await new_player(client, "bd-day-empty", aged=True)
    r = (await get(client, p, "/v1/leaderboard?period=daily")).json()
    assert r["top"] == [] and r["me"] is None and r["daily"] == {"solved": 0, "fastest": None, "median": None}


async def test_daily_without_a_case_is_a_stable_404(client, monkeypatch):
    monkeypatch.setattr(lb, "_tonight", lambda: None)
    p = await new_player(client, "bd-day-none", aged=True)
    r = await get(client, p, "/v1/leaderboard?period=daily")
    assert r.status_code == 404 and r.json()["detail"] == "no_case"


async def test_a_banned_player_is_not_on_the_daily_stats(client, tonight):
    a, b = await new_player(client, "bd-ban-a", aged=True), await new_player(client, "bd-ban-b", aged=True)
    await put_solve(a["player_id"], tonight.id, 3, 100)
    await put_solve(b["player_id"], tonight.id, 3, 50)
    await set_player(b["player_id"], banned=True)
    r = (await get(client, a, "/v1/leaderboard?period=daily")).json()
    assert r["daily"]["solved"] == 1 and r["daily"]["fastest"] == 100


# ------------------------------------------------------------------ weekly
async def test_weekly_gap_inside_and_far_below_the_page(client, clock, single_board, week_of_fake_cases):
    from app import gameclock
    now = T(2029, 3, 14, 12)                    # a week no other test uses (fake case ids are per week)
    clock(now)
    ws = gameclock.week_of(now)
    a, b, c = [await new_player(client, f"bd-wk-{i}", aged=True) for i in range(3)]
    await solve(a["player_id"], wid(ws, 0), 3, gameclock.week_end(ws) - timedelta(days=2))
    await solve(b["player_id"], wid(ws, 0), 2, gameclock.week_end(ws) - timedelta(days=2))
    await solve(c["player_id"], wid(ws, 0), 1, gameclock.week_end(ws) - timedelta(days=2))
    r = (await get(client, c, "/v1/leaderboard?period=weekly")).json()
    assert r["me"]["rank"] == 3 and r["gap"] == {"next_rank": 2, "diff": 2, "unit": "plaque"}
    far = (await get(client, c, "/v1/leaderboard?period=weekly&limit=1")).json()      # I am not in the first page
    assert far["me"]["rank"] == 3 and far["gap"] == {"next_rank": 2, "diff": 2, "unit": "plaque"}
    assert far["next_offset"] == 1
    p2 = (await get(client, c, "/v1/leaderboard?period=weekly&limit=1&offset=1")).json()
    assert p2["top"][0]["rank"] == 2 and p2["top"][0]["pid"] == b["player_id"]
    leader = (await get(client, a, "/v1/leaderboard?period=weekly")).json()
    assert leader["gap"] is None and leader["me"]["rank"] == 1
    late = (await get(client, a, "/v1/leaderboard?period=weekly&offset=500")).json()   # beyond the cached window: empty, calm
    assert late["top"] == [] and late["next_offset"] is None


# ------------------------------------------------------------------ streaks
async def streaker(client, clock, name, *, streak, last_offset, freezes=0, aged=True):
    p = await new_player(client, name, aged=aged)
    ids, i = ids_from()
    clock(evening_of(ids[i]))
    await _set(p["player_id"], streak=streak, best_streak=streak + 3, streak_freezes=freezes,
               last_daily_solved=pub(ids, i + last_offset))
    return p


async def test_streak_board_hides_dead_streaks_and_shows_the_gap(client, clock):
    live_hi = await streaker(client, clock, "bd-st-hi", streak=8000, last_offset=0)
    live_lo = await streaker(client, clock, "bd-st-lo", streak=7000, last_offset=-1)       # tonight's case still open: alive
    dead = await streaker(client, clock, "bd-st-dead", streak=9000, last_offset=-5)        # missed nights, no insurance: dead
    ghost = await streaker(client, clock, "bd-st-ghost", streak=9500, last_offset=0, aged=False)
    r = (await get(client, live_lo, "/v1/leaderboard/streaks?limit=100")).json()
    pids = [x["pid"] for x in r["top"]]
    assert dead["player_id"] not in pids and ghost["player_id"] not in pids
    assert pids.index(live_hi["player_id"]) < pids.index(live_lo["player_id"])
    assert all(x["value"] == x["streak"] and x["value"] > 0 for x in r["top"])
    assert r["me"]["me"] is True and r["me"]["value"] == 7000 and r["my_best"] == 7003
    assert r["gap"]["unit"] == "nights" and r["gap"]["diff"] == 1001 and r["gap"]["next_rank"] == r["me"]["rank"] - 1
    # a dead streak owner has no place and no gap, but still sees his record
    d = (await get(client, dead, "/v1/leaderboard/streaks")).json()
    assert d["me"] is None and d["gap"] is None and d["my_best"] == 9003
    # paging stays inside the list
    p1 = (await get(client, live_hi, "/v1/leaderboard/streaks?limit=1")).json()
    assert len(p1["top"]) == 1 and p1["next_offset"] == 1


async def test_streak_board_is_calm_when_nobody_has_a_streak(client, clock, monkeypatch):
    async def none(session, live):
        return []
    monkeypatch.setattr(lb, "_streak_ranking", none)
    p = await new_player(client, "bd-st-none", aged=True)
    r = (await get(client, p, "/v1/leaderboard/streaks")).json()
    assert r["top"] == [] and r["me"] is None and r["next_offset"] is None


# ------------------------------------------------------------------ player sheet
async def test_player_card_numbers_and_privacy(client, clock):
    a, b = await new_player(client, "bd-card-a", aged=True), await new_player(client, "bd-card-b", aged=True)
    ghost = await new_player(client, "bd-card-ghost")
    ids, i = ids_from()
    clock(evening_of(ids[i]))
    await set_player(b["player_id"], cases_solved=41, stars_total=99, streak=6, best_streak=19, last_daily_solved=pub(ids, i))
    r = await get(client, a, f"/v1/players/{b['player_id']}/card")
    assert r.status_code == 200
    j = r.json()
    assert j["pid"] == b["player_id"] and j["cases_solved"] == 41 and j["stars_total"] == 99
    assert j["streak"] == 6 and j["best_streak"] == 19 and j["rank_title"] and j["league_history"] == []
    assert "device_id" not in j and "email" not in j and "coins" not in j and "invite_code" not in j
    assert (await get(client, a, f"/v1/players/{a['player_id']}/card")).status_code == 200      # my own sheet
    assert (await get(client, a, f"/v1/players/{ghost['player_id']}/card")).status_code == 404  # hidden = missing
    assert (await get(client, a, "/v1/players/nope/card")).json()["detail"] == "no_player"
    assert (await get(client, a, "/v1/players/" + "x" * 80 + "/card")).status_code == 404
    await set_player(b["player_id"], banned=True)
    assert (await get(client, a, f"/v1/players/{b['player_id']}/card")).status_code == 404


async def test_player_card_id_card_fields(client, clock):
    """The detective ID card: league from the rank, number by signup order, fastest solve, newest three badges."""
    from app import economy, weekboard
    from app.models import PlayerAchievement
    from .test_fair_week import solve
    a, b = await new_player(client, "bd-idc-a", aged=True), await new_player(client, "bd-idc-b", aged=True)
    ids, i = ids_from()
    clock(evening_of(ids[i]))
    xp_inspector = next(n for n, t in economy.RANKS if t == "بازرس")                    # first rank of league 2
    await set_player(b["player_id"], xp=xp_inspector, last_daily_solved=pub(ids, i))
    await solve(b["player_id"], ids[i], 3, evening_of(ids[i]), seconds=95)
    await solve(b["player_id"], ids[i - 1], 2, evening_of(ids[i]), seconds=61)
    await solve(b["player_id"], ids[i - 2], 1, evening_of(ids[i]), seconds=3)        # below the floor: never a record
    await solve(b["player_id"], "quick-old-1", 1, evening_of(ids[i]), seconds=14)   # a retired quick puzzle: not a main case, never a record
    async with db.SessionLocal() as s:
        for n, aid in enumerate(["first_case", "cases_5", "cases_10", "cases_25"]):          # the 4th is the newest
            s.add(PlayerAchievement(player_id=b["player_id"], achievement_id=aid, at=utcnow() - timedelta(days=9 - n)))
        await s.commit()
    j = (await get(client, a, f"/v1/players/{b['player_id']}/card")).json()
    assert j["league"] == 2 and j["league_name"] == weekboard.LEAGUES[2] == "بازرس"
    assert j["fastest"] == 61
    assert j["since"] > 0 and j["member_no"] >= 2
    me = (await get(client, a, f"/v1/players/{a['player_id']}/card")).json()
    assert 1 <= me["member_no"] < j["member_no"]                                        # a registered before b
    assert me["league"] == 0 and me["fastest"] == 0 and me["recent"] == []
    assert [x["title"] for x in j["recent"]] == ["پرونده‌خوار", "کارآگاه پرکار", "کارآموز"]      # newest three, newest first
    assert [x["metal"] for x in j["recent"]] == [1, 1, 0]                                         # tiers 4 and 3 of 8 are silver, tier 2 bronze
    assert all(set(x) == {"title", "group", "metal", "at"} and x["metal"] in (0, 1, 2) for x in j["recent"])
    ats = [x["at"] for x in j["recent"]]
    assert ats == sorted(ats, reverse=True)                                              # newest first
    assert "invite_code" not in j and "email" not in j


async def test_player_card_league_history_is_bounded_and_newest_first(client, clock, leagues):
    from app import gameclock
    from app.models import WeekLeague
    clock(T(2027, 2, 10, 12))
    ws = gameclock.week_of(content.now_local())
    from datetime import timedelta
    a, b = await new_player(client, "bd-lh-a", aged=True), await new_player(client, "bd-lh-b", aged=True)
    async with db.SessionLocal() as s:
        for k in (0, 1, 3, 9):                                  # week 9 is older than the 6 weeks the sheet shows
            s.add(WeekLeague(week=(ws - timedelta(days=7 * k)).isoformat(), player_id=b["player_id"], league=min(k, 3)))
        await s.commit()
    j = (await get(client, a, f"/v1/players/{b['player_id']}/card")).json()
    assert [w["week"] for w in j["league_history"]] == [(ws - timedelta(days=7 * k)).isoformat() for k in (0, 1, 3)]
    assert [w["league"] for w in j["league_history"]] == ["تازه‌کار", "کارآگاه", "سرپرست"]


def test_player_card_has_its_own_rate_policy():
    from app.services import ratelimit as rl
    assert "player_card" in rl.DEFAULTS
    hit = next(pol for m, rx, pol in rl.ROUTES if m in ("GET", "*") and rx.match("/v1/players/abc/card"))
    assert hit == "player_card"
    assert next(pol for m, rx, pol in rl.ROUTES if m in ("GET", "*") and rx.match("/v1/leaderboard/streaks")) == "read"
