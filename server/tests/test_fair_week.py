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


@pytest.fixture(autouse=True)
def _points_order(monkeypatch):
    """These tests use the default order (plaques first, then nights, on-time nights, speed); tests/test_leak_defence.py
    covers the rollback order WEEK_RANK_MODE=consistency."""
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "week_rank_mode", "points")


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
    vet, newbie = await new_player(client, "fw-vet", aged=True), await new_player(client, "fw-new", aged=True)
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
    p = await new_player(client, "fw-sat", aged=True)
    await solve(p["player_id"], wid(new_ws, 0), 3, T(2027, 1, 23, 10))         # Friday 21:00 case, solved Saturday morning
    clock(T(2027, 1, 24, 12))
    assert (await board(client, p["headers"]))["me"]["stars"] == 3


async def test_thursday_case_solved_before_friday_21_counts_for_the_old_week(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 1, 29)
    p = await new_player(client, "fw-thu", aged=True)
    late = await new_player(client, "fw-thu-late", aged=True)
    await solve(p["player_id"], wid(ws, 6), 2, T(2027, 2, 5, 20, 59))           # Friday 20:59: still the old week
    await solve(late["player_id"], wid(ws, 6), 3, T(2027, 2, 5, 21, 1))         # Friday 21:01: archive now
    clock(T(2027, 2, 5, 20, 59))
    assert (await board(client, p["headers"]))["me"]["stars"] == 2
    clock(T(2027, 2, 5, 22))                                                    # the new week's board is empty for both
    assert (await board(client, p["headers"]))["me"] is None
    async with db.SessionLocal() as s:
        st = {x.player.id: x.points for x in await weekboard.standings(s, ws)}
    assert st.get(p["player_id"]) == 2 and late["player_id"] not in st


async def test_unranked_and_unfinished_rows_never_count_and_prizes_skip_new_accounts(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 2, 5)
    clock(T(2027, 2, 8, 12))
    lazy, young, ok = (await new_player(client, "fw-lazy", aged=True), await new_player(client, "fw-young", aged=False),
                       await new_player(client, "fw-ok", aged=True))
    await solve(lazy["player_id"], wid(ws, 0), 1, T(2027, 2, 6, 10), ranked=False)
    await solve(young["player_id"], wid(ws, 0), 3, T(2027, 2, 6, 10))
    await solve(ok["player_id"], wid(ws, 0), 2, T(2027, 2, 6, 10))
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=ok["player_id"], case_id=wid(ws, 1), solved=True, stars=3, ranked=True, finished_at=None))
        await s.commit()
    async with db.SessionLocal() as s:
        st = {x.player.id: x.points for x in await weekboard.standings(s, ws)}
        prize = {x.player.id: x.points for x in await weekboard.standings(s, ws, prize=True)}
    # 28 Oct 2026: the board shows the new unsecured account, the prize list still skips it
    assert st == {ok["player_id"]: 2, young["player_id"]: 3}
    assert prize == {ok["player_id"]: 2}


async def test_tie_break_more_cases_then_faster(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 2, 12)
    clock(T(2027, 2, 15, 12))
    a, b, c = [await new_player(client, f"fw-tie{i}", aged=True) for i in range(3)]
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
    ps = [await new_player(client, f"fw-far{i}", aged=True) for i in range(3)]
    for i, p in enumerate(ps):
        await solve(p["player_id"], wid(ws, 0), 3 - i, T(2027, 2, 20, 10))
    b = await board(client, ps[2]["headers"], limit=1)
    assert len(b["top"]) == 1 and b["me"]["rank"] == 3 and b["me"]["stars"] == 1


# ------------------------------------------------------------------ settlement
async def test_settlement_waits_for_the_margin_and_matches_the_board(client, clock, single_board, week_of_fake_cases):
    ws = date(2027, 3, 5)
    p = await new_player(client, "fw-pay1", aged=True)
    q = await new_player(client, "fw-pay2", aged=True)
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
    p = await new_player(client, "fw-race", aged=True)
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
    p = await new_player(client, "fw-one-case", aged=True)
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 4, 3, 10))
    async with db.SessionLocal() as s:
        assert await rewards.settle_week(s, ws) == 0
    assert await inbox_prizes(client, p) == []


