"""Real PostgreSQL races in isolated CI DB; never point this fixture at production.

Each transaction has its own async session/connection. Barriers force stale reads for the
low-level tests; route tests hold the account lock until both requests have started.
"""
import asyncio
import os
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app import achievements, anticheat, content, db, economy as eco, missions
from app.models import (Broadcast, BroadcastClaim, CaseProgress, CoinLog, InboxItem, MissionDay,
                        Player, PlayerAchievement, Purchase, ReferralPayout)
from app.security import make_token
from app.util import add_coins

pytestmark = pytest.mark.skipif(not os.environ.get("WALLET_TEST_DATABASE_URL"), reason="isolated PostgreSQL required")


@pytest.fixture(autouse=True)
async def postgres(monkeypatch):
    url = os.environ["WALLET_TEST_DATABASE_URL"]
    # Destructive fixture has an explicit, deliberately narrow target guard.
    assert url.startswith("postgresql+asyncpg://") and url.rsplit("/", 1)[-1] == "wallet_test"
    engine = create_async_engine(url, pool_size=8, max_overflow=4)
    monkeypatch.setattr(db, "engine", engine)
    monkeypatch.setattr(db, "SessionLocal", async_sessionmaker(engine, expire_on_commit=False))
    async with engine.begin() as conn:
        await conn.run_sync(db.Base.metadata.drop_all)
        await conn.run_sync(db.Base.metadata.create_all)
    yield
    await engine.dispose()


async def account(coins=200, **values):
    async with db.SessionLocal() as s:
        n = int(await s.scalar(select(func.count()).select_from(Player)) or 0)
        p = Player(secret_hash="test", device_id=f"device-{n}", invite_code=f"CODE{n}", coins=coins, **values)
        s.add(p)
        await s.commit()
        token, _ = make_token(p.id)
        return p.id, {"Authorization": f"Bearer {token}"}


async def snapshot(pid):
    async with db.SessionLocal() as s:
        p = await s.get(Player, pid)
        logs = (await s.scalars(select(CoinLog).where(CoinLog.player_id == pid).order_by(CoinLog.id))).all()
        return p, logs


def ledger(logs, initial, final):
    balance = initial
    for row in logs:
        balance += row.amount
        assert row.balance == balance
        assert balance >= 0
    assert balance == final


async def together(*operations):
    gate = asyncio.Barrier(len(operations))
    async def start(op):
        await gate.wait()
        return await op
    return await asyncio.wait_for(asyncio.gather(*(start(op) for op in operations)), 20)


@pytest.mark.parametrize("amounts,final,successes", [((-70, -70), 30, 1), ((40, 60), 200, 2), ((40, -70), 70, 2)])
async def test_atomic_deltas_with_stale_orm_balances(amounts, final, successes):
    pid, _ = await account(100)
    barrier = asyncio.Barrier(2)
    async def change(amount):
        async with db.SessionLocal() as s:
            p = await s.get(Player, pid)
            assert p.coins == 100
            await barrier.wait()  # both read the SAME old balance before either writes
            try:
                await add_coins(s, p, amount, f"test:{amount}")
                await s.commit()
                return 200
            except HTTPException as err:
                await s.rollback()
                return err.status_code
    codes = await asyncio.wait_for(asyncio.gather(*(change(a) for a in amounts)), 20)
    assert codes.count(200) == successes
    assert codes.count(402) == 2 - successes
    p, logs = await snapshot(pid)
    assert p.coins == final and len(logs) == successes
    ledger(logs, 100, final)


@pytest.mark.parametrize("amount", [-70, 40])
async def test_rollback_restores_balance_log_and_related_state(amount):
    pid, _ = await account(100)
    async with db.SessionLocal() as s:
        p = (await db.lock_players(s, [pid]))[pid]
        p.streak_freezes += 1
        await add_coins(s, p, amount, "rollback")
        s.add(InboxItem(player_id=pid, title="rolled back", claimed_at=datetime.utcnow()))
        await s.flush()
        await s.rollback()
    p, logs = await snapshot(pid)
    assert p.coins == 100 and p.streak_freezes == 0 and not logs
    async with db.SessionLocal() as s:
        assert not await s.scalar(select(InboxItem.id))


