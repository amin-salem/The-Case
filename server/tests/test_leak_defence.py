"""Leaked-answer defence: investigation depth gate, the daily draw, the consistency weekly order, the suspicious-solve
report. Deterministic clocks, no sleeps. Uses cases c041-c044 (no other test plays them)."""
import asyncio
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import func, select, update

from app import anticheat as ac
from app import cheatreport, content, db, rewards, weekboard
from app.config import get_settings
from app.models import CaseProgress, DailyDraw, InboxItem, Player, utcnow

from .conftest import ADMIN, new_player
from .test_fair_week import T, solve as week_solve, week_of_fake_cases, wid  # noqa: F401


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def night(case_id: str, hours: int = 1) -> datetime:
    return content.opens_at(content.by_id(case_id)) + timedelta(hours=hours)


async def accuse(client, p, c, **extra):
    r = await client.post(f"/v1/cases/{c.id}/accuse", headers=p["headers"],
                          json={"suspect": c.culprit, "evidence": sorted(c.proof)[0], **extra})
    assert r.status_code == 200, r.text
    return r.json()


def deep(c):
    """What a player who really looked reports: 3 cards, 2 questions."""
    sid = c.data["suspects"][0]["id"]
    return {"cards": [e["id"] for e in c.data["evidence"][:3]], "asks": [f"{sid}:0", f"{sid}:1"]}


async def start(client, name, c):
    p = await new_player(client, name)
    await client.get(f"/v1/cases/{c.id}", headers=p["headers"])
    return p


# ---------------------------------------------------------------- 2. investigation depth
async def test_shallow_solve_keeps_stars_and_coins_but_loses_the_board_place(client, clock):
    c = content.by_id("c041")
    clock(night("c041"))
    lazy, real = await start(client, "ld-lazy", c), await start(client, "ld-real", c)
    r = await accuse(client, lazy, c, cards=[], asks=[])
    assert r["result"] == "solved" and r["stars"] == 3 and r["reward"] > 0
    assert r["ranked"] is False and r["unranked"] is True and r["unranked_reason"] == "depth" and r["rank"] is None
    assert r["depth"]["evidence"] == 0 and r["depth"]["questions"] == 0
    r = await accuse(client, real, c, **deep(c))
    assert r["ranked"] is True and r["unranked_reason"] == "" and r["rank"] is not None
    assert r["depth"]["evidence"] == 3 and r["depth"]["questions"] == 2
    lb = (await client.get("/v1/leaderboard?period=daily", headers=lazy["headers"])).json()
    assert lb["me"] is None
    assert (await client.get("/v1/leaderboard?period=daily", headers=real["headers"])).json()["me"] is not None


async def test_depth_reported_by_ticks_counts_and_garbage_does_not(client, clock):
    c = content.by_id("c041")
    clock(night("c041"))
    p = await start(client, "ld-tick", c)
    sid = c.data["suspects"][1]["id"]
    r = await client.post(f"/v1/cases/{c.id}/tick", headers=p["headers"], json={
        "seconds": 5, "cards": [e["id"] for e in c.data["evidence"][:2]] + ["zzz", "e999"],
        "asks": [f"{sid}:0", "nobody:0", "bad key", f"{sid}:123456"]})
    assert r.status_code == 200
    r = await client.post(f"/v1/cases/{c.id}/tick", headers=p["headers"], json={
        "seconds": 5, "cards": [c.data["evidence"][2]["id"]], "asks": [f"{sid}:1"]})
    assert r.status_code == 200
    async with db.SessionLocal() as s:
        row = (await s.execute(select(CaseProgress).where(CaseProgress.player_id == p["player_id"],
                                                          CaseProgress.case_id == c.id))).scalar_one()
    assert len(row.cards_opened) == 3 and set(row.questions_asked) == {f"{sid}:0", f"{sid}:1"}
    r = await accuse(client, p, c)  # nothing more reported in the accusation: the ticks are enough
    assert r["ranked"] is True and r["depth"]["evidence"] == 3


