"""Relaxed anti-cheat (25 Oct 2026): live numbers, the frozen strict verdict, the admin watcher and the one-time
restore of stars that the strict rules took from honest players."""
import asyncio
from datetime import timedelta

import pytest
from sqlalchemy import delete, func, select, update

from app import anticheat as ac
from app import anticheat_admin as aa
from app import content, db
from app import economy as eco
from app.config import get_settings
from app.models import AdminLog, CaseProgress, Player, utcnow

from .conftest import ADMIN, new_player


@pytest.fixture(autouse=True)
async def _isolated_progress():
    """The test database is shared by the whole run: these tests count rows, so they start from an empty progress table."""
    async with db.SessionLocal() as s:
        await s.execute(delete(CaseProgress))
        await s.execute(delete(AdminLog).where(AdminLog.action == "anticheat_restore"))
        await s.commit()
    yield


@pytest.fixture
def live_rules(monkeypatch):
    """The real (relaxed) defaults; conftest switches the proof rule off for the other tests."""
    monkeypatch.setattr(eco, "MIN_ACTIVE_SECONDS", 90)
    monkeypatch.setattr(eco, "MIN_SUSPECTS_SEEN", None)
    st = get_settings()
    monkeypatch.setattr(st, "active_time_scale", 0.3)
    monkeypatch.setattr(st, "min_suspects_seen", 1)
    monkeypatch.setattr(st, "depth_min_questions", 1)


def case_with(diff):
    return next(c for c in content.all_cases() if int(c.data.get("difficulty") or 3) == diff)


def other_case(diff, exclude):
    return next(c for c in content.all_cases() if int(c.data.get("difficulty") or 3) == diff and c.id not in exclude)


async def row(pid, case_id, **kw):
    vals = dict(solved=True, stars=1, hints=0, attempts=0, proof_misses=0, active_seconds=40, seen=["a"],
                cards_opened=["e1"], questions_asked=["a:0"], ranked=False, finished_at=utcnow(), day="2026-10-20",
                was_daily=False, unlocked=False, seconds=40)
    vals.update(kw)
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=case_id, **vals))
        await s.commit()


async def get_row(pid, case_id):
    async with db.SessionLocal() as s:
        return (await s.execute(select(CaseProgress).where(CaseProgress.player_id == pid,
                                                           CaseProgress.case_id == case_id))).scalar_one()


async def total_stars(pid):
    async with db.SessionLocal() as s:
        return (await s.get(Player, pid)).stars_total


async def restore(client, **body):
    r = await client.post("/admin/anticheat-restore", headers=ADMIN, json=body)
    assert r.status_code == 200, r.text
    return r.json()


async def restore_all(client, **body):
    """Applies every batch, like the panel button; returns the summed counts."""
    after, tot = 0, {"candidates": 0, "restored": 0, "stars_given": 0}
    for _ in range(50):
        r = await restore(client, dry_run=False, after=after, limit=2, **body)
        for k in tot:
            tot[k] += r[k]
        after = r["next_after"]
        if r["done"]:
            return tot
    raise AssertionError("did not finish")


# ---------------------------------------------------------------- 1. live numbers and the frozen strict verdict
def test_live_needs_are_relaxed_and_strict_values_are_reachable_by_env(live_rules, monkeypatch):
    assert [eco.min_active_seconds(d) for d in (1, 2, 3, 4, 5)] == [18, 22, 27, 33, 39]
    assert eco.min_suspects_seen() == 1 and get_settings().depth_min_questions == 1
    st = get_settings()
    monkeypatch.setattr(st, "active_time_scale", 1.0)
    monkeypatch.setattr(st, "min_suspects_seen", 2)
    assert [eco.min_active_seconds(d) for d in (1, 2, 3, 4, 5)] == [60, 75, 90, 110, 130]
    assert eco.min_suspects_seen() == 2


def test_strict_verdict_ignores_the_environment(live_rules, monkeypatch):
    st = get_settings()
    monkeypatch.setattr(st, "active_time_scale", 0.0)
    monkeypatch.setattr(st, "min_suspects_seen", 0)
    monkeypatch.setattr(st, "depth_min_questions", 0)
    ok = ac.strict_verdict(90, 2, 2, 3)
    assert ok["proof_ok"] and ok["depth_ok"] and ok["reason"] == ""
    assert ac.strict_verdict(89, 2, 2, 3)["reason"] == "time"
    assert ac.strict_verdict(500, 1, 2, 3)["reason"] == "suspects"
    assert ac.strict_verdict(500, 2, 1, 3)["reason"] == "depth"
    assert ac.strict_verdict(500, 2, None, 3)["reason"] == ""          # an old app reports no depth
    assert [eco.strict_min_active_seconds(d) for d in (1, 2, 3, 4, 5, None, 9)] == [60, 75, 90, 110, 130, 90, 90]
    assert ac.strict_verdict(1, 0, 0, 3, solved=False)["reason"] == ""  # not solved: nothing to judge


