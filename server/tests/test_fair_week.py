"""The fair weekly board: only the week's own cases count, a case belongs to the week it was published in, the prizes
come from the same standings, and the leagues keep veterans with veterans. Uses synthetic case ids (zw...) so no other
test's solves are on these boards."""
from datetime import date, datetime, timedelta
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import func, select, update

from app import content, db, gameclock, rewards, weekboard
from app.models import CaseProgress, InboxItem, Player, WeekLeague, WeekSettlement, utcnow

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


def T(y, m, d, h=0, mi=0):
    return datetime(y, m, d, h, mi, tzinfo=TEHRAN)


def wid(ws: date, i: int) -> str:
    return f"zw{ws.isoformat()}-{i}"          # 14 chars


@pytest.fixture
def week_of_fake_cases(monkeypatch):
    """Every week has 7 fake cases (zw<week>-0..6); the real content is not used on these boards."""
    monkeypatch.setattr(content, "week_cases", lambda ws: [SimpleNamespace(id=wid(ws, i)) for i in range(7)])


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


@pytest.fixture
def single_board(monkeypatch):
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)


@pytest.fixture
def leagues(monkeypatch):
    monkeypatch.setattr(weekboard, "leagues_on", lambda: True)


async def solve(pid, case_id, stars, at, seconds=100, ranked=True):
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=case_id, solved=True, stars=stars, seconds=seconds, ranked=ranked,
                           finished_at=gameclock.to_utc_naive(at), day=gameclock.game_day(at).isoformat()))
        await s.commit()


async def board(client, h, **q):
    qs = "&".join(f"{k}={v}" for k, v in q.items())
    r = await client.get(f"/v1/leaderboard?period=weekly&{qs}", headers=h)
    assert r.status_code == 200, r.text
    return r.json()


async def inbox_prizes(client, p):
    items = (await client.get("/v1/inbox", headers=p["headers"])).json()
    return [i for i in items if i["title"].startswith("جایزه‌ی هفته")]


async def set_player(pid, **vals):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(**vals))
        await s.commit()


# ------------------------------------------------------------------ the points rule
async def test_archive_solves_do_not_count(client, clock, single_board, week_of_fake_cases):
    ws, old = date(2027, 1, 8), date(2027, 1, 1)
    clock(T(2027, 1, 12, 12))
    vet, newbie = await new_player(client, "fw-vet"), await new_player(client, "fw-new")
    await solve(vet["player_id"], wid(ws, 0), 3, T(2027, 1, 8, 22))            # the veteran: the week's own case
    for i in range(7):                                                          # the newcomer buys the old week's archive
        await solve(newbie["player_id"], wid(old, i), 3, T(2027, 1, 11, 10 + i))
    b = await board(client, vet["headers"])
    assert b["me"]["stars"] == 3 and b["me"]["rank"] == 1
    assert all(r["stars"] <= 3 for r in b["top"])
    nb = await board(client, newbie["headers"])
    assert nb["me"] is None            # 21 stars of archive: nothing on this week's board
    assert nb["week_ends_at"] == int(gameclock.week_end(ws).timestamp())


async def test_friday_case_solved_on_saturday_counts_for_its_new_week(client, clock, single_board, week_of_fake_cases):
    new_ws = date(2027, 1, 22)
    p = await new_player(client, "fw-sat")
    await solve(p["player_id"], wid(new_ws, 0), 3, T(2027, 1, 23, 10))         # Friday 21:00 case, solved Saturday morning
    clock(T(2027, 1, 24, 12))
    assert (await board(client, p["headers"]))["me"]["stars"] == 3


async def test_thursday_case_solved_before_friday_21_counts_for_the_old_week(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 1, 29)
    p = await new_player(client, "fw-thu")
    late = await new_player(client, "fw-thu-late")
    await solve(p["player_id"], wid(ws, 6), 2, T(2027, 2, 5, 20, 59))           # Friday 20:59: still the old week
    await solve(late["player_id"], wid(ws, 6), 3, T(2027, 2, 5, 21, 1))         # Friday 21:01: archive now
    clock(T(2027, 2, 5, 20, 59))
    assert (await board(client, p["headers"]))["me"]["stars"] == 2
    clock(T(2027, 2, 5, 22))                                                    # the new week's board is empty for both
    assert (await board(client, p["headers"]))["me"] is None
    async with db.SessionLocal() as s:
        st = {x.player.id: x.points for x in await weekboard.standings(s, ws)}
    assert st.get(p["player_id"]) == 2 and late["player_id"] not in st


