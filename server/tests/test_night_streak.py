"""Streak insurance like Duolingo (Amin, 30 Oct 2026): the insurance is spent THE NIGHT a daily case is missed (the profile
shows it at once), a covered night counts as a night of the streak, an uninsured miss shows 0 at once, the repair offer
still knows the old streak. Clocks are patched; nothing sleeps. Runs on SQLite and PostgreSQL (CI job server-postgres)."""
import asyncio
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import select

from app import content, db, economy, streakrepair
from app.models import Player

from .conftest import new_player
from .test_streak_longterm import _player, _set, evening_of, ids_from, solve_today

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def pub(ids, k):
    return content.by_id(ids[k]).publish.isoformat()


async def holder(client, clock, device, *, streak, freezes, last_offset, today_offset, coins=2000):
    """streak/freezes held, last daily case solved = case i+last_offset, 'now' = one hour after case i+today_offset opened."""
    p = await new_player(client, device)
    ids, i = ids_from()
    await _set(p["player_id"], streak=streak, best_streak=streak, streak_freezes=freezes, coins=coins,
               last_daily_solved=pub(ids, i + last_offset))
    clock(evening_of(ids[i + today_offset]))
    return p, ids, i


async def me(client, p):
    return (await client.get("/v1/me", headers=p["headers"])).json()


def test_effective_streak_is_pure_and_all_or_nothing(monkeypatch):
    ids, i = ids_from()
    monkeypatch.setattr(content, "now_local", lambda: evening_of(ids[i + 3]))
    pl = Player(streak=5, best_streak=5, streak_freezes=2, last_daily_solved=pub(ids, i))   # missed i+1 and i+2
    assert streakrepair.effective_streak(pl) == (7, 0, 2, False)
    pl = Player(streak=5, best_streak=5, streak_freezes=1, last_daily_solved=pub(ids, i))
    assert streakrepair.effective_streak(pl) == (0, 1, 0, True)         # not enough: broken, insurance untouched
    pl = Player(streak=5, best_streak=5, streak_freezes=0, last_daily_solved=pub(ids, i + 2))
    assert streakrepair.effective_streak(pl) == (5, 0, 0, False)        # today's own unsolved case is not missed
    pl = Player(streak=0, best_streak=0, streak_freezes=2, last_daily_solved=pub(ids, i))
    assert streakrepair.effective_streak(pl) == (0, 2, 0, False)        # no streak: nothing to cover, insurance kept
    assert pl.streak == 0 and pl.streak_freezes == 2                    # pure: nothing written


async def test_insured_player_misses_one_night(client, clock):
    p, ids, i = await holder(client, clock, "ns-one", streak=5, freezes=2, last_offset=0, today_offset=2)
    m = await me(client, p)
    assert (m["streak"], m["streak_freezes"]) == (6, 1)          # spent that night, the night counts
    assert m["streak_repair"] is None
    stored = await _player(p["player_id"])
    assert (stored.streak, stored.streak_freezes) == (5, 2)      # a GET writes nothing
    r = await solve_today(client, p["headers"], ids[i + 2])
    assert r["streak"] == 7 and r["freezes_used"] == 1           # +1 covered night, +1 this solve
    c = content.by_id(ids[i + 2])
    # crossing 7 pays the streak bonus ONCE and gives the badge
    assert r["reward"] == economy.solve_reward(c.data.get("difficulty"), r["stars"]) + economy.DAILY_BONUS + economy.STREAK_BONUS
    assert r["badge"] == 7 and r["streak_milestone"] == 7
    assert (await me(client, p))["streak_freezes"] == 1


async def test_insured_player_misses_two_nights(client, clock):
    p, ids, i = await holder(client, clock, "ns-two", streak=3, freezes=2, last_offset=0, today_offset=3)
    m = await me(client, p)
    assert (m["streak"], m["streak_freezes"]) == (5, 0)
    r = await solve_today(client, p["headers"], ids[i + 3])
    assert r["streak"] == 6 and r["freezes_used"] == 2
    assert (await _player(p["player_id"])).best_streak == 6


async def test_not_enough_insurance_breaks_at_once_and_keeps_it(client, clock):
    p, ids, i = await holder(client, clock, "ns-short", streak=3, freezes=1, last_offset=0, today_offset=3)
    m = await me(client, p)
    assert (m["streak"], m["streak_freezes"]) == (0, 1)
    assert m["streak_repair"] is None                            # two missed cases: no repair either
    r = await solve_today(client, p["headers"], ids[i + 3])
    assert r["streak"] == 1 and r["freezes_used"] == 0 and (await me(client, p))["streak_freezes"] == 1