async def test_a_quick_honest_solve_now_keeps_its_stars(client, live_rules, monkeypatch):
    c = content.by_id("c047")
    monkeypatch.setattr(content, "now_local", lambda: content.opens_at(c) + timedelta(hours=1))
    p = await new_player(client, "relax-live")
    await client.get(f"/v1/cases/{c.id}", headers=p["headers"])
    async with db.SessionLocal() as s:
        await s.execute(update(CaseProgress).where(CaseProgress.player_id == p["player_id"])
                        .values(active_seconds=eco.min_active_seconds(c.data['difficulty']), seen=[c.data["suspects"][0]["id"]]))
        await s.commit()
    r = await client.post(f"/v1/cases/{c.id}/accuse", headers=p["headers"],
                          json={"suspect": c.culprit, "evidence": sorted(c.proof)[0],
                                "cards": [], "asks": [f"{c.data['suspects'][0]['id']}:0"]})
    assert r.status_code == 200, r.text
    assert r.json()["stars"] == 3 and r.json()["stars_capped"] is False


# ---------------------------------------------------------------- 2. the watcher
async def test_watcher_needs_admin_and_reports_without_player_ids(client, live_rules):
    assert (await client.get("/admin/anticheat-watch")).status_code == 403
    a, b, c3 = case_with(3), case_with(2), case_with(4)
    p1, p2 = await new_player(client, "watch-1"), await new_player(client, "watch-2")
    await row(p1["player_id"], a.id, active_seconds=40, seen=["x"])                 # strict: time (needs 90)
    await row(p1["player_id"], b.id, active_seconds=300, seen=["x"], stars=3)       # strict: suspects
    await row(p2["player_id"], a.id, active_seconds=300, seen=["x", "y"], stars=3, questions_asked=["x:0"],
              cards_opened=["e1"])                                                  # strict: depth only
    await row(p2["player_id"], c3.id, active_seconds=400, seen=["x", "y"], stars=3,
              questions_asked=["x:0", "y:1"])                                       # fine under both
    await row(p2["player_id"], "w999", active_seconds=1, seen=[])                  # weekend: ignored
    await row(p2["player_id"], "s01ch01", active_seconds=1, seen=[])               # story: ignored
    r = await client.get("/admin/anticheat-watch?days=7", headers=ADMIN)
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["total_solves"] == 4
    s = d["strict"]
    assert s["affected"] == 3 and s["pct"] == 75.0 and d["level"] == "red"
    assert s["by_reason"] == {"time": 1, "suspects": 1, "depth": 1}
    assert s["one_star"] == 2 and s["kept_full_stars_by_relaxed"] == 3 and s["still_hurt_by_relaxed"] == 0
    assert s["by_difficulty"]["3"]["solves"] == 2 and s["by_difficulty"]["3"]["time"] == 1
    assert d["median_active_seconds"]["3"] in (170, 171) and d["per_day"][-1]["solves"] == 4
    assert p1["player_id"] not in r.text and p2["player_id"] not in r.text
    assert d["live_rules"]["active_time_scale"] == 0.3 and d["strict_rules"]["min_suspects_seen"] == 2


def test_watch_levels():
    assert [aa.level_for(x) for x in (0, 4.9, 5, 15, 15.1, 80)] == ["green", "green", "amber", "amber", "red", "red"]


async def test_watcher_keeps_real_cheat_patterns_listed_as_still_hurt(client, live_rules):
    c = case_with(3)
    p = await new_player(client, "watch-cheat")
    await row(p["player_id"], c.id, active_seconds=4, seen=[])
    s = (await client.get("/admin/anticheat-watch?days=1", headers=ADMIN)).json()["strict"]
    assert s["affected"] == 1 and s["kept_full_stars_by_relaxed"] == 0 and s["still_hurt_by_relaxed"] == 1


# ---------------------------------------------------------------- 3. the restore
async def test_restore_needs_admin_and_dry_run_changes_nothing(client, live_rules):
    assert (await client.post("/admin/anticheat-restore", json={})).status_code == 403
    c = case_with(3)
    p = await new_player(client, "rest-dry")
    await row(p["player_id"], c.id)
    before = await total_stars(p["player_id"])
    d = await restore(client)                                   # dry_run defaults to true
    assert d["dry_run"] is True and d["candidates"] == 1 and d["stars_to_give"] == 2
    assert d["by_difficulty"] == {"3": {"solves": 1, "stars": 2}} and d["ranked_to_restore"] == 1
    assert p["player_id"] not in str(d)
    r = await get_row(p["player_id"], c.id)
    assert r.stars == 1 and r.stars_restored is False and r.ranked is False
    assert await total_stars(p["player_id"]) == before
    async with db.SessionLocal() as s:
        assert await s.scalar(select(func.count()).select_from(AdminLog).where(AdminLog.action == "anticheat_restore")) == 0


