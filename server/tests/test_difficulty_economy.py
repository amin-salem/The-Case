"""Server-authoritative quotes/rewards. Cross-worker atomicity comes from fix/wallet-atomic, not copied here."""
import copy
from datetime import timedelta

import pytest
from sqlalchemy import select, update

from app import content, db, economy as eco
from app.models import CaseProgress, CoinLog, Player, utcnow
from .conftest import new_player

NORMAL = {1: [6, 8, 10, 12, 15], 2: [12, 16, 20, 24, 30], 3: [20, 25, 30, 36, 45]}
WEEKEND = {1: [72, 96, 120, 144, 180], 2: [120, 160, 200, 240, 300], 3: [200, 250, 300, 360, 450]}


@pytest.mark.parametrize("difficulty", range(1, 6))
@pytest.mark.parametrize("stars", [1, 2, 3])
def test_full_reward_and_price_policy(difficulty, stars):
    assert eco.solve_reward(difficulty, stars) == NORMAL[stars][difficulty - 1]
    assert eco.solve_reward(difficulty, stars, live_weekend=True) == WEEKEND[stars][difficulty - 1]
    assert eco.archive_unlock_cost(difficulty) == [100, 120, 150, 180, 220][difficulty - 1]
    assert eco.archive_unlock_cost(difficulty, weekend=True) == [170, 200, 250, 300, 370][difficulty - 1]


@pytest.mark.parametrize("bad", [None, 0, -1, 6, True, "5", 2.5, [], {}])
def test_missing_invalid_difficulty_has_one_consistent_fallback(bad):
    assert eco.archive_unlock_cost(bad) == 150
    assert eco.archive_unlock_cost(bad, weekend=True) == 250
    for stars in (1, 2, 3):
        assert eco.solve_reward(bad, stars) == eco.SOLVE_REWARD[stars]
        assert eco.solve_reward(bad, stars, live_weekend=True) == eco.WEEKLY_REWARD[stars]


def changed(case, difficulty):
    data = copy.deepcopy(case.data)
    data["difficulty"] = difficulty
    return content.Case(case.id, case.number, case.publish, data)


async def fund(pid, amount=2000):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(coins=amount))
        await s.commit()


async def balance(pid):
    async with db.SessionLocal() as s:
        return (await s.get(Player, pid)).coins


@pytest.mark.parametrize("difficulty", range(1, 6))
async def test_archive_quote_debit_insufficient_funds_ownership_and_legacy(client, monkeypatch, difficulty):
    c = changed(content.by_id("c020"), difficulty)
    tomorrow = content.by_id("c021")
    monkeypatch.setattr(content, "all_cases", lambda: (c, tomorrow))
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    p = await new_player(client, f"quote-{difficulty}")
    h = p["headers"]
    row = next(r for r in (await client.get('/v1/cases', headers=h)).json()['archive'] if r['id'] == c.id)
    cost = [100, 120, 150, 180, 220][difficulty - 1]
    assert row['unlock_cost'] == cost and row['locked']
    assert row['base_solve_rewards'] == {str(s): NORMAL[s][difficulty - 1] for s in (1, 2, 3)}
    await fund(p['player_id'])
    refused = await client.post(f'/v1/cases/{c.id}/unlock', headers=h, json={'expected_cost': cost - 1})
    assert refused.status_code == 409 and refused.json()['detail'] == {'error': 'price_changed', 'cost': cost}
    assert await balance(p['player_id']) == 2000
    await fund(p['player_id'], cost - 1)
    refused = await client.post(f'/v1/cases/{c.id}/unlock', headers=h, json={'expected_cost': cost})
    assert refused.status_code == 402 and refused.json()['detail']['need'] == cost
    assert await balance(p['player_id']) == cost - 1
    await fund(p['player_id'])
    got = await client.post(f'/v1/cases/{c.id}/unlock', headers=h, json={'expected_cost': row['unlock_cost']})
    assert got.status_code == 200, got.text
    assert await balance(p['player_id']) == 2000 - cost
    # Already owned bypasses charging/quote negotiation even if a later content edit changes the price.
    c.data['difficulty'] = 5
    for body in ({'expected_cost': 1}, None):
        assert (await client.post(f'/v1/cases/{c.id}/unlock', headers=h, json=body)).status_code == 200
    assert await balance(p['player_id']) == 2000 - cost
    async with db.SessionLocal() as s:
        logs = (await s.scalars(select(CoinLog).where(CoinLog.player_id == p['player_id'], CoinLog.reason == f'unlock:{c.id}'))).all()
        assert len(logs) == 1 and logs[0].amount == -cost
    # Old clients send no body: their existing flow still works at the server's current price.
    old = await new_player(client, f'legacy-quote-{difficulty}')
    await fund(old['player_id'])
    assert (await client.post(f'/v1/cases/{c.id}/unlock', headers=old['headers'])).status_code == 200
    assert await balance(old['player_id']) == 1780


async def test_vip_and_tonights_free_access_never_charge(client, monkeypatch):
    c = changed(content.by_id('c020'), 5)
    tomorrow = content.by_id('c021')
    monkeypatch.setattr(content, 'all_cases', lambda: (c, tomorrow))
    monkeypatch.setattr(content, 'now_local', lambda: content.opens_at(c) + timedelta(hours=1))
    p = await new_player(client, 'economy-free')
    assert (await client.post(f'/v1/cases/{c.id}/unlock', headers=p['headers'], json={'expected_cost': 1})).status_code == 200
    assert await balance(p['player_id']) == eco.START_COINS
    monkeypatch.setattr(content, 'now_local', lambda: content.opens_at(tomorrow) + timedelta(hours=1))
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p['player_id']).values(vip_until=utcnow() + timedelta(days=1)))
        await s.commit()
    assert (await client.post(f'/v1/cases/{c.id}/unlock', headers=p['headers'], json={'expected_cost': 1})).status_code == 200
    assert await balance(p['player_id']) == eco.START_COINS


