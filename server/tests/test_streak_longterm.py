"""Long-term streak rewards, the paid streak repair and the leaderboard flame (Amin, 16 Oct 2026).

Clocks are patched (content.now_local), nothing sleeps. Cases are used by their position in the case list: case i+2
opens at 21:00 of its publish date, and `evening_of` is 22:00 the same day, one hour after it opened.
"""
import asyncio
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import func, select, update

from app import achievements, avatars, content, db, economy, streakrepair
from app.config import get_settings
from app.models import CoinLog, Player, StreakRepair
from app.services import ratelimit

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def evening_of(case_id: str) -> datetime:
    c = content.by_id(case_id)
    return datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN)


def ids_from(start="c010") -> tuple[list[str], int]:
    ids = [c.id for c in content.all_cases()]
    return ids, ids.index(start)


async def _set(pid, **vals):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(**vals))
        await s.commit()


async def _player(pid) -> Player:
    async with db.SessionLocal() as s:
        return await s.get(Player, pid)


async def _count(model, pid, **where) -> int:
    async with db.SessionLocal() as s:
        q = select(func.count()).select_from(model).where(model.player_id == pid)
        for k, v in where.items():
            q = q.where(getattr(model, k) == v)
        return int(await s.scalar(q) or 0)


async def solve_today(client, h, case_id: str) -> dict:
    assert (await client.get(f"/v1/cases/{case_id}", headers=h)).status_code == 200
    c = content.by_id(case_id)
    r = (await client.post(f"/v1/cases/{case_id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved", r
    return r


async def broken_player(client, clock, device, streak=12, coins=2000, **extra):
    """A player whose streak broke: last daily case solved was case i, case i+1 was missed, case i+2 opened an hour ago."""
    p = await new_player(client, device)
    ids, i = ids_from()
    await _set(p["player_id"], streak=streak, best_streak=streak, coins=coins,
               last_daily_solved=content.by_id(ids[i]).publish.isoformat(), **extra)
    clock(evening_of(ids[i + 2]))
    return p, ids, i


# ------------------------------------------------------------------ the ladder and its rewards

def test_ladder_and_reward_rules_are_unchanged():
    assert economy.STREAK_MILESTONES == (3, 7, 14, 30, 60, 100, 200, 365)
    assert economy.next_streak_milestone(0) == 3 and economy.next_streak_milestone(29) == 30
    assert economy.next_streak_milestone(30) == 60 and economy.next_streak_milestone(100) == 200
    assert economy.next_streak_milestone(365) is None
    # no new free coins or warrants: the old numbers stay exactly as they were
    assert (economy.STREAK_BONUS_EVERY, economy.STREAK_BONUS) == (7, 60)
    assert economy.STREAK_WARRANTS == (14, 30) and economy.STREAK_BADGES == (7, 30, 100)
    for m in economy.STREAK_COSMETIC_MILESTONES:
        assert m not in economy.STREAK_WARRANTS


def test_long_milestones_pay_only_cosmetics():
    for m, frame in ((60, "frame_blaze"), (200, "frame_inferno"), (365, "frame_eternal")):
        item = avatars.BY_ID[frame]
        assert (item.how, item.metric, item.target, item.price) == ("goal", "best_streak", m, 0)
        a = achievements.BY_ID[f"streak_{m}"]
        assert a.coins == 0 and a.target == m and a.metric == "best_streak"


@pytest.mark.parametrize("streak,frame", [(60, "frame_blaze"), (200, "frame_inferno"), (365, "frame_eternal")])
async def test_reaching_a_long_milestone_gives_the_frame_and_no_extra_coins(client, clock, streak, frame):
    p = await new_player(client, f"ladder-{streak}")
    h = p["headers"]
    ids, i = ids_from()
    await _set(p["player_id"], streak=streak - 1, best_streak=streak - 1,
               last_daily_solved=content.by_id(ids[i]).publish.isoformat())
    clock(evening_of(ids[i + 1]))
    before = (await client.get("/v1/me", headers=h)).json()["coins"]
    r = await solve_today(client, h, ids[i + 1])
    assert r["streak"] == streak and r["streak_milestone"] == streak and r["badge"] is None
    c = content.by_id(ids[i + 1])
    assert r["reward"] == economy.solve_reward(c.data.get("difficulty"), r["stars"]) + economy.DAILY_BONUS
    assert r["coins"] - before >= r["reward"] and r["gains"]["avatars"] and frame in {g["id"] for g in r["gains"]["avatars"]}
    cat = (await client.get("/v1/avatars", headers=h)).json()
    assert next(x for x in cat["frames"] if x["id"] == frame)["owned"]
    # kept forever, even after the streak breaks
    await _set(p["player_id"], streak=0)
    cat = (await client.get("/v1/avatars", headers=h)).json()
    assert next(x for x in cat["frames"] if x["id"] == frame)["owned"]


async def test_old_badge_field_only_for_the_three_old_badges(client, clock):
    p = await new_player(client, "ladder-badge")
    ids, i = ids_from()
    await _set(p["player_id"], streak=6, best_streak=6, last_daily_solved=content.by_id(ids[i]).publish.isoformat())
    clock(evening_of(ids[i + 1]))
    r = await solve_today(client, p["headers"], ids[i + 1])
    assert r["streak"] == 7 and r["badge"] == 7 and r["streak_milestone"] == 7


def test_config_exposes_the_ladder_and_repair_numbers():
    from app.routers.meta import _economy
    e = _economy()
    assert e["streak_badges"] == [7, 30, 100]
    assert e["streak_milestones"] == [3, 7, 14, 30, 60, 100, 200, 365]
    assert e["streak_repair"]["enabled"] is True and e["streak_repair"]["cap"] == economy.REPAIR_CAP


# ------------------------------------------------------------------ the repair price

def test_repair_price_is_above_the_insurance_and_grows_to_a_cap():
    prices = [economy.streak_repair_cost(n) for n in (3, 7, 14, 30, 60, 100, 365)]
    assert prices == sorted(prices)
    assert all(p > economy.FREEZE_COST for p in prices)
    assert economy.streak_repair_cost(3) == 215 and economy.streak_repair_cost(30) == 350
    assert economy.streak_repair_cost(60) == economy.REPAIR_CAP == economy.streak_repair_cost(10_000)


# ------------------------------------------------------------------ eligibility

async def test_offer_inside_the_window(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-offer")
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["streak_repair"] == {"key": content.by_id(ids[i]).publish.isoformat(), "streak": 12,
                                   "price": economy.streak_repair_cost(12)}


async def test_no_offer_outside_the_24_hours(client, clock, monkeypatch):
    p, ids, i = await broken_player(client, clock, "rep-late")
    monkeypatch.setattr(economy, "REPAIR_WINDOW_HOURS", 0.5)   # the case opened one hour ago
    assert (await client.get("/v1/me", headers=p["headers"])).json()["streak_repair"] is None
    before = (await _player(p["player_id"])).coins
    r = await client.post("/v1/wallet/streak-repair", headers=p["headers"])
    assert r.status_code == 409 and r.json()["detail"] == "not_eligible"
    assert (await _player(p["player_id"])).coins == before


async def test_no_offer_when_two_cases_were_missed(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-two")
    clock(evening_of(ids[i + 3]))
    assert (await client.get("/v1/me", headers=p["headers"])).json()["streak_repair"] is None
    assert (await client.post("/v1/wallet/streak-repair", headers=p["headers"])).status_code == 409


async def test_no_offer_for_a_short_streak_or_with_insurance_or_when_alive(client, clock):
    short, *_ = await broken_player(client, clock, "rep-short", streak=economy.REPAIR_MIN_STREAK - 1)
    assert (await client.get("/v1/me", headers=short["headers"])).json()["streak_repair"] is None
    insured, *_ = await broken_player(client, clock, "rep-insured", streak_freezes=1)
    assert (await client.get("/v1/me", headers=insured["headers"])).json()["streak_repair"] is None
    alive = await new_player(client, "rep-alive")
    ids, i = ids_from()
    await _set(alive["player_id"], streak=12, best_streak=12, last_daily_solved=content.by_id(ids[i + 1]).publish.isoformat())
    clock(evening_of(ids[i + 2]))   # yesterday's case solved: the streak is alive, nothing to mend
    assert (await client.get("/v1/me", headers=alive["headers"])).json()["streak_repair"] is None


async def test_no_offer_for_a_player_who_never_solved_a_daily_case(client, clock):
    p = await new_player(client, "rep-none")
    ids, i = ids_from()
    clock(evening_of(ids[i + 2]))
    assert (await client.get("/v1/me", headers=p["headers"])).json()["streak_repair"] is None


# ------------------------------------------------------------------ buying the repair

async def test_repair_charges_once_and_the_streak_continues(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-buy")
    h, pid = p["headers"], p["player_id"]
    price = economy.streak_repair_cost(12)
    r = await client.post("/v1/wallet/streak-repair", headers=h)
    assert r.status_code == 200, r.text
    me = r.json()
    assert me["coins"] == 2000 - price and me["streak_repair"] is None and me["streak"] == 12
    assert await _count(CoinLog, pid, reason="streak_repair") == 1 and await _count(StreakRepair, pid) == 1
    # asking again never charges again, and the offer is gone
    r2 = await client.post("/v1/wallet/streak-repair", headers=h)
    assert r2.status_code == 409 and r2.json()["detail"] == "not_eligible"
    assert (await _player(pid)).coins == 2000 - price
    # tonight's case continues the streak: one more night, and the bridged night does not add one
    out = await solve_today(client, h, ids[i + 2])
    assert out["streak"] == 13


async def test_repair_does_not_pay_back_and_is_not_offered_again_without_playing(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-noloop")
    h = p["headers"]
    assert (await client.post("/v1/wallet/streak-repair", headers=h)).status_code == 200
    # the player skips tonight's case: the next night shows no second offer for the same streak
    clock(evening_of(ids[i + 3]))
    assert (await client.get("/v1/me", headers=h)).json()["streak_repair"] is None
    assert (await client.post("/v1/wallet/streak-repair", headers=h)).status_code == 409
    # after playing again, a NEW break can be mended again (a different break)
    await _set(p["player_id"], streak=5, last_daily_solved=content.by_id(ids[i + 3]).publish.isoformat())
    clock(evening_of(ids[i + 5]))
    assert (await client.get("/v1/me", headers=h)).json()["streak_repair"]["streak"] == 5


async def test_repair_needs_coins(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-poor", coins=economy.streak_repair_cost(12) - 1)
    r = await client.post("/v1/wallet/streak-repair", headers=p["headers"])
    assert r.status_code == 402 and r.json()["detail"] == {"error": "not_enough_coins", "need": economy.streak_repair_cost(12)}
    pl = await _player(p["player_id"])
    assert pl.coins == economy.streak_repair_cost(12) - 1 and await _count(StreakRepair, p["player_id"]) == 0
    assert pl.last_daily_solved == content.by_id(ids[i]).publish.isoformat()


async def test_two_simultaneous_taps_pay_once(client, clock):
    p, ids, i = await broken_player(client, clock, "rep-double")
    h, pid = p["headers"], p["player_id"]
    rs = await asyncio.gather(*[client.post("/v1/wallet/streak-repair", headers=h) for _ in range(3)])
    assert sorted(r.status_code for r in rs) == [200, 409, 409]
    assert (await _player(pid)).coins == 2000 - economy.streak_repair_cost(12)
    assert await _count(CoinLog, pid, reason="streak_repair") == 1 and await _count(StreakRepair, pid) == 1


async def test_unique_row_blocks_a_second_charge_for_the_same_break(client, clock):
    """Even if the guards above were bypassed, the table refuses a second repair of the same break."""
    p, ids, i = await broken_player(client, clock, "rep-unique")
    key = content.by_id(ids[i]).publish.isoformat()
    async with db.SessionLocal() as s:
        s.add(StreakRepair(player_id=p["player_id"], broken_after=key, streak=12, price=1))
        await s.commit()
    async with db.SessionLocal() as s:
        s.add(StreakRepair(player_id=p["player_id"], broken_after=key, streak=12, price=1))
        with pytest.raises(Exception):
            await s.commit()


async def test_kill_switch(client, clock, monkeypatch):
    p, ids, i = await broken_player(client, clock, "rep-off")
    monkeypatch.setattr(get_settings(), "streak_repair_enabled", False)
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["streak_repair"] is None
    r = await client.post("/v1/wallet/streak-repair", headers=p["headers"])
    assert r.status_code == 403 and r.json()["detail"] == "repair_disabled"
    assert (await _player(p["player_id"])).coins == me["coins"]


def test_repair_uses_the_strict_wallet_policy():
    name = next(pol for m, rx, pol in ratelimit.ROUTES if m in ("POST", "*") and rx.match("/v1/wallet/streak-repair"))
    assert name == "wallet" and ratelimit.DEFAULTS["wallet"].fail == "open" and ratelimit.DEFAULTS["wallet"].store == "strict"


async def test_decisions_are_logged_without_personal_data(client, clock, caplog):
    p, ids, i = await broken_player(client, clock, "rep-log")
    with caplog.at_level("INFO", logger="streak"):
        await client.post("/v1/wallet/streak-repair", headers=p["headers"])
        await client.post("/v1/wallet/streak-repair", headers=p["headers"])
    lines = [r.getMessage() for r in caplog.records if r.name == "streak"]
    assert lines == [f"streak_repair decision=repaired streak=12 price={economy.streak_repair_cost(12)}",
                     "streak_repair decision=not_eligible streak=12 price=0"]
    assert all(p["player_id"] not in line for line in lines)


# ------------------------------------------------------------------ the flame on the leaderboards

async def test_leaderboard_flame_shows_live_streaks_only(client, clock):
    ids, i = ids_from()
    clock(evening_of(ids[i + 2]))
    prev = content.by_id(ids[i + 1]).publish.isoformat()
    a = await new_player(client, "flame-a")
    b = await new_player(client, "flame-b")
    stale = await new_player(client, "flame-stale")
    await _set(a["player_id"], streak=12, best_streak=12, last_daily_solved=prev)
    await _set(stale["player_id"], streak=40, best_streak=40, cases_solved=1, nickname="کهنه",
               last_daily_solved=content.by_id(ids[i - 5]).publish.isoformat())
    await _set(b["player_id"], streak=10_000_000, best_streak=10_000_000, cases_solved=1, nickname="بزرگ", last_daily_solved=prev)
    await solve_today(client, a["headers"], ids[i + 2])
    daily = (await client.get("/v1/leaderboard?period=daily", headers=a["headers"])).json()
    row = next(r for r in daily["top"] if r["me"])
    assert row["streak"] == 13 and daily["me"]["streak"] == 13
    # the all-time board: put the three at the very top so other tests' players cannot push them out of the first 100
    await _set(a["player_id"], nickname="شعله", stars_total=3_000_003)
    await _set(stale["player_id"], stars_total=3_000_002)
    await _set(b["player_id"], stars_total=3_000_001)
    everyone = (await client.get("/v1/leaderboard?period=all&limit=100", headers=a["headers"])).json()["top"]
    by_name = {r["nickname"]: r for r in everyone}
    assert by_name["شعله"]["streak"] == 13
    assert by_name["کهنه"]["streak"] == 0                       # the stored 40 is already broken: no flame
    assert by_name["بزرگ"]["streak"] == streakrepair.MAX_SHOWN_STREAK   # absurd numbers are bounded


async def test_weekly_board_rows_carry_the_flame_field(client, clock):
    ids, i = ids_from()
    clock(evening_of(ids[i + 2]))
    a = await new_player(client, "flame-week")
    await _set(a["player_id"], streak=4, best_streak=4, last_daily_solved=content.by_id(ids[i + 1]).publish.isoformat())
    await solve_today(client, a["headers"], ids[i + 2])
    board = (await client.get("/v1/leaderboard?period=weekly", headers=a["headers"])).json()
    rows = board["top"] + ([board["me"]] if board["me"] else [])
    assert all("streak" in r and 0 <= r["streak"] <= streakrepair.MAX_SHOWN_STREAK for r in rows)


# ------------------------------------------------------------------ old apps keep working

OLD_PROFILE_KEYS = {"player_id", "nickname", "avatar", "avatar_id", "avatar_frame", "invite_code", "referred", "email", "secured",
                    "needs_phone", "phone", "coins", "no_ads", "vip_until", "streak", "best_streak", "cases_solved", "stars_total",
                    "login_reward", "login_day", "streak_freezes", "xp", "rank", "rank_title", "rank_xp", "next_rank_xp",
                    "next_rank_title", "achievements", "warrants"}
OLD_LEADER_KEYS = {"rank", "nickname", "avatar", "avatar_id", "avatar_frame", "value", "stars", "me", "rank_title"}
OLD_ACCUSE_KEYS = {"result", "attempts_left", "stars", "reward", "coins", "streak", "explanation", "culprit", "proof", "rank",
                   "progress", "seconds", "hints_used", "freezes_used", "badge", "gains", "story", "early_bonus"}


async def test_old_payload_shapes_are_unchanged(client, clock):
    ids, i = ids_from()
    clock(evening_of(ids[i + 1]))
    p = await new_player(client, "old-shape")
    h = p["headers"]
    me = (await client.get("/v1/me", headers=h)).json()
    assert OLD_PROFILE_KEYS <= set(me) and me["streak_repair"] is None
    r = await solve_today(client, h, ids[i + 1])
    assert OLD_ACCUSE_KEYS <= set(r)
    board = (await client.get("/v1/leaderboard?period=daily", headers=h)).json()
    assert OLD_LEADER_KEYS <= set(board["top"][0])
    assert (await client.post("/v1/wallet/streak-freeze", headers=h)).status_code == 200   # the insurance is untouched
