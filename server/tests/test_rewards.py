from datetime import date, timedelta

from sqlalchemy import delete

from app import content, db, rewards
from app.models import CaseProgress, InboxItem

from .conftest import new_player


async def test_weekly_prize_paid_once_and_in_inbox(client):
    prev = content.week_start(date.fromisoformat(content.today_str())) - timedelta(days=7)
    async with db.SessionLocal() as s:
        await s.execute(delete(InboxItem).where(InboxItem.source == rewards.source_for(prev)))
        await s.commit()
    p = await new_player(client, "device-reward-1")
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=p["player_id"], case_id="zz1", solved=True, stars=999,
                           day=(prev + timedelta(days=2)).isoformat()))
        await s.commit()
    items = (await client.get("/v1/inbox", headers=p["headers"])).json()
    prizes = [i for i in items if i["title"].startswith("جایزه‌ی هفته")]
    assert len(prizes) == 1 and prizes[0]["grants"] == [{"type": "coins", "amount": 300}]
    again = (await client.get("/v1/inbox", headers=p["headers"])).json()
    assert len([i for i in again if i["title"].startswith("جایزه‌ی هفته")]) == 1
    async with db.SessionLocal() as s:
        assert await rewards.settle_last_week(s) == 0
