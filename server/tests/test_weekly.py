"""The weekend's big case: free for all, opens in chapters, and solving it needs the motive too."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


def test_weekly_content_is_valid():
    cases = content.weekly_cases()
    assert cases and all(c.publish.weekday() == 3 for c in cases)  # Thursdays
    w = cases[0]
    assert len(w.data["suspects"]) == 8 and len(w.data["evidence"]) >= 15
    late = {e for ch in w.data["chapters"][1:] for e in ch.get("evidence", [])}
    assert w.proof <= late  # the proof only shows up in a later chapter


async def test_chapters_open_over_the_weekend(client, clock):
    w = content.weekly_cases()[0]
    start = content.opens_at(w)
    p = await new_player(client, "weekender-1")
    h = p["headers"]

    clock(start - timedelta(minutes=5))
    assert (await client.get("/v1/cases", headers=h)).json()["weekly"] is None
    assert (await client.get(f"/v1/cases/{w.id}", headers=h)).status_code == 404

    clock(start + timedelta(minutes=5))
    lst = (await client.get("/v1/cases", headers=h)).json()
    assert lst["weekly"]["id"] == w.id and not lst["weekly"]["locked"] and lst["weekly_closes_at"]
    case = (await client.get(f"/v1/cases/{w.id}", headers=h)).json()["case"]
    shown = {e["id"] for e in case["evidence"]}
    late = {e for ch in w.data["chapters"][1:] for e in ch.get("evidence", [])}
    assert shown.isdisjoint(late) and len(case["chapters"]) == 1 and case["next_chapter_at"]
    assert "solution" not in case and "hints" not in case and len(case["motives"]) == 3

    clock(start + timedelta(hours=25))
    case = (await client.get(f"/v1/cases/{w.id}", headers=h)).json()["case"]
    assert {e["id"] for e in case["evidence"]} == {e["id"] for e in w.data["evidence"]}
    assert len(case["chapters"]) == case["chapters_total"] and case["next_chapter_at"] is None

    clock(start + timedelta(days=3))  # Sunday 00:00: no longer this weekend's case
    assert (await client.get("/v1/cases", headers=h)).json()["weekly"] is None


async def test_solving_needs_the_motive(client, clock):
    w = content.weekly_cases()[0]
    clock(content.opens_at(w) + timedelta(hours=26))
    p = await new_player(client, "weekender-2")
    h = p["headers"]
    await client.get(f"/v1/cases/{w.id}", headers=h)
    proof = sorted(w.proof)[0]
    right = w.data["solution"]["motive"]
    wrong = next(m["id"] for m in w.data["motives"] if m["id"] != right)
    r = (await client.post(f"/v1/cases/{w.id}/accuse", headers=h,
                           json={"suspect": w.culprit, "evidence": proof, "motive": wrong})).json()
    assert r["result"] == "wrong_motive" and r["attempts_left"] == eco.MAX_ATTEMPTS
    r = (await client.post(f"/v1/cases/{w.id}/accuse", headers=h,
                           json={"suspect": w.culprit, "evidence": proof, "motive": right})).json()
    assert r["result"] == "solved" and r["stars"] == 2 and r["reward"] == eco.WEEKLY_REWARD[2]
    assert r["streak"] == 0  # the weekend case doesn't touch the nightly streak
    done = (await client.get(f"/v1/cases/{w.id}", headers=h)).json()["case"]
    assert done["solution"]["motive"] == right