# ------------------------------------------------------------------ leagues
def test_league_thresholds_follow_the_rank_titles():
    from app import economy as eco
    assert weekboard.league_min_xp() == (0, eco.RANKS[4][0], eco.RANKS[8][0], eco.RANKS[12][0])
    assert [weekboard.league_for_xp(x) for x in (0, 1599, 1600, 5599, 5600, 13499, 13500, 99999)] == [0, 0, 1, 1, 2, 2, 3, 3]


async def test_league_snapshot_is_stable_and_a_player_is_in_one_league(client, clock, leagues, week_of_fake_cases):
    ws = date(2027, 4, 9)
    clock(T(2027, 4, 10, 12))
    p = await new_player(client, "fw-snap", aged=True)
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
    fresh = await new_player(client, "fw-snap-new", aged=True)
    async with db.SessionLocal() as s:
        assert await weekboard.league_of(s, ws, fresh["player_id"]) == 0


async def test_board_shows_own_league_with_a_switch(client, clock, leagues, week_of_fake_cases):
    ws = date(2027, 5, 14)
    clock(T(2027, 5, 15, 12))
    rookie, boss = await new_player(client, "fw-lg-r", aged=True), await new_player(client, "fw-lg-b", aged=True)
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
    ps = [await new_player(client, f"fw-pl{i}", aged=True) for i in range(len(xps))]
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
    p = await new_player(client, "fw-off", aged=True)
    await solve(p["player_id"], wid(ws, 0), 3, T(2027, 5, 8, 10))
    b = await board(client, p["headers"])
    assert b["league"] is None and b["leagues"] == [] and b["me"]["rank"] == 1


# ------------------------------------------------------------------ league names and rank titles agree (21 Oct 2026)
def test_every_profile_rank_is_in_exactly_one_league():
    """19 profile ranks, 4 leagues: each rank title belongs to one league, the ranges touch and nothing is left out."""
    from app import economy as eco
    seen = []
    for i in range(len(weekboard.LEAGUES)):
        a, b = weekboard.league_ranks(i)
        assert a <= b
        seen += list(range(a, b + 1))
        info = weekboard.league_info(i)
        assert info["name"] == weekboard.LEAGUES[i] and info["min_xp"] == eco.RANKS[a][0]
        assert info["from_rank"] == eco.RANKS[a][1] and info["to_rank"] == eco.RANKS[b][1]
    assert seen == list(range(len(eco.RANKS)))
    for r in range(len(eco.RANKS)):
        assert weekboard.league_for_xp(eco.RANKS[r][0]) == weekboard.LEAGUES.index(weekboard.league_name_of_rank(r))


async def test_sarbazras_row_shows_profile_rank_and_league(client, clock, leagues, week_of_fake_cases):
    """A player at the XP of «سربازرس» (the reyhoon case): the league is «بازرس» (the range بازرس..سربازرس), and his row
    shows the title «سربازرس» exactly like his profile."""
    from app import economy as eco
    idx = next(i for i, (_, t) in enumerate(eco.RANKS) if t == "سربازرس")
    ws = date(2027, 6, 11)
    clock(T(2027, 6, 12, 12))
    rey = await new_player(client, "fw-rey", aged=True)
    await set_player(rey["player_id"], xp=eco.RANKS[idx][0], cases_solved=20, nickname="reyhoon")
    await solve(rey["player_id"], wid(ws, 0), 3, T(2027, 6, 12, 10))
    prof = (await client.get("/v1/me", headers=rey["headers"])).json()
    assert prof["rank_title"] == "سربازرس"
    b = await board(client, rey["headers"])
    assert b["my_league"] == b["league"] == 2 and b["me"]["rank"] == 1
    row = next(r for r in b["top"] if r["nickname"] == "reyhoon")
    assert row["rank_title"] == prof["rank_title"] == "سربازرس"
    assert row["league_name"] == "بازرس" == b["leagues"][2]["name"]
    info = b["leagues"][2]
    assert (info["from_rank"], info["to_rank"]) == ("بازرس", "سرپرست پرونده‌ها") and info["min_xp"] == eco.RANKS[8][0]
    assert "بازرس" in b["title"] and b["me"]["league_name"] == "بازرس"