async def test_too_many_entries_are_refused(client, clock):
    c = content.by_id("c041")
    clock(night("c041"))
    p = await start(client, "ld-big", c)
    r = await client.post(f"/v1/cases/{c.id}/tick", headers=p["headers"], json={"seconds": 1, "cards": ["e1"] * 81})
    assert r.status_code == 422
    r = await client.post(f"/v1/cases/{c.id}/accuse", headers=p["headers"],
                          json={"suspect": c.culprit, "evidence": "e1", "asks": ["a:1"] * 81})
    assert r.status_code == 422


async def test_old_app_without_depth_is_not_gated_unless_required(client, clock, monkeypatch):
    c = content.by_id("c041")
    clock(night("c041"))
    old = await start(client, "ld-old", c)
    r = await accuse(client, old, c)  # no cards / asks fields at all
    assert r["ranked"] is True and r["depth"]["evidence"] == 0
    strict = await start(client, "ld-old2", c)
    monkeypatch.setattr(get_settings(), "depth_require_report", True)
    r = await accuse(client, strict, c)
    assert r["ranked"] is False and r["unranked_reason"] == "depth" and r["stars"] == 3


async def test_kill_switch_and_thresholds(client, clock, monkeypatch):
    c = content.by_id("c041")
    clock(night("c041"))
    st = get_settings()
    off = await start(client, "ld-off", c)
    monkeypatch.setattr(st, "depth_gate_enabled", False)
    assert (await accuse(client, off, c, cards=[], asks=[]))["ranked"] is True
    monkeypatch.setattr(st, "depth_gate_enabled", True)
    monkeypatch.setattr(st, "depth_min_cards", 1)
    monkeypatch.setattr(st, "depth_min_questions", 0)
    low = await start(client, "ld-low", c)
    assert (await accuse(client, low, c, cards=[c.data["evidence"][0]["id"]], asks=[]))["ranked"] is True
    monkeypatch.setattr(st, "depth_need_proof", True)
    nop = await start(client, "ld-noproof", c)
    others = [e["id"] for e in c.data["evidence"] if e["id"] not in c.proof][:1]
    r = await accuse(client, nop, c, cards=others, asks=[])
    assert r["ranked"] is False and r["unranked_reason"] == "depth"


async def test_card_threshold_when_switched_on(client, clock, monkeypatch):
    c = content.by_id("c041")
    clock(night("c041"))
    monkeypatch.setattr(get_settings(), "depth_min_cards", 3)
    two = await start(client, "ld-two", c)
    sid = c.data["suspects"][0]["id"]
    r = await accuse(client, two, c, cards=[e["id"] for e in c.data["evidence"][:2]], asks=[f"{sid}:0", f"{sid}:1"])
    assert r["ranked"] is False and r["unranked_reason"] == "depth" and r["stars"] == 3
    three = await start(client, "ld-three", c)
    assert (await accuse(client, three, c, **deep(c)))["ranked"] is True


def test_depth_ok_is_pure_and_skips_weekend_and_story(monkeypatch):
    c = content.by_id("c041")
    p = CaseProgress(cards_opened=[], questions_asked=[])
    assert ac.depth_ok(p, c)[0] is False
    p = CaseProgress(cards_opened=[e["id"] for e in c.data["evidence"][:3]], questions_asked=["a:0", "a:1"])
    assert ac.depth_ok(p, c) == (True, "")
    w = content.weekly_cases()[0]
    assert ac.depth_ok(CaseProgress(cards_opened=[], questions_asked=[]), w) == (True, "")


