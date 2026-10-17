"""App testers: the story is open for them while it is closed to everybody, and they never appear on a leaderboard."""
import pytest
from sqlalchemy import select

from app import content, db
from app.config import get_settings
from app.models import AdminLog, Player
from app.services import sms

from .conftest import ADMIN, new_player
from .test_phone import PHONE, _fake_sms, secure  # noqa: F401  (autouse fake SMS fixture + helper)
from .test_story import give, story  # noqa: F401  (five placeholder chapters)


async def make_tester(client, p, on=True):
    return await client.post("/admin/players/tester", headers=ADMIN, json={"phone": PHONE, "tester": on})


async def test_tester_flag_needs_admin_key_and_a_known_phone(client):
    p = await new_player(client, "tester-1")
    assert (await client.post("/admin/players/tester", json={"phone": PHONE})).status_code in (401, 403)
    assert (await make_tester(client, p)).json()["detail"] == "no_player"  # nobody has this phone yet
    assert (await client.post("/admin/players/tester", headers=ADMIN, json={"phone": "12345678901"})).status_code == 400


async def test_story_open_only_for_the_tester(client, story, monkeypatch):
    monkeypatch.setitem(content.STORY_SEASON, "opens_at", "2099-01-01T00:00:00")
    t = await new_player(client, "tester-2")
    other = await new_player(client, "tester-3")
    assert (await secure(client, t)).status_code == 200
    r = await make_tester(client, t)
    assert r.status_code == 200 and r.json()["tester"] is True
    assert (await client.get("/v1/story", headers=t["headers"])).json()["open"] is True
    assert (await client.post("/v1/story/1/open", headers=t["headers"])).status_code == 200
    assert (await client.get("/v1/cases/s01ch01", headers=t["headers"])).status_code == 200
    # everybody else still sees it closed
    assert (await client.get("/v1/story", headers=other["headers"])).json()["open"] is False
    assert (await client.post("/v1/story/1/open", headers=other["headers"])).json()["detail"] == "story_not_open"
    assert (await client.get("/v1/cases/s01ch01", headers=other["headers"])).status_code == 404
    # removing the flag closes it again
    assert (await make_tester(client, t, on=False)).json()["tester"] is False
    assert (await client.get("/v1/story", headers=t["headers"])).json()["open"] is False
    async with db.SessionLocal() as s:
        acts = [a.action for a in (await s.execute(select(AdminLog))).scalars().all()]
    assert "tester" in acts and "untester" in acts


async def test_tester_is_hidden_from_leaderboards(client):
    t = await new_player(client, "tester-4")
    other = await new_player(client, "tester-5")
    await give(t["player_id"], stars_total=50, cases_solved=5)
    await give(other["player_id"], stars_total=10, cases_solved=1)
    top = (await client.get("/v1/leaderboard?period=all", headers=other["headers"])).json()["top"]
    assert len(top) == 2
    assert (await secure(client, t)).status_code == 200
    assert (await make_tester(client, t)).status_code == 200
    top = (await client.get("/v1/leaderboard?period=all", headers=other["headers"])).json()["top"]
    assert [r["me"] for r in top] == [True]  # only the other player is left
    async with db.SessionLocal() as s:
        pl = await s.get(Player, t["player_id"])
    from app import anticheat as ac
    assert ac.is_visible(pl) is False