async def test_insufficient_balance_never_clamps_or_logs():
    pid, _ = await account(5)
    async with db.SessionLocal() as s:
        p = await s.get(Player, pid)
        with pytest.raises(HTTPException) as caught:
            await add_coins(s, p, -30, "insufficient")
        assert caught.value.status_code == 402
        await s.rollback()
    p, logs = await snapshot(pid)
    assert p.coins == 5 and not logs


async def test_independent_spending_cannot_overspend(client):
    pid, h = await account(200)
    responses = await together(*(client.post("/v1/wallet/streak-freeze", headers=h) for _ in range(2)))
    assert sorted(r.status_code for r in responses) == [200, 402]
    p, logs = await snapshot(pid)
    assert p.coins == 200 - eco.FREEZE_COST and p.streak_freezes == 1
    ledger(logs, 200, p.coins)
    assert len(logs) == 1


async def test_reward_and_spending_keep_both_effects(client):
    pid, h = await account(200)
    responses = await together(client.post("/v1/wallet/streak-freeze", headers=h), client.get("/v1/me", headers=h))
    assert [r.status_code for r in responses] == [200, 200]
    p, logs = await snapshot(pid)
    assert p.coins == 200 - eco.FREEZE_COST + eco.LOGIN_CALENDAR[0]
    assert p.streak_freezes == 1 and p.login_day == 1
    ledger(logs, 200, p.coins)


async def test_daily_login_and_achievement_are_claimed_once(client):
    pid, h = await account(200, email="secure@example.com", secure_rewarded=True)
    responses = await together(*(client.get("/v1/me", headers=h) for _ in range(3)))
    assert all(r.status_code == 200 for r in responses)
    assert sum(r.json()["login_reward"] for r in responses) == eco.LOGIN_CALENDAR[0]
    p, logs = await snapshot(pid)
    assert p.login_day == 1
    assert len([l for l in logs if l.reason.startswith("daily_login:")]) == 1
    assert len({l.reason for l in logs}) == len(logs)
    async with db.SessionLocal() as s:
        earned = (await s.scalars(select(PlayerAchievement.achievement_id).where(PlayerAchievement.player_id == pid))).all()
        assert earned and len(earned) == len(set(earned))
    ledger(logs, 200, p.coins)


@pytest.mark.parametrize("shared", [False, True])
async def test_gift_claim_once_including_perks(client, shared):
    pid, h = await account(200)
    until = int(datetime(2027, 1, 1, tzinfo=ZoneInfo("UTC")).timestamp())
    grants = [{"type": "coins", "amount": 65}, {"type": "no_ads"}, {"type": "vip_until", "ts": until}]
    async with db.SessionLocal() as s:
        item = Broadcast(title="gift", grants=grants) if shared else InboxItem(player_id=pid, title="gift", grants=grants)
        s.add(item)
        await s.commit()
        path = f"/v1/inbox/{'b' if shared else 'p'}{item.id}/claim"
    responses = await together(*(client.post(path, headers=h) for _ in range(3)))
    assert sorted(r.status_code for r in responses) == [200, 409, 409]
    p, logs = await snapshot(pid)
    assert p.coins == 265 and p.no_ads and p.vip_until == datetime(2027, 1, 1)
    assert len(logs) == 1
    ledger(logs, 200, 265)
    async with db.SessionLocal() as s:
        if shared:
            assert await s.scalar(select(func.count()).select_from(BroadcastClaim)) == 1
        else:
            assert (await s.get(InboxItem, item.id)).claimed_at is not None