# ---------------------------------------------------------------- 3. the daily draw
async def test_daily_draw_one_winner_idempotent_and_deterministic(client, clock):
    c = content.by_id("c042")
    clock(night("c042"))
    a, b = await start(client, "dd-a", c), await start(client, "dd-b", c)
    lazy = await start(client, "dd-lazy", c)
    await accuse(client, a, c, **deep(c))
    await accuse(client, b, c, **deep(c))
    assert (await accuse(client, lazy, c, cards=[], asks=[]))["ranked"] is False  # never in the draw
    clock(night("c043"))
    async with db.SessionLocal() as s:
        winner = await rewards.draw_case(s, c)
    expected = rewards.draw_pick(c.id, [a["player_id"], b["player_id"]])
    assert winner == expected and winner in (a["player_id"], b["player_id"])
    async with db.SessionLocal() as s:
        assert await rewards.draw_case(s, c) is None  # a second run draws nothing
        row = await s.get(DailyDraw, c.id)
        assert row.winner_id == winner and row.eligible == 2
        n = await s.scalar(select(func.count()).select_from(InboxItem).where(InboxItem.source == f"draw:{c.id}"))
        assert n == 1
    win = a if winner == a["player_id"] else b
    items = (await client.get("/v1/inbox", headers=win["headers"])).json()
    gift = next(i for i in items if i["title"].startswith("برنده‌ی قرعه"))
    assert gift["grants"] == [{"type": "warrants", "amount": 1}]  # no coins
    before = (await client.get("/v1/me", headers=win["headers"])).json()["warrants"]
    r = await client.post(f"/v1/inbox/{gift['id']}/claim", headers=win["headers"])
    assert r.status_code == 200
    assert (await client.get("/v1/me", headers=win["headers"])).json()["warrants"] == before + 1
    assert (await client.post(f"/v1/inbox/{gift['id']}/claim", headers=win["headers"])).status_code in (404, 409)
    assert rewards.draw_pick("x", []) is None
    assert rewards.draw_pick("x", ["b", "a"]) == rewards.draw_pick("x", ["a", "b"])


async def test_two_simultaneous_draws_pay_once(client, clock):
    c = content.by_id("c044")
    clock(night("c044"))
    a = await start(client, "dd-par-a", c)
    await accuse(client, a, c, **deep(c))
    clock(night("c044") + timedelta(days=1, hours=1))

    async def one():
        async with db.SessionLocal() as s:
            return await rewards.draw_case(s, c)

    res = await asyncio.gather(one(), one(), return_exceptions=True)
    assert [r for r in res if r == a["player_id"]] == [a["player_id"]]
    async with db.SessionLocal() as s:
        n = await s.scalar(select(func.count()).select_from(InboxItem).where(InboxItem.source == f"draw:{c.id}"))
    assert n == 1


async def test_draw_kill_switch_and_nobody_eligible(client, clock, monkeypatch):
    clock(night("c043") + timedelta(days=1))
    st = get_settings()
    monkeypatch.setattr(st, "daily_draw_enabled", False)
    async with db.SessionLocal() as s:
        before = await s.scalar(select(func.count()).select_from(DailyDraw))
        assert await rewards.settle_daily_draws(s) == 0
        assert await s.scalar(select(func.count()).select_from(DailyDraw)) == before
    monkeypatch.setattr(st, "daily_draw_enabled", True)
    async with db.SessionLocal() as s:
        await rewards.settle_daily_draws(s)  # draws the last closed cases; an empty one gets a row without a winner
        c = content.by_id("c043")
        row = await s.get(DailyDraw, c.id)
        assert row is not None and row.winner_id is None and row.eligible == 0


# ---------------------------------------------------------------- 3b. weekly order: consistency first
async def test_weekly_order_nights_then_on_time_then_plaques_then_speed(client, clock, monkeypatch, week_of_fake_cases):
    monkeypatch.setattr(get_settings(), "week_rank_mode", "consistency")
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    ws = date(2027, 4, 2)
    clock(T(2027, 4, 5, 12))
    one3, three1, pun, late, quick, slow = [await new_player(client, f"wc-{i}") for i in range(6)]

    async def solve(p, i, stars, day, seconds=100, daily=False):
        await week_solve(p["player_id"], wid(ws, i), stars, T(2027, 4, day, 10), seconds=seconds)
        async with db.SessionLocal() as s:
            await s.execute(update(CaseProgress).where(CaseProgress.player_id == p["player_id"],
                                                       CaseProgress.case_id == wid(ws, i)).values(was_daily=daily))
            await s.commit()

    await solve(one3, 0, 3, 3)                                    # 3 plaques in ONE night
    for i in range(3):
        await solve(three1, i, 1, 3 + i)                          # 3 plaques over THREE nights: ranks first
    for i in range(2):
        await solve(pun, i, 1, 3 + i, daily=True)                 # same nights as `late`, but on their own night
        await solve(late, i, 1, 3 + i, daily=False)
    for i in range(2):
        await solve(quick, i, 2, 3 + i, seconds=50)               # same nights, same plaques: speed only breaks the tie
        await solve(slow, i, 2, 3 + i, seconds=400)
    async with db.SessionLocal() as s:
        order = [x.player.id for x in await weekboard.standings(s, ws)]
    ids = {k: v["player_id"] for k, v in dict(one3=one3, three1=three1, pun=pun, late=late, quick=quick, slow=slow).items()}
    assert order[0] == ids["three1"]                              # most nights
    # among the two-night players: 2-plaque solves beat 1-plaque unless on time counts first
    assert order.index(ids["pun"]) < order.index(ids["quick"]) < order.index(ids["slow"])
    assert order.index(ids["quick"]) < order.index(ids["late"])
    assert order.index(ids["slow"]) < order.index(ids["one3"])   # two nights beat one night, even with more plaques each
    # the player's own rank uses the same order
    async with db.SessionLocal() as s:
        pl = await s.get(Player, ids["slow"])
        rank, pts = await weekboard.my_standing(s, ws, pl, None)
    assert rank == order.index(ids["slow"]) + 1 and pts == 4
    # the old order is one setting away
    monkeypatch.setattr(get_settings(), "week_rank_mode", "points")
    async with db.SessionLocal() as s:
        old = [x.player.id for x in await weekboard.standings(s, ws)]
    assert old.index(ids["one3"]) < old.index(ids["pun"])