async def test_only_honest_rows_are_restored_and_everything_else_is_untouched(client, live_rules):
    honest, cheat, banned, tester = [await new_player(client, f"rest-{n}") for n in ("h", "c", "b", "t")]
    c3, c2, c4 = case_with(3), case_with(2), case_with(4)
    await row(honest["player_id"], c3.id, hints=0)                                          # 40 s, 1 suspect -> 3 stars
    await row(honest["player_id"], c2.id, hints=2, active_seconds=30)                       # natural 2 -> +1, not 3
    await row(honest["player_id"], c4.id, active_seconds=40, questions_asked=[], cards_opened=[])  # depth fails: stars yes, rank no
    await row(honest["player_id"], other_case(3, {c3.id}).id, was_daily=True, unlocked=True)       # paid retry: stars yes, rank no
    await row(honest["player_id"], other_case(2, {c2.id}).id, active_seconds=300, seen=["a", "b"])  # strict passes: not ours
    await row(honest["player_id"], other_case(4, {c4.id}).id, stars=3, hints=0)                    # already full
    await row(honest["player_id"], "w999")                                                  # weekend
    await row(honest["player_id"], "s01ch01")                                               # story
    await row(cheat["player_id"], c3.id, active_seconds=5, seen=[])                         # throwaway pattern
    await row(banned["player_id"], c3.id)
    await row(tester["player_id"], c3.id)
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == banned["player_id"]).values(banned=True))
        await s.execute(update(Player).where(Player.id == tester["player_id"]).values(tester=True))
        await s.commit()
    base = {k: await total_stars(v["player_id"]) for k, v in (("h", honest), ("c", cheat), ("b", banned))}
    out = await restore_all(client)
    assert out == {"candidates": 4, "restored": 4, "stars_given": 2 + 1 + 2 + 2}
    h = honest["player_id"]
    assert (await get_row(h, c3.id)).stars == 3 and (await get_row(h, c3.id)).ranked is True
    assert (await get_row(h, c2.id)).stars == 2
    r4 = await get_row(h, c4.id)
    assert r4.stars == 3 and r4.ranked is False and r4.stars_restored is True
    assert (await get_row(h, other_case(3, {c3.id}).id)).ranked is False
    assert (await get_row(h, other_case(2, {c2.id}).id)).stars == 1
    assert (await get_row(h, "w999")).stars == 1 and (await get_row(h, "s01ch01")).stars == 1
    assert (await get_row(cheat["player_id"], c3.id)).stars == 1
    assert (await get_row(banned["player_id"], c3.id)).stars == 1
    assert (await get_row(tester["player_id"], c3.id)).stars == 1
    assert await total_stars(h) == base["h"] + 7
    assert await total_stars(cheat["player_id"]) == base["c"] and await total_stars(banned["player_id"]) == base["b"]
    async with db.SessionLocal() as s:   # coins/XP stay as they were: nothing wrote the coin log
        assert await s.scalar(select(func.count()).select_from(AdminLog).where(AdminLog.action == "anticheat_restore")) >= 2


async def test_second_run_gives_nothing_and_a_double_call_gives_once(client, live_rules):
    c = case_with(3)
    players = [await new_player(client, f"rest-twice-{i}") for i in range(3)]
    for pl in players:
        await row(pl["player_id"], c.id)
    first, second = await asyncio.gather(client.post("/admin/anticheat-restore", headers=ADMIN, json={"dry_run": False}),
                                         client.post("/admin/anticheat-restore", headers=ADMIN, json={"dry_run": False}))
    a, b = first.json(), second.json()
    assert a["restored"] + b["restored"] == 3 and a["stars_given"] + b["stars_given"] == 6
    for pl in players:
        assert await total_stars(pl["player_id"]) == 2
    again = await restore(client, dry_run=False)
    assert again["candidates"] == 0 and again["restored"] == 0
    for pl in players:
        assert await total_stars(pl["player_id"]) == 2


async def test_restore_updates_the_boards_and_respects_the_kill_switch(client, live_rules, monkeypatch):
    c = case_with(3)
    p = await new_player(client, "rest-board")
    await row(p["player_id"], c.id)
    lb0 = (await client.get("/v1/leaderboard?period=all", headers=p["headers"])).json()
    monkeypatch.setattr(get_settings(), "anticheat_restore_enabled", False)
    r = await client.post("/admin/anticheat-restore", headers=ADMIN, json={"dry_run": False})
    assert r.status_code == 409
    assert (await restore(client))["candidates"] == 1            # a dry run still works
    assert (await get_row(p["player_id"], c.id)).stars == 1
    monkeypatch.setattr(get_settings(), "anticheat_restore_enabled", True)
    await restore(client, dry_run=False)
    lb1 = (await client.get("/v1/leaderboard?period=all", headers=p["headers"])).json()
    assert lb0["me"] is None and lb1["me"] is not None and lb1["me"]["stars"] == 2
    assert (await get_row(p["player_id"], c.id)).ranked is True
    assert await total_stars(p["player_id"]) == 2


async def test_panel_home_shows_the_watcher_card_and_the_two_step_restore(client):
    html = (await client.get("/admin/ui")).text
    assert "/admin/anticheat-watch" in html and "برگرداندن ستاره‌ها" in html and "با قانون سخت ۱ ستاره می‌شدند" in html
    assert "ACTIVE_TIME_SCALE=1" in html and 'id="acgo"' in html and "dry_run: dry" in html