async def test_purchase_retries_grant_once_and_distinct_tokens_accumulate(client):
    pid, h = await account(200)
    body = {"product_id": "coins_small", "purchase_token": "test-retry", "store": "bazaar"}
    responses = await together(*(client.post("/v1/purchases/verify", headers=h, json=body) for _ in range(3)))
    assert all(r.status_code == 200 for r in responses)
    assert sorted(r.json()["status"] for r in responses) == ["already_granted", "already_granted", "granted"]
    responses = await together(*(client.post("/v1/purchases/verify", headers=h,
        json={**body, "purchase_token": f"test-distinct-{i}"}) for i in range(2)))
    assert all(r.json()["status"] == "granted" for r in responses)
    p, logs = await snapshot(pid)
    assert p.coins == 200 + 3 * eco.PRODUCTS["coins_small"].coins and len(logs) == 3
    ledger(logs, 200, p.coins)
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(Purchase)) == 3


async def test_token_race_across_accounts_rolls_back_losing_credit(client, monkeypatch):
    a, ha = await account(200)
    b, hb = await account(200)
    # Force BOTH requests past the token lookup before either can grant it.
    from app.main import app
    from app.services.bazaar import get_bazaar, PurchaseCheck
    barrier = asyncio.Barrier(2)
    class Store:
        async def check_inapp(self, product, token):
            await barrier.wait()
            return PurchaseCheck(valid=True)
    monkeypatch.setitem(app.dependency_overrides, get_bazaar, lambda: Store())
    body = {"product_id": "coins_small", "purchase_token": "test-shared", "store": "bazaar"}
    responses = await together(*(client.post("/v1/purchases/verify", headers=h, json=body) for h in [ha, hb]))
    assert sorted(r.json()["status"] for r in responses) == ["granted", "rejected"]
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.sum(Player.coins))) == 400 + eco.PRODUCTS["coins_small"].coins
        assert await s.scalar(select(func.count()).select_from(Purchase)) == 1
        assert await s.scalar(select(func.count()).select_from(CoinLog)) == 1
    for pid in [a, b]:
        p, logs = await snapshot(pid)
        ledger(logs, 200, p.coins)


@pytest.fixture
async def tonight(monkeypatch):
    c = content.by_id("c020")
    monkeypatch.setattr(content, "now_local", lambda: datetime.combine(c.publish, datetime.min.time(),
                                                                      ZoneInfo("Asia/Tehran")) + timedelta(hours=22))
    return c


async def test_same_archive_unlock_charges_once(client, tonight):
    pid, h = await account(500)
    c = content.by_id("c019")
    responses = await together(*(client.post(f"/v1/cases/{c.id}/unlock", headers=h) for _ in range(2)))
    assert all(r.status_code == 200 for r in responses)
    p, logs = await snapshot(pid)
    assert len([l for l in logs if l.reason == f"unlock:{c.id}"]) == 1
    assert (p.stats or {})["case_unlock"] == 1
    ledger(logs, 500, p.coins)
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(CaseProgress)) == 1


async def test_two_archive_purchases_share_one_wallet(client, tonight):
    pid, h = await account(200)
    responses = await together(*(client.post(f"/v1/cases/{cid}/unlock", headers=h) for cid in ["c018", "c019"]))
    assert sorted(r.status_code for r in responses) == [200, 402]
    p, logs = await snapshot(pid)
    assert p.coins == 50 and len(logs) == 1
    assert p.stats["case_unlock"] == 1
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(CaseProgress)) == 1
    ledger(logs, 200, 50)


async def test_simultaneous_hints_advance_and_charge_distinct_tiers(client, tonight):
    pid, h = await account(500)
    assert (await client.get(f"/v1/cases/{tonight.id}", headers=h)).status_code == 200
    responses = await together(*(client.post(f"/v1/cases/{tonight.id}/hint", headers=h) for _ in range(2)))
    assert all(r.status_code == 200 for r in responses)
    p, logs = await snapshot(pid)
    costs = [l.amount for l in logs if l.reason.startswith("hint")]
    assert costs == [-eco.HINT_COSTS[0], -eco.HINT_COSTS[1]]
    async with db.SessionLocal() as s:
        progress = await s.scalar(select(CaseProgress).where(CaseProgress.player_id == pid))
        assert progress.hints == 2
    ledger(logs, 500, p.coins)