# ---------------------------------------------------------------- 4. suspicious-solve report
def test_cluster_detection_is_pure():
    t0 = datetime(2026, 10, 22, 12, 0, 0)
    quiet_group = [(t0 + timedelta(seconds=10 * i), f"p{i}") for i in range(5)]
    assert len(cheatreport.find_clusters(quiet_group)) == 1
    # not enough accounts
    assert cheatreport.find_clusters(quiet_group[:3]) == []
    # a steady stream (no quiet period before the second burst) is not a cluster
    steady = [(t0 + timedelta(seconds=300 * i), f"s{i}") for i in range(10)]
    assert cheatreport.find_clusters(steady) == []
    # a burst that starts only 20 s after another solve is not "after a quiet period"
    mixed = [(t0, "first")] + [(t0 + timedelta(seconds=20 + 10 * i), f"m{i}") for i in range(5)]
    assert all(g[0][1] != "m0" for g in cheatreport.find_clusters(mixed))
    # a burst after 15 quiet minutes is
    later = [(t0, "x")] + [(t0 + timedelta(minutes=15, seconds=10 * i), f"l{i}") for i in range(5)]
    assert [g[0][1] for g in cheatreport.find_clusters(later)] == ["l0"]


async def test_suspicious_report_flags_and_never_bans(client, clock, caplog):
    c = content.by_id("c043")
    clock(night("c043"))
    now = utcnow()
    ps = [await new_player(client, f"sr-{i}") for i in range(10)]
    async with db.SessionLocal() as s:
        for i, p in enumerate(ps):
            s.add(CaseProgress(player_id=p["player_id"], case_id=c.id, solved=True, stars=3, ranked=True, was_daily=True,
                               finished_at=now - timedelta(hours=2) + timedelta(seconds=5 * i),
                               active_seconds=10 if i < 3 else (30 if i == 5 else 200), cards_opened=[] if i < 5 else None,
                               questions_asked=[] if i < 5 else None))
        await s.commit()
    with caplog.at_level("INFO", logger="cheatreport"):
        async with db.SessionLocal() as s:
            rep = await cheatreport.suspicious_solves(s, now)
    assert len(rep["clusters"]) == 1 and rep["clusters"][0]["accounts"] == 10
    assert any(r.message.startswith("suspicious_cluster case=c043 accounts=10") for r in caplog.records)
    assert not any(ps[0]["player_id"] in r.message for r in caplog.records)  # no personal data in the log
    assert {x["why"] for x in rep["low_depth"]} == {"depth", "active_time"}
    assert len(rep["far_faster"]) >= 1 and rep["far_faster"][0]["median"] > rep["far_faster"][0]["active_seconds"]
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(Player).where(Player.banned.is_(True),
                                                                             Player.id.in_([p["player_id"] for p in ps]))) == 0
    r = await client.get("/admin/suspicious-solves", headers=ADMIN)
    assert r.status_code == 200 and set(r.json()) >= {"low_depth", "far_faster", "clusters"}
    assert (await client.get("/admin/suspicious-solves")).status_code in (401, 403)
