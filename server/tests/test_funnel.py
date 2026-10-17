"""Admin screen «قیف و ماندگاری» (app/services/funnel.py): seeded data in its own SQLite database, fixed clock, no sleeps."""
import json
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.db import Base
from app.models import CaseProgress, Player, Purchase
from app.services import funnel

from .conftest import ADMIN, new_player

NOW = datetime(2026, 9, 30, 12, 0)  # UTC; 15:30 on 30 Sep in Tehran. Ten days: 21 Sep .. 30 Sep (today is day 9)


def at(day: int, hour: int = 12, minute: int = 0) -> datetime:
    return datetime(2026, 9, day, hour, minute)


@pytest.fixture
async def session(tmp_path):
    """A private database, so rows made by other tests never leak into the numbers."""
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path}/funnel.db")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


def player(s, n, created, seen, coins=0, device=None, banned=False):
    p = Player(id=f"p{n}", secret_hash="x", device_id=device or f"dev-{n}", invite_code=f"CODE{n}",
               nickname=f"nick{n}", coins=coins, banned=banned, created_at=created, last_seen=seen)
    s.add(p)
    return p


def prog(s, pid, case, opened, finished=None, solved=False, failed=False, stars=0, hints=0, active=0):
    s.add(CaseProgress(player_id=f"p{pid}", case_id=case, opened_at=opened, finished_at=finished, solved=solved,
                       failed=failed, stars=stars, hints=hints, active_seconds=active,
                       day=finished.date().isoformat() if finished and solved else ""))


def buy(s, n, pid, product, when, status="granted"):
    s.add(Purchase(player_id=f"p{pid}", product_id=product, purchase_token=f"tok{n}", status=status, created_at=when))


async def seed(s):
    # cohort 21 Sep: A (plays on day 0, 1, 3 and 7), B (fails the first case and leaves), C (never opens a case)
    player(s, "A", at(21), at(24), coins=100)
    player(s, "B", at(21), at(21))
    player(s, "C", at(21), at(21))
    player(s, "F", at(22), at(30, 9), coins=200)             # 22 Sep, seen today, no case
    player(s, "E", at(28), at(29, 13), coins=300)            # 28 Sep, returns the next day
    player(s, "D", at(29), at(30, 10), coins=0)              # 29 Sep, too young for D1
    player(s, "S", at(21), at(30), device="smoke-load-1")    # test accounts are left out of every number
    player(s, "X", at(21), at(30), banned=True)
    await s.flush()
    prog(s, "A", "c001", at(21), at(21, 12, 30), solved=True, stars=3, active=100)
    prog(s, "A", "c002", at(22), at(22, 12, 30), solved=True, stars=2, active=200)
    prog(s, "A", "c003", at(24), at(24, 12, 30), solved=True, stars=1, active=300, hints=2)
    prog(s, "A", "c004", at(28))                              # day 7, never finished
    prog(s, "B", "c001", at(21), at(21, 12, 10), failed=True)
    prog(s, "E", "c001", at(28, 11), at(28, 11, 30), solved=True, stars=3, active=50)
    prog(s, "E", "c002", at(29, 13))                          # opened less than 24 h ago: not "abandoned" yet
    prog(s, "D", "c002", at(29, 10))
    prog(s, "S", "c001", at(21), at(21, 12, 5), solved=True, stars=3, active=5)
    prog(s, "X", "c001", at(21), at(21, 12, 5), failed=True)
    buy(s, 1, "A", "coins_small", at(21, 17))
    buy(s, 2, "B", "starter_pack", at(22, 12))
    buy(s, 3, "C", "coins_medium", at(23), status="rejected")
    buy(s, 4, "S", "coins_large", at(25))
    await s.commit()


