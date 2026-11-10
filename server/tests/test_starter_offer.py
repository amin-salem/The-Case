"""Starter-pack funnel in the admin economy report (events from the app) and the `suspect_count` field of the case list."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Event, Player
from app.services import economy_report as er

from .conftest import ADMIN, new_player, private_engine

NOW = datetime(2026, 11, 10, 12, 0)


@pytest.fixture
async def session(tmp_path):
    engine = await private_engine(tmp_path, "starter")
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


def player(s, n, device=None, banned=False):
    s.add(Player(id=f"p{n}", secret_hash="x", device_id=device or f"dev-{n}", invite_code=f"CODE{n}", nickname=f"nick{n}",
                 banned=banned, created_at=NOW - timedelta(days=9), last_seen=NOW))


def ev(s, n, name, moment=None, days=1):
    s.add(Event(player_id=f"p{n}", name=name, props={"moment": moment} if moment else {}, ts=NOW - timedelta(days=days)))


async def test_funnel_counts_players_and_splits_by_moment(session):
    for n in (1, 2, 3):
        player(session, n)
    player(session, 4, device="smoke-x")
    player(session, 5, banned=True)
    await session.flush()
    ev(session, 1, "starter_offer_shown", "lack_coins")
    ev(session, 1, "starter_offer_tapped", "lack_coins")
    ev(session, 1, "starter_offer_bought", "lack_coins")
    ev(session, 2, "starter_offer_shown", "first_solve")
    ev(session, 2, "starter_offer_shown", "lack_coins")          # the second and last showing of this account
    ev(session, 2, "starter_offer_closed", "first_solve")
    ev(session, 3, "starter_offer_shown", "weird")                # an unknown moment is folded into «other»
    ev(session, 3, "starter_offer_shown", "lack_coins", days=40)  # outside the window
    ev(session, 4, "starter_offer_shown", "lack_coins")           # smoke player: ignored
    ev(session, 5, "starter_offer_bought", "lack_coins")          # banned: ignored
    ev(session, 1, "something_else")                              # other events never count
    await session.commit()
    d = await er.build(session, 14, now=NOW)
    so = d["starter_offer"]
    assert so["shown"] == 4 and so["shown_players"] == 3
    assert so["tapped"] == 1 and so["tapped_players"] == 1 and so["bought"] == 1 and so["closed"] == 1
    assert so["tapped_pct"] == 33.3 and so["bought_pct"] == 33.3
    assert so["by_moment"]["lack_coins"]["shown"] == 2 and so["by_moment"]["first_solve"]["shown"] == 1
    assert so["by_moment"]["other"]["shown"] == 1
    assert "p1" not in str(so) and "nick" not in str(so)


async def test_funnel_is_empty_not_broken_without_events(session):
    d = await er.build(session, 7, now=NOW)
    so = d["starter_offer"]
    assert so["shown"] == 0 and so["bought"] == 0 and so["tapped_pct"] is None and so["by_moment"] == {}


async def test_app_events_endpoint_stores_starter_events(client):
    p = await new_player(client, "starter-ev")
    r = await client.post("/v1/events", headers=p["headers"], json={"events": [
        {"name": "starter_offer_shown", "props": {"moment": "first_solve", "n": 1}}]})
    assert r.status_code == 200 and r.json()["stored"] == 1


async def test_case_list_carries_suspect_count(client):
    p = await new_player(client, "starter-list")
    r = await client.get("/v1/cases", headers=p["headers"])
    assert r.status_code == 200
    rows = ([r.json()["today"]] if r.json().get("today") else []) + r.json()["archive"]
    assert rows and all(isinstance(x["suspect_count"], int) and x["suspect_count"] >= 3 for x in rows)


async def test_admin_page_shows_the_starter_line(client):
    page = (await client.get("/admin/ui")).text
    assert "starter_offer" in page and "بسته‌ی شروع" in page
    r = await client.get("/admin/api/economy?days=7", headers=ADMIN)
    assert r.status_code == 200 and "starter_offer" in r.json()
