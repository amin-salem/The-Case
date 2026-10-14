"""Avatars and frames: ownership, the shop, refused picks and unlocks by goal."""
from sqlalchemy import update

from app import avatars, db
from app import economy as eco
from app.models import Player

from .conftest import new_player


async def _set(pid, **vals):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(**vals))
        await s.commit()


def _by_id(lst, i):
    return next(x for x in lst if x["id"] == i)


def test_catalog_matches_prices_and_frames():
    assert {i.id for i in avatars.AVATARS if i.how == "shop"} == set(eco.AVATAR_PRICE)
    assert {i.id for i in avatars.FRAMES if i.how == "shop"} == set(eco.FRAME_PRICE)
    assert eco.FRAME_PRICE == {"frame_fingerprint": 300, "frame_blinds": 400, "frame_cuffs": 600,
                               "frame_stamp": 600, "frame_neon": 900, "frame_royal": 1500}
    assert [i.id for i in avatars.FRAMES if i.how == "goal"] == [
        "frame_bronze", "frame_silver", "frame_gold", "frame_ember", "frame_tape", "frame_loupe"]
    assert len(avatars.BY_ID) == len(avatars.AVATARS) + len(avatars.FRAMES)


async def test_list_defaults_and_old_profiles(client):
    p = await new_player(client, "av-list-1")
    h = p["headers"]
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["avatar_id"] == "det_01" and me["avatar_frame"] == "frame_brass"
    r = (await client.get("/v1/avatars", headers=h)).json()
    assert _by_id(r["avatars"], "det_05")["owned"] and _by_id(r["frames"], "frame_brass")["owned"]
    cat = _by_id(r["avatars"], "ex_cat")
    assert not cat["owned"] and cat["price"] == 800
    nh = _by_id(r["avatars"], "ex_rookie")
    assert not nh["owned"] and nh["target"] == 10 and nh["progress"] == 0 and nh["goal"]
    await client.patch("/v1/me", headers=h, json={"avatar": 3})  # an old app picks the 4th portrait
    assert (await client.get("/v1/me", headers=h)).json()["avatar_id"] == "det_04"


async def test_buy_once_and_equip(client):
    p = await new_player(client, "av-buy-1")
    h = p["headers"]
    await _set(p["player_id"], coins=2000)
    r = await client.post("/v1/avatars/ex_cat/buy", headers=h)
    assert r.status_code == 200 and r.json()["coins"] == 1200
    assert _by_id(r.json()["avatars"], "ex_cat")["owned"]
    again = await client.post("/v1/avatars/ex_cat/buy", headers=h)
    assert again.status_code == 409 and (await client.get("/v1/avatars", headers=h)).json()["coins"] == 1200
    r = await client.patch("/v1/me", headers=h, json={"avatar_id": "ex_cat"})
    assert r.status_code == 200 and r.json()["avatar_id"] == "ex_cat"


async def test_frame_buy_and_equip(client):
    p = await new_player(client, "av-frame-1")
    h = p["headers"]
    await _set(p["player_id"], coins=1000)
    assert (await client.post("/v1/avatars/frame_neon/buy", headers=h)).json()["coins"] == 100
    r = await client.patch("/v1/me", headers=h, json={"avatar_frame": "frame_neon"})
    assert r.json()["avatar_frame"] == "frame_neon"
    lb = (await client.get("/v1/leaderboard?period=all", headers=h)).status_code
    assert lb in (200, 404)


async def test_not_enough_coins_and_unbuyable(client):
    p = await new_player(client, "av-poor-1")
    h = p["headers"]
    await _set(p["player_id"], coins=100)
    r = await client.post("/v1/avatars/ex_gold/buy", headers=h)
    assert r.status_code == 402 and r.json()["detail"]["need"] == 2500
    assert (await client.get("/v1/avatars", headers=h)).json()["coins"] == 100
    assert (await client.post("/v1/avatars/ex_rookie/buy", headers=h)).status_code == 422   # goals are not for sale
    assert (await client.post("/v1/avatars/det_01/buy", headers=h)).status_code == 422
    assert (await client.post("/v1/avatars/nope/buy", headers=h)).status_code == 404


async def test_locked_pick_refused(client):
    p = await new_player(client, "av-locked-1")
    h = p["headers"]
    for body in ({"avatar_id": "ex_cat"}, {"avatar_id": "ex_rookie"}, {"avatar_frame": "frame_royal"},
                 {"avatar_frame": "frame_tape"}, {"avatar_id": "frame_brass"}, {"avatar_frame": "det_01"},
                 {"avatar_id": "bogus"}):
        r = await client.patch("/v1/me", headers=h, json=body)
        assert r.status_code == 422 and r.json()["detail"] == "not_owned", body
    assert (await client.patch("/v1/me", headers=h, json={"avatar_id": "det_07", "avatar_frame": "frame_brass"})).status_code == 200


async def test_unlock_by_goal_with_gains(client):
    p = await new_player(client, "av-goal-1")
    h = p["headers"]
    await _set(p["player_id"], cases_solved=10, best_streak=14, xp=eco.RANKS[5][0])
    r = (await client.get("/v1/avatars", headers=h)).json()
    assert {g["id"] for g in r["gains"]["avatars"]} == {"ex_rookie", "ex_nightowl", "frame_ember", "frame_bronze", "frame_silver"}
    assert _by_id(r["avatars"], "ex_rookie")["owned"] and not _by_id(r["avatars"], "ex_ironstreak")["owned"]
    assert _by_id(r["avatars"], "ex_ironstreak")["progress"] == 14
    assert "gains" not in (await client.get("/v1/avatars", headers=h)).json()   # celebrated once
    assert (await client.patch("/v1/me", headers=h, json={"avatar_id": "ex_rookie", "avatar_frame": "frame_ember"})).status_code == 200
    await _set(p["player_id"], best_streak=0, streak=0)  # once earned, kept
    assert _by_id((await client.get("/v1/avatars", headers=h)).json()["avatars"], "ex_nightowl")["owned"]


async def test_champion_by_weekly_top3_and_story(client):
    p = await new_player(client, "av-champ-1")
    h = p["headers"]
    await _set(p["player_id"], stats={"weekly_top3": 1, "weekly_solved": 3})
    ids = {g["id"] for g in (await client.get("/v1/avatars", headers=h)).json()["gains"]["avatars"]}
    assert ids == {"ex_champion", "frame_loupe", "ex_weekend"}
    from datetime import datetime

    from app.models import StoryProgress
    async with db.SessionLocal() as s:
        s.add(StoryProgress(player_id=p["player_id"], season=1, chapter=5, finished_at=datetime(2026, 1, 1), solved=True))
        await s.commit()
    ids = {g["id"] for g in (await client.get("/v1/avatars", headers=h)).json()["gains"]["avatars"]}
    assert ids == {"ex_partner"}