async def test_cohorts_funnel_and_retention_with_a_fixed_clock(session):
    await seed(session)
    d = await funnel.build(session, 10, NOW)
    assert d["first_day"] == "2026-09-21" and d["last_day"] == "2026-09-30" and d["days"] == 10
    assert not [k for k, v in d.items() if isinstance(v, dict) and v.get("error")]

    new = {x["day"]: x["new"] for x in d["signups"]["days"]}
    assert new["2026-09-21"] == 3 and new["2026-09-22"] == 1 and new["2026-09-28"] == 1 and new["2026-09-29"] == 1
    assert d["signups"]["total"] == 6                          # smoke and banned accounts are not counted

    t = d["funnel"]["total"]
    assert t == {"registered": 6, "opened": 4, "finished_first": 3, "solved_first": 2, "solved_3_days": 1}
    assert d["funnel"]["pct"]["opened"] == 66.7 and d["funnel"]["pct"]["solved_3_days"] == 16.7
    first = d["funnel"]["days"][0]
    assert first["registered"] == 3 and first["finished_first"] == 2 and first["solved_first"] == 1

    r = d["retention"]
    rows = {x["day"]: x for x in r["days"]}
    assert rows["2026-09-21"]["d1"] == 1 and rows["2026-09-21"]["d3"] == 1 and rows["2026-09-21"]["d7"] == 1
    assert rows["2026-09-28"]["d1"] == 1 and rows["2026-09-28"]["d3"] is None   # too young for D3
    assert rows["2026-09-29"]["d1"] is None                                      # too young for D1
    assert rows["2026-09-22"]["d7"] == 0                                         # 22 Sep + 7 = 29 Sep is over, nobody came
    assert r["total"]["d1"] == {"returned": 2, "of": 5, "pct": 40.0, "cohorts": 8}
    assert r["total"]["d3"] == {"returned": 1, "of": 4, "pct": 25.0, "cohorts": 6}
    assert r["total"]["d7"] == {"returned": 1, "of": 4, "pct": 25.0, "cohorts": 2}
    assert r["active"] == {"players": 6, "dau": 3, "wau": 4, "dau_pct": 50.0, "wau_pct": 66.7, "dau_wau_pct": 75.0}


async def test_where_players_stop_and_which_cases_they_leave(session):
    await seed(session)
    o = (await funnel.build(session, 10, NOW))["drop_off"]
    assert o["stopped"] == 3
    got = {x["key"]: x["players"] for x in o["stages"]}
    assert got == {"never_opened": 1, "opened_not_finished": 0, "finished_1": 1, "finished_2": 0,
                   "finished_3_4": 1, "finished_5_plus": 0}
    assert [(c["case"], c["abandoned"]) for c in o["abandoned_cases"]] == [("c002", 1), ("c004", 1)]


async def test_money_and_coin_quartiles(session):
    await seed(session)
    m = (await funnel.build(session, 10, NOW))["money"]
    assert (m["registered"], m["payers"], m["conversion_pct"]) == (6, 2, 33.3)
    assert (m["d7_retained"], m["d7_retained_payers"], m["d7_conversion_pct"]) == (1, 1, 100.0)
    assert m["first_purchase_median_hours"] == 5.0            # 5 h and 24 h after signup; nearest rank = the lower one
    packs = {p["product"]: p for p in m["packs"]}
    assert packs["coins_small"]["granted"] == 1 and packs["coins_small"]["coins"] == 400
    assert packs["starter_pack"]["coins"] == 1000 and packs["starter_pack"]["no_ads"] is True
    assert packs["coins_medium"]["granted"] == 0 and packs["coins_medium"]["rejected"] == 1
    assert "coins_large" not in packs                          # bought by a smoke account
    assert m["coins"] == {"active_players": 4, "p25": 0.0, "median": 100.0, "p75": 200.0, "zero_pct": 25.0}


