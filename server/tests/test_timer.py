"""Fair solving time: only the time the case screen was open counts."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import content, models
from app import economy as eco

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture
def clock(monkeypatch):
    """Moves both the Tehran clock and the UTC clock the server stores times with."""
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        utc = dt.astimezone(ZoneInfo("UTC")).replace(tzinfo=None)
        monkeypatch.setattr(models, "utcnow", lambda: utc)
        import app.routers.cases as cases
        monkeypatch.setattr(cases, "utcnow", lambda: utc)
        return dt
    return set_to


async def test_time_away_does_not_count(client, clock):
    c = content.by_id("c033")
    start = datetime(c.publish.year, c.publish.month, c.publish.day, 21, 5, tzinfo=TEHRAN)
    clock(start)
    p = await new_player(client, "timer-1")
    h = p["headers"]
    assert (await client.get(f"/v1/cases/{c.id}", headers=h)).status_code == 200
    # two minutes of reading, reported in two ticks
    clock(start + timedelta(seconds=60))
    assert (await client.post(f"/v1/cases/{c.id}/tick", headers=h, json={"seconds": 60})).json()["active_seconds"] == 60
    clock(start + timedelta(seconds=120))
    assert (await client.post(f"/v1/cases/{c.id}/tick", headers=h, json={"seconds": 60})).json()["active_seconds"] == 120
    # a tick can't claim more than really passed, nor more than TICK_MAX
    clock(start + timedelta(seconds=130))
    assert (await client.post(f"/v1/cases/{c.id}/tick", headers=h, json={"seconds": 100})).json()["active_seconds"] == 135
    # the player leaves for almost a day, comes back and solves it in 40 more seconds
    clock(start + timedelta(hours=23))
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0], "extra_seconds": 40})).json()
    assert r["result"] == "solved" and r["seconds"] == 175
    # finished: ticks change nothing
    assert (await client.post(f"/v1/cases/{c.id}/tick", headers=h, json={"seconds": 60})).json()["active_seconds"] == 175


async def test_old_apps_still_get_clock_time(client, clock):
    c = content.by_id("c034")
    start = datetime(c.publish.year, c.publish.month, c.publish.day, 21, 5, tzinfo=TEHRAN)
    clock(start)
    p = await new_player(client, "timer-2")
    h = p["headers"]
    await client.get(f"/v1/cases/{c.id}", headers=h)
    clock(start + timedelta(minutes=7))
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved" and abs(r["seconds"] - 420) <= 2
    assert eco.TICK_MAX >= 60