async def test_solve_retries_do_not_duplicate_reward_xp_or_counters(client, tonight):
    pid, h = await account(200)
    assert (await client.get(f"/v1/cases/{tonight.id}", headers=h)).status_code == 200
    body = {"suspect": tonight.culprit, "evidence": sorted(tonight.proof)[0]}
    responses = await together(*(client.post(f"/v1/cases/{tonight.id}/accuse", headers=h, json=body) for _ in range(3)))
    assert sorted(r.status_code for r in responses) == [200, 409, 409]
    p, logs = await snapshot(pid)
    assert p.cases_solved == 1 and p.stars_total == 3 and p.stats["case_solved"] == 1
    assert p.xp == eco.XP_CASE[3] + eco.XP_DAILY_BONUS + sum(
        a.xp for a in achievements.ALL if f"achievement:{a.id}" in {l.reason for l in logs})
    assert len([l for l in logs if l.reason == f"solve:{tonight.id}"]) == 1
    assert len({l.reason for l in logs}) == len(logs)
    ledger(logs, 200, p.coins)


async def test_mission_chest_claim_once(client, monkeypatch):
    pid, h = await account(200)
    picked = [missions.BY_ID["daily_case"]]
    monkeypatch.setattr(missions, "for_day", lambda day: picked)
    async with db.SessionLocal() as s:
        s.add(MissionDay(player_id=pid, day=content.mission_day_str(), counts={picked[0].event: picked[0].target}))
        await s.commit()
    responses = await together(*(client.post("/v1/missions/claim", headers=h) for _ in range(3)))
    assert sorted(r.status_code for r in responses) == [200, 409, 409]
    p, logs = await snapshot(pid)
    assert p.chests == 1 and p.chest_streak == 1 and p.stats["chest"] == 1
    assert len([l for l in logs if l.reason.startswith("chest:")]) == 1
    ledger(logs, 200, p.coins)


async def test_secure_account_requests_pay_once(client):
    pid, h = await account(200)
    body = {"email": "wallet@example.com", "password": "test-password-123"}
    responses = await together(*(client.post("/v1/auth/email", headers=h, json=body) for _ in range(2)))
    assert all(r.status_code == 200 for r in responses)
    p, logs = await snapshot(pid)
    assert p.secure_rewarded and p.coins == 200 + eco.SECURE_REWARD
    assert len(logs) == 1
    ledger(logs, 200, p.coins)


async def test_invite_redeem_once(client):
    inviter, _ = await account(200)
    pid, h = await account(200)
    responses = await together(*(client.post("/v1/referrals/redeem", headers=h, json={"code": "CODE0"}) for _ in range(2)))
    assert sorted(r.status_code for r in responses) == [200, 409]
    p, logs = await snapshot(pid)
    assert p.referred_by == inviter and p.coins == 200 + eco.INVITE_NEW_PLAYER and len(logs) == 1


async def test_referral_workers_keep_slots_and_inviter_counter():
    inviter, _ = await account(200)
    invitees = []
    for i in range(2):
        pid, _ = await account(200, referred_by=inviter)
        invitees.append(pid)
        async with db.SessionLocal() as s:
            for n in range(eco.INVITE_MIN_DAYS):
                s.add(CaseProgress(player_id=pid, case_id=f"c{n:03}", day=f"2026-10-{n+1:02}", solved=True))
            await s.commit()
    assert await together(*(anticheat.maybe_pay_referral(pid) for pid in invitees)) == [True, True]
    assert await together(*(anticheat.maybe_pay_referral(pid) for pid in invitees)) == [False, False]
    async with db.SessionLocal() as s:
        p = await s.get(Player, inviter)
        assert p.invites_rewarded == 2
        assert sorted((await s.scalars(select(ReferralPayout.slot))).all()) == [1, 2]
        assert await s.scalar(select(func.count()).select_from(InboxItem)) == 2