async def test_unranked_hidden_and_unfinished_rows_never_count(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 2, 5)
    clock(T(2027, 2, 8, 12))
    lazy, young, ok = (await new_player(client, "fw-lazy"), await new_player(client, "fw-young", aged=False),
                       await new_player(client, "fw-ok"))
    await solve(lazy["player_id"], wid(ws, 0), 1, T(2027, 2, 6, 10), ranked=False)
    await solve(young["player_id"], wid(ws, 0), 3, T(2027, 2, 6, 10))
    await solve(ok["player_id"], wid(ws, 0), 2, T(2027, 2, 6, 10))
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=ok["player_id"], case_id=wid(ws, 1), solved=True, stars=3, ranked=True, finished_at=None))
        await s.commit()
    async with db.SessionLocal() as s:
        st = {x.player.id: x.points for x in await weekboard.standings(s, ws)}
    assert st == {ok["player_id"]: 2}


async def test_tie_break_more_cases_then_faster(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 2, 12)
    clock(T(2027, 2, 15, 12))
    a, b, c = [await new_player(client, f"fw-tie{i}") for i in range(3)]
    await solve(a["player_id"], wid(ws, 0), 3, T(2027, 2, 13, 10), seconds=50)                    # 3 points, 1 case
    await solve(b["player_id"], wid(ws, 0), 2, T(2027, 2, 13, 10), seconds=300)                   # 3 points, 2 cases
    await solve(b["player_id"], wid(ws, 1), 1, T(2027, 2, 14, 10), seconds=300)
    await solve(c["player_id"], wid(ws, 0), 2, T(2027, 2, 13, 10), seconds=100)                   # 3 points, 2 cases, faster
    await solve(c["player_id"], wid(ws, 1), 1, T(2027, 2, 14, 10), seconds=100)
    async with db.SessionLocal() as s:
        order = [x.player.id for x in await weekboard.standings(s, ws)]
    assert order[:3] == [c["player_id"], b["player_id"], a["player_id"]]


async def test_my_rank_beyond_the_limit(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 2, 19)
    clock(T(2027, 2, 21, 12))
    ps = [await new_player(client, f"fw-far{i}") for i in range(3)]
    for i, p in enumerate(ps):
        await solve(p["player_id"], wid(ws, 0), 3 - i, T(2027, 2, 20, 10))
    b = await board(client, ps[2]["headers"], limit=1)
    assert len(b["top"]) == 1 and b["me"]["rank"] == 3 and b["me"]["stars"] == 1


# ------------------------------------------------------------------ settlement
async def test_settlement_waits_for_the_margin_and_matches_the_board(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 3, 5)
    p = await new_player(client, "fw-pay1")
    q = await new_player(client, "fw-pay2")
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 3, 6, 10))
    await solve(p["player_id"], wid(ws, 1), 3, T(2027, 3, 7, 10))
    await solve(q["player_id"], wid(ws, 0), 2, T(2027, 3, 6, 10))
    await solve(q["player_id"], wid(ws, 1), 2, T(2027, 3, 12, 20, 59))           # the last legal minute
    await solve(q["player_id"], wid(ws, 2), 3, T(2027, 3, 12, 21, 1))            # too late: archive
    clock(T(2027, 3, 12, 21, 5))                                                 # closed, but inside the safety margin
    assert gameclock.settle_at(ws) == T(2027, 3, 12, 21, 10)
    assert ws not in rewards.settleable_weeks(content.now_local())
    clock(T(2027, 3, 12, 21, 11))
    assert ws in rewards.settleable_weeks(content.now_local())
    b = await board(client, p["headers"])        # the new week's board; the old one is read straight from the helper
    async with db.SessionLocal() as s:
        board_rows = [(x.player.id, x.points) for x in await weekboard.standings(s, ws)]
        assert board_rows == [(p["player_id"], 6), (q["player_id"], 4)]
        assert await rewards.settle_week(s, ws) == 2
        assert await rewards.settle_week(s, ws) == 0                              # once
    assert [i["grants"] for i in await inbox_prizes(client, p)] == [[{"type": "coins", "amount": 300}]]
    assert [i["grants"] for i in await inbox_prizes(client, q)] == [[{"type": "coins", "amount": 200}]]
    assert "6 پلاک" in (await inbox_prizes(client, p))[0]["message"]
    assert b["me"] is None
    async with db.SessionLocal() as s:
        assert (await s.get(WeekSettlement, ws.isoformat())).paid == 2