@pytest.mark.parametrize('difficulty', range(1, 6))
@pytest.mark.parametrize('stars', [1, 2, 3])
async def test_nightly_reward_bonus_and_repeat_solve(client, monkeypatch, difficulty, stars):
    c = changed(content.by_id('c020'), difficulty)
    monkeypatch.setattr(content, 'all_cases', lambda: (c,))
    monkeypatch.setattr(content, 'now_local', lambda: content.opens_at(c) + timedelta(hours=1))
    p = await new_player(client, f'reward-{difficulty}-{stars}')
    await client.get(f'/v1/cases/{c.id}', headers=p['headers'])
    async with db.SessionLocal() as s:
        await s.execute(update(CaseProgress).where(CaseProgress.player_id == p['player_id']).values(attempts=3-stars))
        await s.commit()
    body = {'suspect': c.culprit, 'evidence': sorted(c.proof)[0]}
    r = await client.post(f'/v1/cases/{c.id}/accuse', headers=p['headers'], json=body)
    assert r.status_code == 200, r.text
    assert r.json()['stars'] == stars and r.json()['reward'] == NORMAL[stars][difficulty-1] + eco.DAILY_BONUS
    before = await balance(p['player_id'])
    assert (await client.post(f'/v1/cases/{c.id}/accuse', headers=p['headers'], json=body)).status_code == 409
    assert await balance(p['player_id']) == before
    async with db.SessionLocal() as s:
        logs = (await s.scalars(select(CoinLog).where(CoinLog.player_id == p['player_id'], CoinLog.reason == f'solve:{c.id}'))).all()
        assert len(logs) == 1 and logs[0].amount == r.json()['reward']


@pytest.mark.parametrize('difficulty', range(1, 6))
@pytest.mark.parametrize('stars', [1, 2, 3])
@pytest.mark.parametrize('expired', [False, True])
async def test_live_and_expired_weekend_keep_distinct_baselines(client, monkeypatch, difficulty, stars, expired):
    c = changed(content.weekly_cases()[0], difficulty)
    monkeypatch.setattr(content, 'weekly_cases', lambda: (c,))
    now = content.weekly_closes_at(c) + timedelta(seconds=1) if expired else content.weekly_all_open_at(c)
    monkeypatch.setattr(content, 'now_local', lambda: now)
    p = await new_player(client, f'weekend-{difficulty}-{stars}-{expired}')
    await fund(p['player_id'])
    if expired:
        row = next(r for r in (await client.get('/v1/cases', headers=p['headers'])).json()['archive'] if r['id'] == c.id)
        assert row['unlock_cost'] == [170, 200, 250, 300, 370][difficulty-1]
        assert (await client.post(f'/v1/cases/{c.id}/unlock', headers=p['headers'], json={'expected_cost': row['unlock_cost']})).status_code == 200
    else:
        assert (await client.get(f'/v1/cases/{c.id}', headers=p['headers'])).status_code == 200
    async with db.SessionLocal() as s:
        await s.execute(update(CaseProgress).where(CaseProgress.player_id == p['player_id']).values(attempts=3-stars))
        await s.commit()
    body = {'suspect': c.culprit, 'evidence': sorted(c.proof)[0], 'motive': c.data['solution']['motive']}
    r = await client.post(f'/v1/cases/{c.id}/accuse', headers=p['headers'], json=body)
    assert r.status_code == 200, r.text
    expected = (NORMAL if expired else WEEKEND)[stars][difficulty-1]
    assert r.json()['reward'] == expected and r.json()['stars'] == stars and r.json()['early_bonus'] == 0


async def test_streak_and_early_weekend_bonuses_are_added_not_scaled(client, monkeypatch):
    cases = content.all_cases()
    c = changed(content.by_id('c020'), 5)
    previous = content.by_id('c019')
    monkeypatch.setattr(content, 'all_cases', lambda: tuple(c if x.id == c.id else x for x in cases))
    monkeypatch.setattr(content, 'now_local', lambda: content.opens_at(c) + timedelta(hours=1))
    p = await new_player(client, 'bonus-unscaled')
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p['player_id']).values(streak=6, best_streak=6, last_daily_solved=previous.publish.isoformat()))
        await s.commit()
    await client.get(f'/v1/cases/{c.id}', headers=p['headers'])
    r = (await client.post(f'/v1/cases/{c.id}/accuse', headers=p['headers'], json={'suspect': c.culprit, 'evidence': sorted(c.proof)[0]})).json()
    assert r['reward'] == 45 + eco.DAILY_BONUS + eco.STREAK_BONUS
    w = changed(content.weekly_cases()[0], 5)
    monkeypatch.setattr(content, 'weekly_cases', lambda: (w,))
    monkeypatch.setattr(content, 'now_local', lambda: content.opens_at(w) + timedelta(hours=1))
    b = await new_player(client, 'early-unscaled')
    await client.get(f'/v1/cases/{w.id}', headers=b['headers'])
    result = (await client.post(f'/v1/cases/{w.id}/accuse', headers=b['headers'], json={
        'suspect': w.culprit, 'evidence': sorted(w.proof)[0], 'motive': w.data['solution']['motive']})).json()
    assert result['reward'] == 450 + eco.WEEKLY_EARLY_BONUS and result['early_bonus'] == eco.WEEKLY_EARLY_BONUS