async def test_unrelated_accounts_are_not_globally_locked():
    a, _ = await account(200)
    b, _ = await account(200)
    async with db.SessionLocal() as first:
        await db.lock_players(first, [a])
        async def other():
            async with db.SessionLocal() as second:
                p = (await db.lock_players(second, [b]))[b]
                await add_coins(second, p, 10, "independent")
                await second.commit()
        await asyncio.wait_for(other(), 5)  # completes while first still holds its row lock
        await first.rollback()


async def test_phone_verification_reacquires_lock_after_otp_commit(client, monkeypatch):
    from app.routers import phone
    pid, h = await account(200)
    barrier = asyncio.Barrier(2)
    async def checked(session, *args):
        await session.commit()  # real OTP checking deliberately commits too
        await barrier.wait()
    monkeypatch.setattr(phone, "_check", checked)
    responses = await together(*(client.post("/v1/auth/phone/verify", headers=h,
        json={"phone": "09123456789", "code": "123456"}) for _ in range(2)))
    assert all(r.status_code == 200 for r in responses)
    assert sum(r.json()["reward"] for r in responses) == eco.SECURE_REWARD
    p, logs = await snapshot(pid)
    assert p.secure_rewarded and p.phone_hash and p.coins == 200 + eco.SECURE_REWARD
    assert len(logs) == 1


async def test_parallel_ads_respect_daily_cap(client):
    pid, h = await account(200)
    responses = await together(*(client.post("/v1/wallet/ad-reward", headers=h) for _ in range(eco.AD_PER_DAY + 2)))
    assert sum(r.status_code == 200 for r in responses) == eco.AD_PER_DAY
    assert sum(r.status_code == 429 for r in responses) == 2
    p, logs = await snapshot(pid)
    assert p.ad_count == eco.AD_PER_DAY and len(logs) == eco.AD_PER_DAY
    assert p.coins == 200 + eco.AD_PER_DAY * eco.AD_REWARD
    ledger(logs, 200, p.coins)


async def test_parallel_riddle_answers_pay_once(client):
    from app import riddles
    pid, h = await account(200)
    items = (await client.get("/v1/riddles", headers=h)).json()["items"]
    item = next(i for i in items if not i["locked"])
    riddle = next(r for r in riddles.for_day(content.today_str()) if r.id == item["id"])
    responses = await together(*(client.post(f"/v1/riddles/{riddle.id}/answer", headers=h,
        json={"choice": riddle.answer, "seconds": 30}) for _ in range(2)))
    assert sorted(r.status_code for r in responses) == [200, 409]
    p, logs = await snapshot(pid)
    assert p.stats["riddle_correct"] == 1
    assert len([l for l in logs if l.reason == f"riddle:{riddle.id}"]) == 1
    ledger(logs, 200, p.coins)


async def test_weekly_settlement_refreshes_stats_after_concurrent_player_update(monkeypatch):
    from datetime import date
    from types import SimpleNamespace
    from app import rewards, weekboard
    pid, _ = await account(200)
    loaded = asyncio.Event()
    resume = asyncio.Event()
    async def standings(session, *args, **kwargs):
        player = await session.get(Player, pid)
        loaded.set()
        await resume.wait()  # settlement holds a stale stats snapshot while another request updates it
        return [SimpleNamespace(player=player, cases=weekboard.MIN_CASES_FOR_PRIZE, points=100)]
    monkeypatch.setattr(weekboard, "standings", standings)
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    async def settle():
        async with db.SessionLocal() as session:
            return await rewards.settle_week(session, date(2026, 10, 16))
    task = asyncio.create_task(settle())
    try:
        await asyncio.wait_for(loaded.wait(), 5)
        async with db.SessionLocal() as session:
            p = (await db.lock_players(session, [pid]))[pid]
            p.stats = {"parallel_progress": 1}
            await session.commit()
        resume.set()
        assert await asyncio.wait_for(task, 10) == 1
    finally:
        resume.set()
        if not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
    p, _ = await snapshot(pid)
    assert p.stats == {"parallel_progress": 1, "weekly_top3": 1}
    async with db.SessionLocal() as session:
        assert await rewards.settle_week(session, date(2026, 10, 16)) == 0
        assert await session.scalar(select(func.count()).select_from(InboxItem)) == 1