async def test_gameplay_quality_overall_and_per_case(session):
    await seed(session)
    q = (await funnel.build(session, 10, NOW))["quality"]
    assert (q["opened"], q["finished"], q["solved"], q["failed"]) == (8, 5, 4, 1)
    assert q["failed_pct"] == 20.0
    assert (q["plaques"]["3_pct"], q["plaques"]["2_pct"], q["plaques"]["1_pct"]) == (50.0, 25.0, 25.0)
    assert q["median_active_seconds"] == 100 and q["avg_hints"] == 0.4
    cases = {c["case"]: c for c in q["cases"]}
    assert [c["case"] for c in q["cases"]][:2] == ["c001", "c002"]
    assert cases["c001"]["opened"] == 3 and cases["c001"]["solved_pct"] == 66.7 and cases["c001"]["failed_pct"] == 33.3
    assert cases["c001"]["median_active_seconds"] == 50 and cases["c002"]["median_active_seconds"] == 200
    assert cases["c001"]["title"]                              # the title comes from the case file


async def test_zero_data_page(session):
    d = await funnel.build(session, 30, NOW)
    assert not [k for k, v in d.items() if isinstance(v, dict) and v.get("error")]
    assert d["signups"]["total"] == 0 and len(d["signups"]["days"]) == 30
    assert d["funnel"]["total"]["registered"] == 0 and d["funnel"]["pct"]["opened"] is None
    assert d["retention"]["total"]["d1"]["pct"] is None and d["retention"]["active"]["dau_wau_pct"] is None
    assert d["drop_off"]["stopped"] == 0 and d["drop_off"]["abandoned_cases"] == []
    assert d["money"]["payers"] == 0 and d["money"]["first_purchase_median_hours"] is None
    assert d["money"]["coins"]["median"] is None and d["money"]["packs"] == []
    assert d["quality"]["median_active_seconds"] is None and d["quality"]["cases"] == []
    assert "قیف و ماندگاری" in d["text"]


async def test_one_failing_section_does_not_break_the_rest(session, monkeypatch):
    await seed(session)

    async def boom(s, f):
        raise RuntimeError("secret detail that must not be logged or returned")

    monkeypatch.setitem(funnel.SECTIONS, "money", boom)
    d = await funnel.build(session, 10, NOW)
    assert d["money"] == {"error": "section_failed"}
    assert d["funnel"]["total"]["registered"] == 6 and d["retention"]["total"]["d1"]["returned"] == 2
    assert "[پول] خطا" in d["text"] and "secret detail" not in json.dumps(d)


async def test_days_are_capped_and_a_90_day_window_works(session):
    await seed(session)
    d = await funnel.build(session, 500, NOW)
    assert d["days"] == 90 and len(d["signups"]["days"]) == 90 and d["funnel"]["total"]["registered"] == 6


# ---------------------------------------------------------------- the HTTP call

async def test_funnel_call_needs_the_key_validates_days_and_holds_no_personal_data(client):
    assert (await client.get("/admin/api/funnel")).status_code == 403
    assert (await client.get("/admin/api/funnel", headers={"X-Admin-Key": "wrong"})).status_code == 403
    assert (await client.get("/admin/api/funnel?days=91", headers=ADMIN)).status_code == 422
    assert (await client.get("/admin/api/funnel?days=0", headers=ADMIN)).status_code == 422
    p = await new_player(client, "funnel-http-dev-1")
    r = await client.get("/admin/api/funnel?days=30", headers=ADMIN)
    assert r.status_code == 200
    body = r.json()
    for k in ("signups", "funnel", "retention", "drop_off", "money", "quality", "text"):
        assert k in body
    raw = r.text
    assert p["player_id"] not in raw and "funnel-http-dev-1" not in raw
    assert (await client.get("/admin/api/funnel?days=30", headers=ADMIN)).json() == body   # served from the 60 s cache


async def test_the_panel_page_has_the_funnel_screen(client):
    page = (await client.get("/admin/ui")).text
    assert "قیف و ماندگاری" in page and "/admin/api/funnel" in page and "کپی به‌صورت متن" in page