async def test_two_simultaneous_settlements_pay_once(client, clock, single_board, week_of_fake_cases):
    import asyncio
    ws = date(2027, 3, 19)
    p = await new_player(client, "fw-race")
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 3, 20, 10))
    await solve(p["player_id"], wid(ws, 1), 3, T(2027, 3, 21, 10))

    async def go():
        async with db.SessionLocal() as s:
            return await rewards.settle_week(s, ws)
    results = await asyncio.gather(go(), go())
    assert sorted(results) == [0, 1]
    async with db.SessionLocal() as s:
        n = await s.scalar(select(func.count()).select_from(InboxItem).where(InboxItem.source == rewards.source_for(ws)))
    assert n == 1


async def test_weeks_before_the_fair_rule_are_never_paid(client, clock, single_board, week_of_fake_cases):
    clock(T(2026, 10, 17, 18, 40))        # the day the rule starts: the old week (Oct 9-16) was paid by the old rule
    assert rewards.settleable_weeks(content.now_local()) == []
    clock(T(2026, 10, 23, 21, 11))
    assert rewards.settleable_weeks(content.now_local()) == [date(2026, 10, 16)]


async def test_a_prize_needs_two_cases(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 4, 2)
    p = await new_player(client, "fw-one-case")
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 4, 3, 10))
    async with db.SessionLocal() as s:
        assert await rewards.settle_week(s, ws) == 0
    assert await inbox_prizes(client, p) == []


# ------------------------------------------------------------------ leagues
def test_league_thresholds_follow_the_rank_titles():
    from app import economy as eco
    assert weekboard.league_min_xp() == (0, eco.RANKS[2][0], eco.RANKS[4][0], eco.RANKS[6][0])
    assert [weekboard.league_for_xp(x) for x in (0, 599, 600, 2499, 2500, 6499, 6500, 99999)] == [0, 0, 1, 1, 2, 2, 3, 3]


async def test_league_snapshot_is_stable_and_a_player_is_in_one_league(client, clock, leagues, week_of_fake_cases):
    ws = date(2027, 4, 9)
    clock(T(2027, 4, 10, 12))
    p = await new_player(client, "fw-snap")
    await set_player(p["player_id"], xp=700, cases_solved=5)
    async with db.SessionLocal() as s:
        assert await weekboard.league_of(s, ws, p["player_id"]) == 1
    await set_player(p["player_id"], xp=99999)                  # grows during the week: the league does not change
    async with db.SessionLocal() as s:
        assert await weekboard.league_of(s, ws, p["player_id"]) == 1
        rows = (await s.execute(select(WeekLeague).where(WeekLeague.week == ws.isoformat(), WeekLeague.player_id == p["player_id"]))).scalars().all()
        assert len(rows) == 1
        marker = await s.scalar(select(func.count()).select_from(WeekLeague).where(WeekLeague.week == ws.isoformat(), WeekLeague.player_id == weekboard.MARKER))
        assert marker == 1
    async with db.SessionLocal() as s:                         # taking it again changes nothing
        await weekboard.ensure_snapshot(s, ws)
        assert await weekboard.league_of(s, ws, p["player_id"]) == 1
    next_ws = ws + timedelta(days=7)
    async with db.SessionLocal() as s:                         # next week's snapshot is the promotion
        assert await weekboard.league_of(s, next_ws, p["player_id"]) == 3
    # a player who never solved anything is in league 0
    fresh = await new_player(client, "fw-snap-new")
    async with db.SessionLocal() as s:
        assert await weekboard.league_of(s, ws, fresh["player_id"]) == 0


