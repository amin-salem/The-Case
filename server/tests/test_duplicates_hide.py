"""Hide / restore / delete for good (Amin, 15 Nov 2026). SQLite and PostgreSQL (job server-postgres); private databases."""
from datetime import timedelta

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker

from app import anticheat as ac
from app.models import AdminLog, CaseProgress, Player, Purchase, utcnow
from app.services import duplicates as dup

from .conftest import ADMIN, new_player, private_engine
from .test_duplicates import add


@pytest.fixture
async def session(tmp_path):
    engine = await private_engine(tmp_path, "duph")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


async def count(s, *where):
    return int(await s.scalar(select(func.count()).select_from(Player).where(*where)) or 0)


async def test_hide_keeps_the_last_row_a_secured_row_and_a_buyer(session):
    sec = add(session, "dev-A", secured=True, solved=7)
    g1 = add(session, "dev-A")
    g2 = add(session, "dev-A", solved=2)
    buyer = add(session, "dev-A")
    session.add(Purchase(player_id=buyer, product_id="coins_100", status="granted", purchase_token="t1"))
    await session.flush()
    r = await dup.hide(session, [sec, g1, g2, buyer])
    assert r == {"ok": True, "hidden": 2, "skipped": 2}            # the secured row and the buyer stay
    assert await count(session, Player.hidden_at.is_not(None)) == 2
    assert (await session.get(Player, sec)).hidden_at is None and (await session.get(Player, buyer)).hidden_at is None
    # two guests, nobody secured: only one may go, the device keeps a row
    a = add(session, "dev-B")
    b = add(session, "dev-B")
    await session.flush()
    r = await dup.hide(session, [a, b])
    assert r["hidden"] == 1 and r["skipped"] == 1
    assert await count(session, Player.device_id == "dev-B", Player.hidden_at.is_(None)) == 1
    # hiding twice does nothing
    assert (await dup.hide(session, [g1]))["hidden"] == 0
    log = (await session.scalars(select(AdminLog.action))).all()
    assert log.count("hide_duplicates") == 2


async def test_hidden_rows_leave_the_groups_the_boards_and_the_counts(session):
    sec = add(session, "dev-A", secured=True)
    g1 = add(session, "dev-A")
    add(session, "dev-C")
    await session.flush()
    before = await dup.groups(session)
    assert before["summary"]["groups"] == 1 and before["groups"][0]["players"][0]["keep"] is True
    assert [i["can_hide"] for i in before["groups"][0]["players"]] == [False, True]
    await dup.hide(session, [g1])
    after = await dup.groups(session)
    assert after["summary"]["groups"] == 0 and after["summary"]["hidden"] == 1 and after["groups"] == []
    assert ac.is_visible(await session.get(Player, sec)) is True
    assert ac.is_visible(await session.get(Player, g1)) is False
    hid = await dup.hidden_list(session)
    assert [i["id"] for i in hid["items"]] == [g1] and hid["items"][0]["due"] is False


async def test_restore_brings_a_row_back(session):
    add(session, "dev-A", secured=True)
    g1 = add(session, "dev-A")
    await session.flush()
    await dup.hide(session, [g1])
    assert (await dup.restore(session, [g1]))["restored"] == 1
    assert (await session.get(Player, g1)).hidden_at is None
    assert (await dup.groups(session))["summary"]["groups"] == 1


async def test_delete_for_good_only_after_30_days_and_only_if_unused(session):
    add(session, "dev-A", secured=True)
    old_quiet, old_used, fresh = add(session, "dev-A"), add(session, "dev-A"), add(session, "dev-A")
    await session.flush()
    await dup.hide(session, [old_quiet, old_used, fresh])
    now = utcnow()
    for pid, days, seen_days_ago in ((old_quiet, 31, 32), (old_used, 31, 2), (fresh, 5, 6)):
        p = await session.get(Player, pid)
        p.hidden_at = now - timedelta(days=days)
        p.last_seen = now - timedelta(days=seen_days_ago)
    session.add(CaseProgress(player_id=old_quiet, case_id="c001", solved=False))        # rows that hang on it go too
    await session.flush()
    hid = {i["id"]: i for i in (await dup.hidden_list(session))["items"]}
    assert hid[old_quiet]["due"] is True and hid[old_used]["used_since"] is True and hid[old_used]["due"] is False
    r = await dup.purge_expired(session)
    assert r == {"ok": True, "deleted": 1, "kept": 1}
    assert await session.get(Player, old_quiet) is None
    assert await session.get(Player, old_used) is not None and await session.get(Player, fresh) is not None
    assert await session.scalar(select(func.count()).select_from(CaseProgress).where(CaseProgress.player_id == old_quiet)) == 0


async def test_http_endpoints_need_confirm_and_the_key_and_list_member_numbers(client):
    a, b, c = [await new_player(client, f"hide-dev-{i}") for i in range(3)]
    pl = (await client.get("/admin/api/players?sort=created_asc&segment=all", headers=ADMIN)).json()["items"]
    nums = [p["member_no"] for p in pl]
    assert nums[0] == 1 and nums == sorted(nums)                                       # oldest first, numbered from 1
    newest = (await client.get("/admin/api/players?sort=created&segment=all&limit=200", headers=ADMIN)).json()["items"]
    mine = {a["player_id"], b["player_id"], c["player_id"]}
    got = [p["member_no"] for p in newest if p["id"] in mine]                           # other tests share the database: look at mine only
    assert len(got) == 3 and got == sorted(got, reverse=True) and len(set(got)) == 3
    body = {"ids": [b["player_id"]]}
    assert (await client.post("/admin/api/duplicate-accounts/hide", json={**body, "confirm": True})).status_code == 403
    assert (await client.post("/admin/api/duplicate-accounts/hide", headers=ADMIN, json=body)).status_code == 422
    assert (await client.post("/admin/api/duplicate-accounts/purge-hidden", headers=ADMIN, json={})).status_code == 422
    # three different devices: nothing is a duplicate, so nothing is hidden
    r = await client.post("/admin/api/duplicate-accounts/hide", headers=ADMIN, json={**body, "confirm": True})
    assert r.status_code == 200 and r.json()["hidden"] == 0 and r.json()["skipped"] == 1
    assert (await client.get("/admin/api/duplicate-accounts/hidden", headers=ADMIN)).json()["items"] == []
