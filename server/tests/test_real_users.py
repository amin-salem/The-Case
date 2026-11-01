"""Admin «کاربر واقعی» (app/services/real_users.py): read-only, runs on SQLite and on PostgreSQL.
Each test has a private empty database."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import CaseProgress, Player, Purchase
from app.services import real_users as ru

from .conftest import private_engine

NOW = datetime(2026, 11, 1, 12, 0)


@pytest.fixture
async def session(tmp_path, monkeypatch):
    monkeypatch.setattr(ru, "utcnow", lambda: NOW)
    engine = await private_engine(tmp_path, "realusers")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


_n = 0


def add(s, email=None, device=None, solved=0, banned=False, tester=False, created=10, seen=1, phone=False):
    global _n
    _n += 1
    pid = f"ru{_n:05d}x"
    s.add(Player(id=pid, secret_hash="x", device_id=device or f"dev{_n}", invite_code=f"RU{_n:06d}", nickname=f"n{_n}",
                 email=email, phone_hash=f"h{_n}" if phone else None, phone_last4="0030" if phone else None,
                 cases_solved=solved, banned=banned, tester=tester,
                 created_at=NOW - timedelta(days=created), last_seen=NOW - timedelta(days=seen)))
    return pid


async def segs(s):
    from sqlalchemy import select
    await s.flush()
    rows = (await s.scalars(select(Player))).all()
    return {pid: v["segment"] for pid, v in (await ru.label_rows(s, list(rows), await ru.duplicate_ids(s))).items()}


async def test_empty_database(session):
    r = await ru.summary(session)
    assert r["players"] == 0 and r["real"] == 0 and r["duplicate"] == 0 and r["excluded"] == 0


async def test_segments_and_counts(session):
    real = add(session, solved=3, seen=2)
    buyer = add(session)
    tried = add(session)
    await session.flush()  # the players exist before rows that point at them (no ORM relationships here)
    session.add(Purchase(player_id=buyer, product_id="coins_100", purchase_token="tok-ru-1", status="granted"))
    session.add(CaseProgress(player_id=tried, case_id="c001"))
    empty = add(session)
    tester = add(session, solved=5, tester=True)
    banned = add(session, solved=5, banned=True)
    smoke = add(session, device="smoke-load-abc-1")
    await session.flush()
    s = await segs(session)
    assert s[real] == "real" and s[buyer] == "real" and s[tried] == "tried" and s[empty] == "empty"
    assert s[tester] == s[banned] == s[smoke] == "excluded"
    r = await ru.summary(session)
    assert (r["players"], r["real"], r["tried"], r["empty"], r["excluded"], r["duplicate"]) == (7, 2, 1, 1, 3, 0)
    assert r["real_active_7d"] == 2 and r["real_active_30d"] == 2


async def test_mina_case_same_person_new_device_and_email_name(session):
    """Two rows, two different device ids: the old one went quiet two days before the new one was created."""
    old = add(session, email="maryam@example.com", solved=4, created=25, seen=22)
    new = add(session, email="maryamfarzaneh130@gmail.com", solved=10, phone=True, created=20, seen=0)
    await session.flush()
    dup = await ru.duplicate_ids(session)
    assert dup == {old: "email"}
    s = await segs(session)
    assert s[old] == "duplicate" and s[new] == "real"
    r = await ru.summary(session)
    assert r["real"] == 1 and r["duplicate"] == 1 and r["duplicate_email"] == 1


async def test_email_link_needs_the_old_row_to_be_quiet_and_a_long_enough_name(session):
    # both active at the same time: two people (or one with two e-mails in use): not flagged
    a = add(session, email="maryam@example.com", solved=1, created=25, seen=0)
    add(session, email="maryamx@gmail.com", solved=1, created=20, seen=0)
    # a short name never links
    add(session, email="ali@example.com", solved=1, created=30, seen=29)
    add(session, email="alireza@example.com", solved=1, created=28, seen=0)
    # unrelated names
    add(session, email="sara@example.com", solved=1, created=30, seen=29)
    add(session, email="zahra@example.com", solved=1, created=28, seen=0)
    await session.flush()
    assert await ru.duplicate_ids(session) == {}
    assert a


async def test_orphan_guest_on_the_same_device_is_a_duplicate_but_a_guest_who_solved_is_not(session):
    owner = add(session, email="owner1@example.com", device="shared", solved=5)
    orphan = add(session, device="shared", created=0)
    played = add(session, device="shared", solved=2, created=0)
    lone_guest = add(session)
    await session.flush()
    dup = await ru.duplicate_ids(session)
    assert dup == {orphan: "device"} and owner not in dup and played not in dup and lone_guest not in dup


async def test_excluded_rows_are_never_marked_duplicates(session):
    add(session, email="maryam@example.com", created=25, seen=22, tester=True)
    add(session, email="maryamfarzaneh@gmail.com", created=20)
    await session.flush()
    assert await ru.duplicate_ids(session) == {}


async def test_segment_filter_matches_the_summary(session):
    add(session, solved=1)
    add(session, solved=2)
    add(session)
    add(session, tester=True)
    await session.flush()
    from sqlalchemy import func, select
    dup = list(await ru.duplicate_ids(session))
    r = await ru.summary(session)
    for seg in ru.SEGMENTS:
        n = await session.scalar(select(func.count()).select_from(Player).where(ru.where_segment(seg, dup)))
        assert n == r[seg], seg


async def test_admin_api_needs_the_key_and_lists_segments(client):
    from .conftest import ADMIN, new_player
    assert (await client.get("/admin/api/real-users")).status_code == 403
    await new_player(client, "ru-api-1")
    s = (await client.get("/admin/api/real-users", headers=ADMIN)).json()
    assert s["players"] >= 1 and s["empty"] >= 1
    lst = (await client.get("/admin/api/players?segment=empty", headers=ADMIN)).json()
    assert lst["total"] >= 1 and all(i["segment"] == "empty" for i in lst["items"])
    assert (await client.get("/admin/api/players?segment=bad", headers=ADMIN)).status_code == 422
    real = (await client.get("/admin/api/players?segment=real", headers=ADMIN)).json()
    assert real["total"] == s["real"]
