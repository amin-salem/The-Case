"""Admin «حساب‌های تکراری» (app/services/duplicates.py): read-only, runs on SQLite and on PostgreSQL (CI job server-postgres).
Each test has a private empty database."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Player, Purchase
from app.services import duplicates as dup

from .conftest import private_engine

NOW = datetime(2026, 10, 28, 12, 0)


@pytest.fixture
async def session(tmp_path):
    engine = await private_engine(tmp_path, "dups")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


_n = 0


def add(s, device, secured=False, phone=False, solved=0, coins=0, banned=False, tester=False, age=1, nick=None):
    global _n
    _n += 1
    s.add(Player(id=f"dp{_n:05d}x", secret_hash="x", device_id=device, invite_code=f"DC{_n:06d}", nickname=nick or f"nick{_n}",
                 email=f"u{_n}@example.com" if secured else None,
                 phone_hash=f"hash{_n}" if phone else None, phone_last4="1234" if phone else None,
                 cases_solved=solved, coins=coins, banned=banned, tester=tester,
                 created_at=NOW - timedelta(days=age), last_seen=NOW - timedelta(hours=age)))
    return f"dp{_n:05d}x"


async def test_empty_database(session):
    r = await dup.groups(session)
    assert r["groups"] == []
    assert r["summary"] == {"players": 0, "devices": 0, "groups": 0, "rows_in_groups": 0,
                            "probable_orphans": 0, "real_people_estimate": 0, "hidden": 0}


async def test_groups_and_orphan_detection(session):
    # one person: secured account + two orphan guests on the same device
    sec = add(session, "dev-A", secured=True, solved=7, coins=300)
    o1 = add(session, "dev-A")
    o2 = add(session, "dev-A", coins=100)
    # a guest who played does not count as an orphan; nor does one who bought coins
    played = add(session, "dev-A", solved=2)
    # two guests on one device and no secured row: shared device, but nobody to be an orphan of
    add(session, "dev-B")
    add(session, "dev-B")
    # a phone-secured account counts as secured
    ph = add(session, "dev-C", phone=True, solved=1)
    o3 = add(session, "dev-C")
    # alone on the device: not a group
    add(session, "dev-D", secured=True)
    await session.flush()
    bought = add(session, "dev-C")
    await session.flush()
    session.add(Purchase(player_id=bought, product_id="coins_small", purchase_token="tok-1", status="granted"))
    await session.commit()

    r = await dup.groups(session)
    s = r["summary"]
    assert s["players"] == 10 and s["devices"] == 4 and s["groups"] == 3 and s["rows_in_groups"] == 9
    assert s["probable_orphans"] == 3  # o1, o2, o3
    assert s["real_people_estimate"] == 7
    assert [g["rows"] for g in r["groups"]] == [4, 3, 2]  # biggest group first
    a = r["groups"][0]
    assert a["device"].endswith("…")
    roles = {p["id"]: p["role"] for p in a["players"]}
    assert roles == {sec: "secured", o1: "orphan", o2: "orphan", played: "guest"}
    assert a["players"][0]["id"] == sec  # the secured row comes first
    c = {p["id"]: p for p in r["groups"][1]["players"]}
    assert c[ph]["role"] == "secured" and c[ph]["phone_last4"] == "1234"
    assert c[o3]["role"] == "orphan" and c[bought]["role"] == "guest" and c[bought]["purchases"] == 1
    # nothing personal beyond the player page: no email text, no full device id, no phone hash
    text = str(r)
    assert "@example.com" not in text and "hash" not in text and "device_id" not in text


async def test_banned_and_tester_rows_are_never_probable_orphans(session):
    add(session, "dev-X", secured=True)
    add(session, "dev-X", banned=True)
    add(session, "dev-X", tester=True)
    add(session, "dev-X")
    await session.commit()
    r = await dup.groups(session)
    assert r["summary"]["probable_orphans"] == 1
    roles = sorted(p["role"] for p in r["groups"][0]["players"])
    assert roles == ["guest", "guest", "orphan", "secured"]
    flags = {(p["banned"], p["tester"]) for p in r["groups"][0]["players"]}
    assert (True, False) in flags and (False, True) in flags


async def test_group_list_is_bounded_and_paged(session):
    for i in range(dup.MAX_GROUPS + 5):
        add(session, f"dev-many-{i:04d}", secured=True)
        add(session, f"dev-many-{i:04d}")
    await session.commit()
    r = await dup.groups(session, limit=500)  # asking for more than the cap is cut to it
    assert len(r["groups"]) == dup.MAX_GROUPS
    assert r["summary"]["groups"] == dup.MAX_GROUPS + 5  # the numbers still count everything
    assert r["summary"]["probable_orphans"] == dup.MAX_GROUPS + 5
    page = await dup.groups(session, limit=50, offset=150)
    assert len(page["groups"]) == 50
    beyond = await dup.groups(session, limit=50, offset=dup.MAX_GROUPS)
    assert beyond["groups"] == []


async def test_rows_of_one_device_are_cut(session, monkeypatch):
    monkeypatch.setattr(dup, "MAX_ROWS", 5)
    for _ in range(9):
        add(session, "dev-big")
    await session.commit()
    r = await dup.groups(session)
    g = r["groups"][0]
    assert g["rows"] == 9 and g["shown"] == 5


async def test_admin_api_needs_the_key_and_reads(client):
    from .conftest import ADMIN
    assert (await client.get("/admin/api/duplicate-accounts")).status_code == 403
    assert (await client.get("/admin/api/duplicate-accounts/summary")).status_code == 403
    r = await client.get("/admin/api/duplicate-accounts?limit=10", headers=ADMIN)
    assert r.status_code == 200 and set(r.json()) == {"summary", "groups", "max_groups"}
    assert (await client.get("/admin/api/duplicate-accounts?limit=201", headers=ADMIN)).status_code == 422
    s = (await client.get("/admin/api/duplicate-accounts/summary", headers=ADMIN)).json()
    assert s["real_people_estimate"] == s["players"] - s["probable_orphans"]
    page = await client.get("/admin/ui")
    assert "حساب‌های تکراری" in page.text and "duplicate-accounts" in page.text