async def test_board_shows_own_league_with_a_switch(client, clock, leagues, week_of_fake_cases):
    ws = date(2027, 5, 14)
    clock(T(2027, 5, 15, 12))
    rookie, boss = await new_player(client, "fw-lg-r"), await new_player(client, "fw-lg-b")
    await set_player(boss["player_id"], xp=7000, cases_solved=50)
    await set_player(rookie["player_id"], xp=10, cases_solved=1)
    await solve(rookie["player_id"], wid(ws, 0), 3, T(2027, 5, 15, 10))
    await solve(boss["player_id"], wid(ws, 0), 1, T(2027, 5, 15, 10))
    mine = await board(client, rookie["headers"])
    assert mine["league"] == 0 and mine["my_league"] == 0 and len(mine["leagues"]) == 4 and mine["me"]["rank"] == 1
    assert "تازه‌کار" in mine["title"]
    other = await board(client, rookie["headers"], league=3)
    assert other["league"] == 3 and other["me"] is None and any(r["stars"] == 1 for r in other["top"])
    assert not any(r["me"] for r in other["top"])
    bossb = await board(client, boss["headers"])
    assert bossb["league"] == 3 and bossb["me"]["rank"] == 1       # 1 point wins his league, the rookie's 3 is another board


async def test_settlement_pays_each_league_once(client, clock, leagues, week_of_fake_cases):
    ws = date(2027, 4, 23)
    clock(T(2027, 4, 24, 12))
    xps = [0, 0, 0, 0, 700, 3000, 7000]            # four rookies (only 3 prizes), one of each other league
    ps = [await new_player(client, f"fw-pl{i}") for i in range(len(xps))]
    for p, xp in zip(ps, xps):
        await set_player(p["player_id"], xp=xp, cases_solved=5)
    async with db.SessionLocal() as s:
        await weekboard.ensure_snapshot(s, ws)
    for i, p in enumerate(ps):
        await solve(p["player_id"], wid(ws, 0), 3, T(2027, 4, 24, 10), seconds=100 + i)
        await solve(p["player_id"], wid(ws, 1), 3, T(2027, 4, 25, 10), seconds=100 + i)
    await set_player(ps[0]["player_id"], xp=99999)  # grows mid-week: still a rookie that week
    clock(T(2027, 4, 30, 21, 30))
    async with db.SessionLocal() as s:
        paid = await rewards.settle_week(s, ws)
        assert paid == 3 + 1 + 1 + 1
        assert await rewards.settle_week(s, ws) == 0
        assert await rewards.settle_last_week(s) >= 0
    prizes = {p["player_id"]: await inbox_prizes(client, p) for p in ps}
    assert [len(v) for v in prizes.values()] == [1, 1, 1, 0, 1, 1, 1]       # the 4th rookie gets nothing; nobody twice
    amounts = [v[0]["grants"][0]["amount"] for v in list(prizes.values())[:3]]
    assert amounts == [120, 80, 50]
    assert [prizes[ps[i]["player_id"]][0]["grants"][0]["amount"] for i in (4, 5, 6)] == [120, 120, 120]
    # the whole bill is lower than the old single board (1175)
    assert sum(weekboard.LEAGUE_PRIZES.values()) * 4 <= sum(rewards.PRIZES.values()) + 7 * rewards.PRIZE_REST
    # only the highest league's winner gets the champion item
    async with db.SessionLocal() as s:
        top = await s.get(Player, ps[6]["player_id"])
        low = await s.get(Player, ps[1]["player_id"])
        assert (top.stats or {}).get("weekly_top3") == 1 and not (low.stats or {}).get("weekly_top3")


async def test_leagues_kill_switch_falls_back_to_one_board(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 5, 7)
    clock(T(2027, 5, 8, 12))
    p = await new_player(client, "fw-off")
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 5, 8, 10))
    b = await board(client, p["headers"])
    assert b["league"] is None and b["leagues"] == [] and b["me"]["rank"] == 1
