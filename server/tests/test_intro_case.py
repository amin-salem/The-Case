"""The free first case «intro01»: only for a player with no solved case, never in the archive or the schedule, kill switch."""
import pytest
from sqlalchemy import update

from app import content, db
from app.config import get_settings
from app.models import Player
from .conftest import new_player


def test_intro_is_valid_and_outside_the_schedule():
    c = content.intro_by_id(content.INTRO_ID)
    assert c is not None and c.data["difficulty"] in (1, 2) and len(c.data["suspects"]) <= 4
    assert content.INTRO_ID not in {x.id for x in content.all_cases()}
    assert content.intro_by_id("intro../x") is None and content.intro_by_id("intro99") is None


async def test_new_player_sees_the_intro_row_and_can_solve_it(client):
    p = await new_player(client, "intro-new")
    h = p["headers"]
    j = (await client.get("/v1/cases", headers=h)).json()
    assert j["intro"]["id"] == "intro01" and j["intro"]["locked"] is False
    assert all(r["id"] != "intro01" for r in j["archive"])
    got = await client.get("/v1/cases/intro01", headers=h)
    assert got.status_code == 200
    body = got.json()["case"]
    assert "solution" not in body and "hints" not in body
    c = content.intro_by_id("intro01")
    wrong = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    r = await client.post("/v1/cases/intro01/accuse", headers=h, json={"suspect": wrong, "evidence": sorted(c.proof)[0]})
    assert r.status_code == 200 and r.json()["result"] != "solved"
    r = await client.post("/v1/cases/intro01/accuse", headers=h, json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})
    assert r.status_code == 200 and r.json()["result"] == "solved"


async def test_a_player_who_solved_cases_does_not_see_it_unless_opened(client):
    p = await new_player(client, "intro-old")
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p["player_id"]).values(cases_solved=3))
        await s.commit()
    assert (await client.get("/v1/cases", headers=p["headers"])).json()["intro"] is None


async def test_kill_switch_hides_and_refuses(client, monkeypatch):
    monkeypatch.setattr(get_settings(), "intro_case_enabled", False)
    p = await new_player(client, "intro-off")
    assert (await client.get("/v1/cases", headers=p["headers"])).json()["intro"] is None
    assert (await client.get("/v1/cases/intro01", headers=p["headers"])).status_code == 404


async def test_unknown_intro_id_is_404(client):
    p = await new_player(client, "intro-404")
    assert (await client.get("/v1/cases/intro02", headers=p["headers"])).status_code == 404
