"""Admin screen «اقتصاد سکه» (app/services/economy_report.py): seeded data in its own SQLite database, fixed clock."""
from datetime import datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app import economy as eco
from app.db import Base
from app.models import CaseProgress, CaseToolUse, CoinLog, Player
from app.services import economy_report as er

from .conftest import ADMIN

NOW = datetime(2026, 10, 21, 12, 0)


@pytest.fixture
async def session(tmp_path):
    engine = create_async_engine(f"sqlite+aiosqlite:///{tmp_path}/economy.db")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        yield s
    await engine.dispose()


def player(s, n, created, seen, coins=0, device=None, banned=False):
    s.add(Player(id=f"p{n}", secret_hash="x", device_id=device or f"dev-{n}", invite_code=f"CODE{n}", nickname=f"nick{n}",
                 coins=coins, banned=banned, created_at=created, last_seen=seen))


def coin(s, n, amount, reason, at):
    s.add(CoinLog(player_id=f"p{n}", amount=amount, reason=reason, balance=0, at=at))


def prog(s, n, case, opened, finished=None, solved=False, failed=False, hints=0):
    s.add(CaseProgress(player_id=f"p{n}", case_id=case, opened_at=opened, finished_at=finished, solved=solved,
                       failed=failed, hints=hints))


def test_kind_and_group_fold_reasons():
    assert er.kind_of("hint2:c020") == "hint" and er.kind_of("tool_camera:c020") == "tool"
    assert er.kind_of("solve:c001") == "solve" and er.kind_of("streak_repair") == "streak_repair" and er.kind_of("") == "other"
    assert er.group_of("hint") == "escape" and er.group_of("tool") == "escape" and er.group_of("reopen") == "escape"
    assert er.group_of("avatar") == "desire" and er.group_of("unlock") == "desire" and er.group_of("solve") == "other"


async def seed(s):
    d = NOW - timedelta(days=1)
    player(s, 1, NOW - timedelta(days=10), NOW - timedelta(hours=2), coins=0)
    player(s, 2, NOW - timedelta(days=10), NOW - timedelta(hours=3), coins=45)
    player(s, 3, NOW - timedelta(days=10), NOW - timedelta(hours=4), coins=120)
    player(s, 4, NOW - timedelta(days=10), NOW - timedelta(hours=5), coins=900)
    player(s, 5, NOW - timedelta(days=10), NOW - timedelta(days=30), coins=5000)             # not active this week
    player(s, 6, NOW - timedelta(days=10), NOW - timedelta(hours=1), coins=9999, device="smoke-x")
    player(s, 7, NOW - timedelta(days=10), NOW - timedelta(hours=1), coins=9999, banned=True)
    for n in (1, 2, 3, 4, 6, 7):
        coin(s, n, 100, f"solve:c0{n}", d)
    coin(s, 1, -40, "hint1:c020", d)
    coin(s, 2, -80, "hint2:c020", d)
    coin(s, 2, -65, "tool_fingerprint:c020", d)
    coin(s, 3, -600, "avatar:ex_cat", d)
    coin(s, 4, -240, "reopen:c020", d)
    coin(s, 6, -5000, "hint1:c020", d)                                                         # smoke: ignored
    coin(s, 7, -5000, "avatar:x", d)                                                           # banned: ignored
    coin(s, 5, 100, "solve:old", NOW - timedelta(days=40))                                     # outside the window
    # cases: p1 solved with 1 hint, p2 lost and came back, p3 lost and never came back, p4 lost and reopened (paid)
    prog(s, 1, "c020", d, d, solved=True, hints=1)
    prog(s, 2, "c020", d, d, failed=True, hints=3)
    prog(s, 2, "c021", d + timedelta(hours=1))
    prog(s, 3, "c020", d, d, failed=True)
    s.add(CaseToolUse(player_id="p1", case_id="c020", kind="fingerprint", source="free", result={}, created_at=d))
    s.add(CaseToolUse(player_id="p2", case_id="c020", kind="fingerprint", source="coins", result={}, created_at=d))
    await s.commit()


