"""Admin purge of worthless accounts (app/services/purge.py). Runs on SQLite and PostgreSQL (private database each)."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import CaseComment, CaseProgress, CoinLog, Event, NicknameClaim, Player, Purchase
from app.services import purge

from .conftest import ADMIN, new_player, private_engine

NOW = datetime(2026, 11, 1, 12, 0)


@pytest.fixture
async def session(tmp_path, monkeypatch):
    monkeypatch.setattr(purge, "utcnow", lambda: NOW)
    engine = await private_engine(tmp_path, "purge")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


_n = 0


def add(s, device=None, created=30, seen=30, **kw):
    global _n
    _n += 1
    f = dict(id=f"pg{_n:05d}x", secret_hash="x", device_id=device or f"dev{_n}", invite_code=f"PG{_n:06d}", nickname=f"n{_n}",
             coins=100, created_at=NOW - timedelta(days=created), last_seen=NOW - timedelta(days=seen))
    f.update(kw)
    s.add(Player(**f))
    return f["id"]


async def candidates(s):
    await s.flush()
    return {i["id"]: i["reason"] for i in (await purge.preview(s))["items"]}


async def test_empty_database(session):
    r = await purge.preview(session)
    assert r["total"] == 0 and r["items"] == []
    assert (await purge.apply(session, None)) == {"ok": True, "deleted": 0, "skipped": 0}


async def test_abandoned_guest_is_a_candidate_but_a_young_or_recent_one_is_not(session):
    old = add(session)
    young = add(session, created=3, seen=3)
    recent = add(session, created=30, seen=2)
    c = await candidates(session)
    assert c == {old: "abandoned"} and young not in c and recent not in c


@pytest.mark.parametrize("field,value", [
    ("email", "a@b.com"), ("phone_hash", "h1"), ("tester", True), ("banned", True), ("cases_solved", 1), ("stars_total", 3),
    ("xp", 5), ("streak", 1), ("best_streak", 2), ("warrants", 1), ("no_ads", True), ("vip_until", NOW), ("coins", 101),
    ("referred_by", "someone")])
async def test_anything_of_value_protects_the_row(session, field, value):
    add(session, **{field: value})
    assert await candidates(session) == {}


async def test_progress_purchase_comment_and_inviting_protect_the_row(session):
    a = add(session); b = add(session); c = add(session); d = add(session); inv = add(session)
    add(session, referred_by=inv, created=3, seen=3)
    await session.flush()
    session.add(CaseProgress(player_id=a, case_id="c001"))
    session.add(Purchase(player_id=b, product_id="coins_100", purchase_token="pt1", status="granted"))
    session.add(CaseComment(case_id="c001", player_id=c, rating=5, body="x"))
    await session.flush()
    assert await candidates(session) == {d: "abandoned"}  # a, b, c did something; inv invited someone


async def test_orphan_guest_of_a_secured_account(session):
    owner = add(session, device="shared", email="o@x.com", cases_solved=5, created=40, seen=0)
    orphan = add(session, device="shared", created=5, seen=5)
    fresh_orphan = add(session, device="shared", created=0, seen=0)
    played = add(session, device="shared", created=5, seen=5, cases_solved=1)
    c = await candidates(session)
    assert c == {orphan: "orphan"} and owner not in c and fresh_orphan not in c and played not in c


async def test_smoke_rows_are_candidates_unless_they_are_new_or_testers(session):
    smoke = add(session, device="smoke-load-1-1", created=3, seen=3, coins=900, xp=40)
    add(session, device="smoke-load-1-2", created=0, seen=0)
    add(session, device="smoke-load-1-3", created=3, seen=3, tester=True)
    assert await candidates(session) == {smoke: "smoke"}


async def test_apply_deletes_dependents_and_skips_ids_that_no_longer_qualify(session):
    gone = add(session)
    keeper = add(session, cases_solved=2)  # sent by a stale panel: must be skipped
    await session.flush()
    session.add_all([CoinLog(player_id=gone, amount=100, reason="welcome", balance=100),
                     Event(player_id=gone, name="app_open", props={}),
                     NicknameClaim(key="k-gone", player_id=gone)])
    await session.flush()
    r = await purge.apply(session, [gone, keeper, "nope"])
    assert r == {"ok": True, "deleted": 1, "skipped": 2}
    assert await session.get(Player, gone) is None and await session.get(Player, keeper) is not None
    for m in (CoinLog, Event, NicknameClaim):
        assert await session.scalar(select(func.count()).select_from(m).where(m.player_id == gone)) == 0


async def test_apply_without_ids_is_bounded_to_one_batch(session, monkeypatch):
    monkeypatch.setattr(purge, "MAX_BATCH", 5)
    for _ in range(8):
        add(session)
    await session.flush()
    assert (await purge.apply(session, None))["deleted"] == 5
    assert (await purge.preview(session))["total"] == 3


async def test_admin_api_needs_key_and_confirm_and_a_deleted_login_is_refused(client, monkeypatch):
    p = await new_player(client, "purge-api-1")
    pid = p["player_id"]
    assert (await client.get("/admin/api/purge-preview")).status_code == 403
    assert (await client.post("/admin/api/purge", json={"confirm": True})).status_code == 403
    assert (await client.post("/admin/api/purge", headers=ADMIN, json={"ids": [pid]})).status_code == 422  # no confirm
    # a brand-new guest is far too young: never deleted
    r = await client.post("/admin/api/purge", headers=ADMIN, json={"ids": [pid], "confirm": True})
    assert r.json() == {"ok": True, "deleted": 0, "skipped": 1}
    # make it old and worthless, then it goes and the old secret is refused like a moved account
    from app import db
    async with db.SessionLocal() as s:
        row = await s.get(Player, pid)
        row.created_at = datetime(2020, 1, 1)
        row.last_seen = datetime(2020, 1, 1)
        await s.commit()
    pv = (await client.get("/admin/api/purge-preview", headers=ADMIN)).json()
    assert pid in [i["id"] for i in pv["items"]]
    r = await client.post("/admin/api/purge", headers=ADMIN, json={"ids": [pid], "confirm": True})
    assert r.json()["deleted"] == 1
    login = await client.post("/v1/auth/login", json={"player_id": pid, "secret": p["secret"], "app_version": 1})
    assert login.status_code == 401 and login.json()["detail"] == "wrong_login"
    log = (await client.get("/admin/api/log", headers=ADMIN)).json()
    assert log[0]["action"] == "purge_players"
