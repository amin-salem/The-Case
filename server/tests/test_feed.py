"""The messages hub feed: ordering, unread count, seen idempotency, bounds, and gifts still pay once."""
from datetime import timedelta

from app import db
from app.models import InboxItem, Player, utcnow

from .conftest import ADMIN, new_player


async def give(pid: str, n: int, age_hours: float, title: str = "هدیه") -> None:
    async with db.SessionLocal() as s:
        for i in range(n):
            s.add(InboxItem(player_id=pid, title=f"{title} {i}", message="m", grants=[{"type": "coins", "amount": 10}],
                            created_at=utcnow() - timedelta(hours=age_hours + i * 0.01)))
        await s.commit()


async def test_feed_order_and_unread(client):
    p = await new_player(client, "feed-1")
    h = p["headers"]
    await give(p["player_id"], 1, 5, "قدیمی")
    await give(p["player_id"], 1, 1, "تازه")
    r = (await client.get("/v1/feed", headers=h)).json()
    ats = [i["at"] for i in r["items"]]
    assert ats == sorted(ats, reverse=True)
    gifts = [i for i in r["items"] if i["kind"] == "gift"]
    assert [g["title"] for g in gifts] == ["تازه 0", "قدیمی 0"]
    assert gifts[0]["gift_id"] and gifts[0]["reward"] == 10
    assert r["unread"] == len(r["items"]) > 0
    assert (await client.get("/v1/me", headers=h)).json()["unread"] >= len(gifts)  # + anything /me just granted


async def test_seen_is_idempotent_and_new_items_are_unread(client):
    p = await new_player(client, "feed-2")
    h = p["headers"]
    await give(p["player_id"], 2, 3)
    a = (await client.post("/v1/feed/seen", headers=h)).json()
    b = (await client.post("/v1/feed/seen", headers=h)).json()
    assert a["unread"] == 0 and b["unread"] == 0
    assert (await client.get("/v1/me", headers=h)).json()["unread"] == 0
    async with db.SessionLocal() as s:
        pl = await s.get(Player, p["player_id"])
        pl.feed_seen_at = utcnow() - timedelta(hours=1)
        await s.commit()
    await give(p["player_id"], 1, 0.5, "بعدی")  # newer than "seen"
    r = (await client.get("/v1/feed", headers=h)).json()
    assert r["unread"] >= 1 and any(i["unread"] and i["title"].startswith("بعدی") for i in r["items"])


async def test_feed_is_bounded_and_windowed(client):
    p = await new_player(client, "feed-3")
    h = p["headers"]
    await give(p["player_id"], 60, 2)
    await give(p["player_id"], 1, 24 * 20, "خیلی قدیمی")
    r = (await client.get("/v1/feed", headers=h)).json()
    assert len(r["items"]) == 40
    assert not any(i["title"].startswith("خیلی قدیمی") for i in r["items"])
    assert (await client.get("/v1/feed")).status_code == 401


async def test_feed_is_private_to_the_player(client):
    a = await new_player(client, "feed-4a")
    b = await new_player(client, "feed-4b")
    await give(a["player_id"], 1, 1, "فقط-الف")
    r = (await client.get("/v1/feed", headers=b["headers"])).json()
    assert not any(i["title"].startswith("فقط-الف") for i in r["items"])


async def test_claiming_a_gift_from_the_feed_pays_once(client):
    p = await new_player(client, "feed-5")
    h = p["headers"]
    sent = (await client.post("/admin/gifts", headers=ADMIN, json={
        "title": "پاداش", "grants": [{"type": "coins", "amount": 77}], "player_id": p["player_id"]})).json()
    r = (await client.get("/v1/feed", headers=h)).json()
    gift = next(i for i in r["items"] if i["gift_id"] == sent["id"])
    before = (await client.get("/v1/me", headers=h)).json()["coins"]
    assert (await client.post(f"/v1/inbox/{gift['gift_id']}/claim", headers=h)).status_code == 200
    assert (await client.post(f"/v1/inbox/{gift['gift_id']}/claim", headers=h)).status_code == 409
    assert (await client.get("/v1/me", headers=h)).json()["coins"] == before + 77
    again = (await client.get("/v1/feed", headers=h)).json()
    assert next(i for i in again["items"] if i["id"] == sent["id"])["gift_id"] is None  # no longer claimable


async def test_story_openings_are_not_listed_while_paused(client):
    p = await new_player(client, "feed-6")
    r = (await client.get("/v1/feed", headers=p["headers"])).json()
    assert not any(i["kind"] == "story" for i in r["items"])