async def test_promoted_during_the_week_keeps_the_weeks_league_but_shows_the_current_rank(client, clock, leagues, week_of_fake_cases):
    """XP of کارآگاه ارشد at the week's start, grows to سربازرس on Monday: league stays «کارآگاه», row title is the
    NEW profile rank. This is the by-design difference that looked like a bug."""
    from app import economy as eco
    ws = date(2027, 6, 18)
    clock(T(2027, 6, 19, 9))
    p = await new_player(client, "fw-promo", aged=True)
    await set_player(p["player_id"], xp=next(x for x, t in eco.RANKS if t == "کارآگاه ارشد"), cases_solved=9, nickname="promo")
    async with db.SessionLocal() as s:
        await weekboard.ensure_snapshot(s, ws)               # the week's start
    await set_player(p["player_id"], xp=next(x for x, t in eco.RANKS if t == "سربازرس"))     # promoted to سربازرس later
    clock(T(2027, 6, 21, 12))
    await solve(p["player_id"], wid(ws, 0), 2, T(2027, 6, 21, 10))
    b = await board(client, p["headers"])
    row = next(r for r in b["top"] if r["me"])
    assert b["my_league"] == 1 and row["league_name"] == "کارآگاه" and row["rank_title"] == "سربازرس"
    # he is NOT on the board of the league «بازرس» this week
    other = await board(client, p["headers"], league=2)
    assert not any(r["me"] for r in other["top"])


# ------------------------------------------------------------------ the order: plaques, nights, on-time nights, speed, age
async def test_points_order_plaques_first_then_nights_ontime_speed_age(client, single_board, week_of_fake_cases, monkeypatch):
    """Amin, 31 Oct 2026: 10 plaques over 4 nights beat 8 plaques over 5 nights. my_standing() agrees with standings()."""
    from app.config import get_settings
    ws = date(2027, 3, 5)
    names = ["eight5", "ten4", "two1", "three1", "ontime", "late", "fast", "slow", "old", "young"]
    pl = {n: await new_player(client, f"po-{n}", aged=True) for n in names}

    async def put(name, i, stars, day, seconds=100, daily=False):
        await solve(pl[name]["player_id"], wid(ws, i), stars, T(2027, 3, day, 10), seconds=seconds)
        async with db.SessionLocal() as s:
            await s.execute(update(CaseProgress).where(CaseProgress.player_id == pl[name]["player_id"],
                                                       CaseProgress.case_id == wid(ws, i)).values(was_daily=daily))
            await s.commit()

    for i, st in enumerate([2, 2, 2, 1, 1]):
        await put("eight5", i, st, 6 + i)                      # 8 plaques over 5 nights
    for i, st in enumerate([3, 3, 2, 2]):
        await put("ten4", i, st, 6 + i)                        # 10 plaques over 4 nights
    await put("two1", 0, 3, 6)                                 # same plaques (3) as three1, but one night
    for i in range(2):
        await put("three1", i, 1 + i, 6 + i)
    await put("ontime", 0, 1, 6, daily=True)                   # same plaques and nights: on its own night wins
    await put("late", 0, 1, 7, daily=False)
    await put("fast", 0, 1, 8, seconds=50)                     # all equal but the time
    await put("slow", 0, 1, 8, seconds=400)
    await put("old", 0, 1, 9)                                  # all equal: the older account is first
    await put("young", 0, 1, 9)
    await set_player(pl["old"]["player_id"], created_at=datetime(2026, 1, 1))
    await set_player(pl["young"]["player_id"], created_at=datetime(2026, 6, 1))

    async def order():
        async with db.SessionLocal() as s:
            rows = await weekboard.standings(s, ws)
        return [x.player.id for x in rows]

    ids = {n: pl[n]["player_id"] for n in names}
    got = await order()
    pos = lambda n: got.index(ids[n])           # noqa: E731
    assert pos("ten4") < pos("eight5")                          # plaques first
    assert pos("three1") < pos("two1")                          # equal plaques: more nights
    assert pos("ontime") < pos("late")                          # then nights on their own night
    assert pos("fast") < pos("slow")                            # then less time
    assert pos("old") < pos("young")                            # then the older account
    # my_standing counts exactly like standings
    for n in names:
        async with db.SessionLocal() as s:
            rank, pts = await weekboard.my_standing(s, ws, await s.get(Player, ids[n]), None)
        assert rank == pos(n) + 1, n
    # the rollback order is one setting away: nights first, so the 5-night player now beats the 4-night one
    monkeypatch.setattr(get_settings(), "week_rank_mode", "consistency")
    old = await order()
    assert old.index(ids["eight5"]) < old.index(ids["ten4"])
    for n in names:
        async with db.SessionLocal() as s:
            rank, _ = await weekboard.my_standing(s, ws, await s.get(Player, ids[n]), None)
        assert rank == old.index(ids[n]) + 1, n
