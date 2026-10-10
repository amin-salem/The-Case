"""Story mode: chapters open in order (3 free, then warrant / 12 h wait / coins), warrants are earned."""
import json
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content, missions
from app import economy as eco
from app import models

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def story(tmp_path, monkeypatch):
    """Five placeholder chapters made from case c001 (the real season is written separately)."""
    base = content.by_id("c001").data
    folder = tmp_path / "s01"
    folder.mkdir()
    for n in range(1, 6):
        d = {**json.loads(json.dumps(base)), "id": f"s01ch{n:02d}", "number": n, "season": 1, "chapter": n,
             "title": f"فصل {n}", "partner_intro": "بیا شروع کنیم.", "partner_outro_win": "آفرین.",
             "partner_outro_lose": "دفعه‌ی بعد.", "thread": "یه کبریت سوخته."}
        d.pop("publish")
        (folder / f"ch{n:02d}.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(content, "STORY_DIR", tmp_path)
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2026-01-01T00:00:00")
    return content.story_chapters()


def pid_of(p):
    return p["player_id"]


async def give(player_id, **fields):
    from sqlalchemy import update

    from app import db
    async with db.SessionLocal() as s:
        await s.execute(update(models.Player).where(models.Player.id == player_id).values(**fields))
        await s.commit()


async def age_finish(player_id, chapter, hours):
    """Pretend the chapter was finished `hours` ago."""
    from sqlalchemy import update

    from app import db
    async with db.SessionLocal() as s:
        await s.execute(update(models.StoryProgress).where(
            models.StoryProgress.player_id == player_id, models.StoryProgress.chapter == chapter
        ).values(finished_at=models.utcnow() - timedelta(hours=hours)))
        await s.commit()


async def play(client, h, n, win=True):
    cid = f"s01ch{n:02d}"
    r = await client.post(f"/v1/story/{n}/open", headers=h)
    assert r.status_code == 200, r.text
    await client.get(f"/v1/cases/{cid}", headers=h)
    c = content.story_by_id(cid)
    if win:
        r = await client.post(f"/v1/cases/{cid}/accuse", headers=h,
                              json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})
        assert r.json()["result"] == "solved"
    else:
        others = [s["id"] for s in c.data["suspects"] if s["id"] != c.culprit]
        for _ in range(eco.MAX_ATTEMPTS):
            r = await client.post(f"/v1/cases/{cid}/accuse", headers=h,
                                  json={"suspect": others[0], "evidence": sorted(c.proof)[0]})
        assert r.json()["result"] == "failed"
    return r.json()


def states(body):
    return [c["state"] for c in body["chapters"]]


def test_no_folder_means_coming_soon(monkeypatch, tmp_path):
    monkeypatch.setattr(content, "STORY_DIR", tmp_path / "nothing")
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2026-01-01T00:00:00")
    assert content.story_chapters() == ()
    assert content.story_upcoming()["open"] is False  # time has passed, but no chapters yet


def test_open_only_when_time_passed_and_chapters_exist(story, monkeypatch):
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2099-01-01T00:00:00")
    assert content.story_upcoming()["open"] is False
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2026-01-01T00:00:00")
    assert content.story_upcoming()["open"] is True