async def test_flows_balances_cases_and_loss(session):
    await seed(session)
    d = await er.build(session, 14, now=NOW)
    assert not any(isinstance(v, dict) and v.get("error") for v in d.values())
    fl = d["flows"]
    assert fl["earned_total"] == 400 and fl["spent_total"] == 40 + 80 + 65 + 600 + 240   # smoke, banned, old rows left out
    spent = {r["kind"]: r for r in fl["spent"]}
    assert spent["hint"]["coins"] == 120 and spent["hint"]["times"] == 2 and spent["hint"]["group"] == "escape"
    assert spent["avatar"]["group"] == "desire"
    split = fl["spent_split_pct"]
    assert split["desire"] == round(100 * 600 / 1025, 1) and split["escape"] == round(100 * 425 / 1025, 1)
    bal = d["balances"]
    assert bal["active_players"] == 4                       # p5 not seen this week; smoke and banned left out
    assert [b["players"] for b in bal["buckets"]] == [1, 1, 0, 1, 0, 1]
    assert bal["can_afford_first_hint_pct"] == 75.0          # 45, 120 and 900 reach the first hint price (40)
    assert bal["first_hint_price"] == eco.HINT_COSTS[0]
    cs = d["cases"]
    assert cs["finished"] == 3 and cs["failed"] == 2 and cs["with_hint_pct"] == round(200 / 3, 1)
    assert {t["kind"]: (t["free"], t["coins"]) for t in cs["tools"]} == {"fingerprint": (1, 1)}
    loss = d["after_loss"]
    assert loss["lost_cases"] == 2 and loss["came_back_pct"] == 50.0 and loss["paid_second_chance"] == 1


async def test_first_day_spenders_and_notes(session):
    created = NOW - timedelta(days=5)
    for n in range(1, 25):
        spender = n <= 12
        player(session, n, created, created + (timedelta(days=2) if (n % 2 == 0 or not spender) else timedelta(hours=3)))
        if spender:
            coin(session, n, -40, "hint1:c020", created + timedelta(hours=2))
    coin(session, 13, -40, "hint1:c020", created + timedelta(days=3))                           # later spend: not a first-day spender
    await session.commit()
    fd = (await er.build(session, 14, now=NOW))["first_day"]
    assert fd["players"] == 24 and fd["spent_first_day"] == 12 and fd["others"] == 12
    assert fd["spenders_came_back_pct"] == 50.0 and fd["others_came_back_pct"] == 100.0
    d = await er.build(session, 14, now=NOW)
    assert any("برگشته" in n for n in d["notes"])


async def test_empty_database_is_calm(session):
    d = await er.build(session, 7, now=NOW)
    assert d["flows"]["earned_total"] == 0 and d["balances"]["active_players"] == 0
    assert d["after_loss"]["came_back_pct"] is None and d["first_day"] == {"players": 0}
    assert d["notes"]


async def test_a_failing_section_does_not_break_the_others(session, monkeypatch):
    async def boom(*a, **k):
        raise RuntimeError("x")
    monkeypatch.setattr(er, "SECTIONS", [("flows", boom, "since")] + [x for x in er.SECTIONS if x[0] != "flows"])
    d = await er.build(session, 7, now=NOW)
    assert d["flows"] == {"error": "section_failed"} and d["balances"]["active_players"] == 0


def test_notes_flag_trap_economies():
    d = {"flows": {"spent_total": 100, "spent_split_pct": {"escape": 80, "desire": 20, "other": 0}},
         "balances": {"active_players": 50, "buckets": [{"pct": 50}] + [{"pct": 0}] * 5, "can_afford_first_hint_pct": 20,
                      "first_hint_price": 40},
         "after_loss": {"lost_cases": 40, "came_back_pct": 40}, "cases": {"failed_pct": 50, "finished": 100}}
    text = " ".join(er.notes(d))
    assert "فرار از گیر" in text and "اولین سرنخ" in text and "سکه‌ی صفر" in text and "باخت" in text and "شکست" in text


async def test_endpoint_needs_admin_and_holds_no_player_data(client):
    assert (await client.get("/admin/api/economy")).status_code in (401, 403)
    r = await client.get("/admin/api/economy?days=7", headers=ADMIN)
    assert r.status_code == 200
    body = r.json()
    assert {"flows", "balances", "cases", "after_loss", "first_day", "notes"} <= set(body)
    text = r.text
    assert "nick" not in text and "device" not in text and "player_id" not in text
    assert (await client.get("/admin/api/economy?days=999", headers=ADMIN)).status_code == 422
    page = (await client.get("/admin/ui")).text
    assert "اقتصاد سکه" in page and "/admin/api/economy" in page


def test_prices_are_sane():
    assert eco.HINT_COSTS == sorted(eco.HINT_COSTS)
    assert all(eco.TOOL_PRICES[k] < eco.HINT_COSTS[i] for i, k in enumerate(("magnifier", "fingerprint", "camera")))