async def test_uninsured_miss_shows_zero_but_repair_still_knows_the_old_streak(client, clock):
    p, ids, i = await holder(client, clock, "ns-none", streak=12, freezes=0, last_offset=0, today_offset=2)
    m = await me(client, p)
    assert m["streak"] == 0 and m["streak_repair"]["streak"] == 12
    r = await client.post("/v1/wallet/streak-repair", headers=p["headers"])
    assert r.status_code == 200 and r.json()["streak"] == 12 and r.json()["streak_repair"] is None


async def test_todays_unsolved_case_is_not_missed(client, clock):
    p, ids, i = await holder(client, clock, "ns-today", streak=4, freezes=1, last_offset=1, today_offset=2)
    m = await me(client, p)
    assert (m["streak"], m["streak_freezes"]) == (4, 1)


async def test_buying_insurance_after_the_miss_does_not_cover_it(client, clock):
    p, ids, i = await holder(client, clock, "ns-late", streak=12, freezes=0, last_offset=0, today_offset=2)
    r = await client.post("/v1/wallet/streak-freeze", headers=p["headers"])
    assert r.status_code == 200
    m = r.json()
    assert (m["streak"], m["streak_freezes"]) == (0, 1)          # bought, but the missed night stays missed
    assert (await me(client, p))["streak"] == 0
    assert (await me(client, p))["streak_repair"]["streak"] == 12   # the break can still be mended once
    out = await solve_today(client, p["headers"], ids[i + 2])
    assert out["streak"] == 1 and out["freezes_used"] == 0
    assert (await me(client, p))["streak_freezes"] == 1


async def test_buying_insurance_settles_the_covered_night_first_and_the_bonus_still_pays_once(client, clock):
    p, ids, i = await holder(client, clock, "ns-buy", streak=6, freezes=1, last_offset=0, today_offset=2)
    m = (await client.post("/v1/wallet/streak-freeze", headers=p["headers"])).json()
    assert (m["streak"], m["streak_freezes"]) == (7, 1)          # 1 spent for the night, 1 bought
    stored = await _player(p["player_id"])
    assert (stored.streak, stored.streak_freezes) == (7, 1)
    r = await solve_today(client, p["headers"], ids[i + 2])
    c = content.by_id(ids[i + 2])
    assert r["streak"] == 8 and r["badge"] == 7                  # 7 was crossed by the covered night: paid now, once
    assert r["reward"] == economy.solve_reward(c.data.get("difficulty"), r["stars"]) + economy.DAILY_BONUS + economy.STREAK_BONUS


async def test_two_simultaneous_solves_spend_the_insurance_once(client, clock):
    p, ids, i = await holder(client, clock, "ns-race", streak=5, freezes=2, last_offset=0, today_offset=2)
    h = p["headers"]
    assert (await client.get(f"/v1/cases/{ids[i + 2]}", headers=h)).status_code == 200
    c = content.by_id(ids[i + 2])
    body = {"suspect": c.culprit, "evidence": sorted(c.proof)[0]}
    rs = await asyncio.gather(*[client.post(f"/v1/cases/{ids[i + 2]}/accuse", headers=h, json=body) for _ in range(3)],
                         return_exceptions=True)
    assert any(not isinstance(r, Exception) and r.status_code == 200 for r in rs)
    stored = await _player(p["player_id"])
    assert (stored.streak, stored.streak_freezes) == (7, 1)      # spent once, +1 night covered, +1 solve


async def test_decisions_are_logged_without_personal_data(client, clock, caplog):
    p, ids, i = await holder(client, clock, "ns-log", streak=5, freezes=1, last_offset=0, today_offset=2)
    with caplog.at_level("INFO", logger="streak"):
        await solve_today(client, p["headers"], ids[i + 2])
    lines = [r.getMessage() for r in caplog.records if r.name == "streak"]
    assert lines == ["streak_insurance decision=spent nights=1 left=0 streak=6"]
    assert all(p["player_id"] not in line for line in lines)


async def test_the_board_flame_counts_covered_nights(client, clock):
    p, ids, i = await holder(client, clock, "ns-flame", streak=9, freezes=1, last_offset=0, today_offset=2)
    await _set(p["player_id"], nickname="شعله‌ی بیمه", cases_solved=1, stars_total=4_000_001)
    board = (await client.get("/v1/leaderboard?period=all&limit=100", headers=p["headers"])).json()["top"]
    await _set(p["player_id"], stars_total=0)
    assert next(r for r in board if r["nickname"] == "شعله‌ی بیمه")["streak"] == 10