def test_bad_chapter_file_is_refused(tmp_path, monkeypatch):
    d = json.loads(json.dumps(content.by_id("c001").data))
    d.update(id="s01ch01", number=1, season=1, chapter=1)  # no partner lines
    (tmp_path / "s01").mkdir()
    (tmp_path / "s01" / "ch01.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    monkeypatch.setattr(content, "STORY_DIR", tmp_path)
    with pytest.raises(content.CaseError):
        content.story_chapters()


async def test_free_chapters_in_order_then_wait(client, story):
    p = await new_player(client, "story-1")
    h = p["headers"]
    body = (await client.get("/v1/story", headers=h)).json()
    assert body["open"] and states(body) == ["ready", "locked", "locked", "locked", "locked"]
    assert body["chapters"][1]["title"] is None  # locked chapters keep their title secret
    # wrong order is refused, a locked chapter's case is closed
    assert (await client.post("/v1/story/2/open", headers=h)).json()["detail"] == "wrong_order"
    assert (await client.get("/v1/cases/s01ch02", headers=h)).status_code == 409
    assert (await client.get("/v1/cases/s01ch01", headers=h)).status_code == 409  # not opened yet either
    r = await client.post("/v1/cases/s01ch01/unlock", headers=h)
    assert r.status_code == 409  # never bought like an archive case
    assert (await client.post("/v1/story/9/open", headers=h)).status_code == 404

    got = await play(client, h, 1)
    assert got["story"]["outro"] == "آفرین." and got["story"]["thread"]
    case = (await client.get("/v1/cases/s01ch01", headers=h)).json()["case"]
    assert case["story"]["intro"] and "partner_outro_win" not in case and "solution" in case
    await play(client, h, 2, win=False)  # losing also finishes a chapter
    await play(client, h, 3)  # chapters 1-3 are free and instant
    body = (await client.get("/v1/story", headers=h)).json()
    assert states(body) == ["done", "done", "done", "waiting", "locked"]
    assert body["chapters"][1]["solved"] is False and body["chapters"][0]["stars"] == 3
    w = body["chapters"][3]
    assert w["unlock_at"] and body["next_open_at"] == w["unlock_at"]
    assert w["skip_cost"] == eco.STORY_SKIP_COST and w["can_warrant"] is False
    assert (await client.post("/v1/story/4/open", headers=h)).json()["detail"] == "wait"
    assert (await client.post("/v1/story/5/open", headers=h)).json()["detail"] == "wrong_order"


async def test_warrant_opens_next_chapter(client, story):
    p = await new_player(client, "story-2")
    h = p["headers"]
    for n in (1, 2, 3):
        await play(client, h, n)
    r = await client.post("/v1/story/4/open", headers=h, json={"warrant": True})
    assert r.status_code == 409 and r.json()["detail"] == "no_warrant"
    await give(pid_of(p), warrants=2)
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["warrants"] == 2
    body = (await client.get("/v1/story", headers=h)).json()
    assert body["chapters"][3]["can_warrant"] is True
    r = await client.post("/v1/story/4/open", headers=h, json={"warrant": True})
    assert r.status_code == 200 and r.json()["warrants"] == 1 and r.json()["case_id"] == "s01ch04"
    assert states(r.json())[3] == "open"
    # opening again costs nothing
    r = await client.post("/v1/story/4/open", headers=h, json={"warrant": True})
    assert r.json()["warrants"] == 1
    await play(client, h, 4)
    assert (await client.get("/v1/story", headers=h)).json()["chapters"][4]["state"] == "waiting"


async def test_twelve_hours_open_it_by_themselves(client, story):
    p = await new_player(client, "story-3")
    h = p["headers"]
    pid = pid_of(p)
    for n in (1, 2, 3):
        await play(client, h, n)
    await age_finish(pid, 3, 11)
    assert states((await client.get("/v1/story", headers=h)).json())[3] == "waiting"
    await age_finish(pid, 3, 12.1)
    body = (await client.get("/v1/story", headers=h)).json()
    assert body["chapters"][3]["state"] == "ready" and body["next_open_at"] is None
    r = await client.post("/v1/story/4/open", headers=h)
    assert r.status_code == 200 and r.json()["warrants"] == 0


def test_skip_price_falls_with_time():
    assert eco.story_skip_cost(12 * 3600) == eco.STORY_SKIP_COST
    assert eco.story_skip_cost(6 * 3600) == eco.STORY_SKIP_COST // 2
    assert eco.story_skip_cost(60) == eco.STORY_SKIP_MIN
    assert eco.story_skip_cost(0) == 0


async def test_skip_with_coins(client, story):
    p = await new_player(client, "story-4")
    h = p["headers"]
    pid = pid_of(p)
    for n in (1, 2, 3):
        await play(client, h, n)
    await give(pid, coins=50)
    r = await client.post("/v1/story/4/skip", headers=h)
    assert r.status_code == 402 and r.json()["detail"]["need"] > 50
    await age_finish(pid, 3, 6)  # half of the wait is over: half the price
    await give(pid, coins=500)
    coins = (await client.get("/v1/me", headers=h)).json()["coins"]
    r = await client.post("/v1/story/4/skip", headers=h)
    assert r.status_code == 200 and states(r.json())[3] == "open"
    paid = coins - r.json()["coins"]
    assert abs(paid - eco.STORY_SKIP_COST // 2) <= 2
    assert (await client.post("/v1/story/5/skip", headers=h)).json()["detail"] == "wrong_order"


async def test_story_closed_before_opening_time(client, story, monkeypatch):
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2099-01-01T00:00:00")
    p = await new_player(client, "story-5")
    h = p["headers"]
    assert (await client.get("/v1/story", headers=h)).json()["open"] is False
    assert (await client.post("/v1/story/1/open", headers=h)).json()["detail"] == "story_not_open"
    assert (await client.get("/v1/cases/s01ch01", headers=h)).status_code == 404


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt):
        monkeypatch.setattr(content, "now_local", lambda: dt)
    return set_to


@pytest.fixture
def no_missions(monkeypatch):
    """A day's only mission needs a bought hint, so no test below finishes the missions by accident."""
    monkeypatch.setattr(missions, "for_day", lambda day: [missions.BY_ID["hint_use"]])


async def test_warrant_for_tonights_case(client, clock, no_missions):
    c = content.by_id("c020")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    p = await new_player(client, "story-6")
    h = p["headers"]
    await client.get(f"/v1/cases/{c.id}", headers=h)
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["gains"]["warrants"] == 1  # tonight's case
    assert (await client.get("/v1/me", headers=h)).json()["warrants"] == 1
    # an archive case gives none
    old = content.by_id("c019")
    await client.post(f"/v1/cases/{old.id}/unlock", headers=h)
    r = (await client.post(f"/v1/cases/{old.id}/accuse", headers=h,
                           json={"suspect": old.culprit, "evidence": sorted(old.proof)[0]})).json()
    assert r["gains"]["warrants"] == 0


async def test_streak_milestone_gives_a_warrant(client, clock, no_missions):
    cases = content.all_cases()[-3:]
    p = await new_player(client, "story-7")
    h = p["headers"]
    got = []
    for c in cases:
        clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
        await client.get(f"/v1/cases/{c.id}", headers=h)
        r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                               json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
        got.append((r["streak"], r["gains"]["warrants"]))
    assert got == [(1, 1), (2, 1), (3, 2)]  # the third night in a row adds the streak warrant


async def test_all_missions_done_gives_one_warrant(client, clock, monkeypatch):
    c = content.by_id("c020")
    clock(datetime(c.publish.year, c.publish.month, c.publish.day, 22, 0, tzinfo=TEHRAN))
    monkeypatch.setattr(missions, "for_day", lambda day: [missions.BY_ID["daily_case"], missions.BY_ID["talk3"]])
    p = await new_player(client, "story-8")
    h = p["headers"]
    await client.get(f"/v1/cases/{c.id}", headers=h)
    ids = [s["id"] for s in c.data["suspects"]][:3]
    for sid in ids[:2]:
        r = (await client.post(f"/v1/cases/{c.id}/seen", headers=h, json={"suspect": sid})).json()
        assert r["gains"]["warrants"] == 0
    r = (await client.post(f"/v1/cases/{c.id}/seen", headers=h, json={"suspect": ids[2]})).json()
    assert r["gains"]["warrants"] == 0  # the case itself is still open
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["gains"]["warrants"] == 2  # tonight's case + the last mission done
    assert (await client.get("/v1/me", headers=h)).json()["warrants"] == 2
