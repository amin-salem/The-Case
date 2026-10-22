import pytest
from datetime import date, datetime
from types import SimpleNamespace
from zoneinfo import ZoneInfo

from app import content, db, gameclock, rewards, weekboard
from app.models import CaseProgress

from .conftest import new_player

TEHRAN = ZoneInfo("Asia/Tehran")


@pytest.fixture(autouse=True)
def _points_order(monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "week_rank_mode", "points")


async def test_weekly_prize_paid_once_and_in_inbox(client, monkeypatch):
    ws = date(2027, 6, 4)   # a Friday; fake cases, so no other test's solves are on this board
    monkeypatch.setattr(content, "week_cases", lambda w: [SimpleNamespace(id=f"zr{w.isoformat()}-{i}") for i in range(7)])
    monkeypatch.setattr(weekboard, "leagues_on", lambda: False)
    monkeypatch.setattr(content, "now_local", lambda: datetime(2027, 6, 11, 22, 0, tzinfo=TEHRAN))  # the week closed at 21:00
    p = await new_player(client, "device-reward-1")
    async with db.SessionLocal() as s:
        for i in range(2):
            s.add(CaseProgress(player_id=p["player_id"], case_id=f"zr{ws.isoformat()}-{i}", solved=True, stars=3, ranked=True,
                               seconds=90, finished_at=gameclock.to_utc_naive(datetime(2027, 6, 5 + i, 10, 0, tzinfo=TEHRAN))))
        await s.commit()
    items = (await client.get("/v1/inbox", headers=p["headers"])).json()
    prizes = [i for i in items if i["title"].startswith("جایزه‌ی هفته")]
    assert len(prizes) == 1 and prizes[0]["grants"] == [{"type": "coins", "amount": 300}]
    again = (await client.get("/v1/inbox", headers=p["headers"])).json()
    assert len([i for i in again if i["title"].startswith("جایزه‌ی هفته")]) == 1
    async with db.SessionLocal() as s:
        assert await rewards.settle_last_week(s) == 0
