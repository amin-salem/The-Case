"""Update thank-you coins (services/app_update.grant_bonus, paid inside POST /v1/me/client): once per player per
`latest_version`, only for a real update, never for a new install or a downgrade, and never twice under a race.
Runs on SQLite and PostgreSQL."""
import asyncio

import pytest
from sqlalchemy import delete, func, select, update

from app import db
from app.models import CoinLog, ConfigValue, Player
from app.services import remote_config
from .conftest import ADMIN, new_player

KEYS = ["latest_version", "min_version", "update_bonus_coins"]


@pytest.fixture(autouse=True)
async def clean(client):
    async def wipe():
        async with db.SessionLocal() as s:
            await s.execute(delete(ConfigValue).where(ConfigValue.key.in_(KEYS)))
            await s.commit()
        remote_config.invalidate()
    await wipe()
    yield
    await wipe()


async def set_cfg(**values):
    async with db.SessionLocal() as s:
        for k, v in values.items():
            s.add(ConfigValue(key=k, value=v))
        await s.commit()
    remote_config.invalidate()


async def set_build(pid, build):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(client_build=build, app_version=build))
        await s.commit()


def report(client, p, build):
    return client.post("/v1/me/client", headers=p["headers"], json={"app_version": "1.0", "build": build})


async def coins(pid):
    async with db.SessionLocal() as s:
        return await s.scalar(select(Player.coins).where(Player.id == pid))


async def paid_rows(pid):
    async with db.SessionLocal() as s:
        return await s.scalar(select(func.count()).select_from(CoinLog).where(
            CoinLog.player_id == pid, CoinLog.reason.like("update_bonus:%")))


async def test_update_pays_once_and_says_how_much(client):
    await set_cfg(latest_version=90)
    p = await new_player(client, "dev-ub-1")
    await set_build(p["player_id"], 80)
    before = await coins(p["player_id"])
    r = await report(client, p, 90)
    assert r.status_code == 200 and r.json()["bonus_coins"] == 50
    assert await coins(p["player_id"]) == before + 50
    again = await report(client, p, 90)          # repeat: nothing more
    assert again.json()["bonus_coins"] == 0
    await set_build(p["player_id"], 80)          # went back and updated again: still the same latest_version
    assert (await report(client, p, 91)).json()["bonus_coins"] == 0
    assert await coins(p["player_id"]) == before + 50 and await paid_rows(p["player_id"]) == 1


async def test_new_install_and_unknown_build_get_nothing(client):
    await set_cfg(latest_version=90)
    fresh = await new_player(client, "dev-ub-2")
    await set_build(fresh["player_id"], 90)      # signed up on the current build
    assert (await report(client, fresh, 90)).json()["bonus_coins"] == 0
    old = await new_player(client, "dev-ub-3")
    await set_build(old["player_id"], 0)         # an app that never reported: no known previous build
    assert (await report(client, old, 90)).json()["bonus_coins"] == 0
    assert await paid_rows(fresh["player_id"]) == 0 and await paid_rows(old["player_id"]) == 0


async def test_downgrade_or_partial_update_gets_nothing(client):
    await set_cfg(latest_version=90)
    p = await new_player(client, "dev-ub-4")
    await set_build(p["player_id"], 70)
    assert (await report(client, p, 60)).json()["bonus_coins"] == 0     # went down
    assert (await report(client, p, 85)).json()["bonus_coins"] == 0     # up, but still below latest
    assert await paid_rows(p["player_id"]) == 0


async def test_new_latest_version_pays_again_once(client):
    await set_cfg(latest_version=90)
    p = await new_player(client, "dev-ub-5")
    await set_build(p["player_id"], 80)
    assert (await report(client, p, 90)).json()["bonus_coins"] == 50
    async with db.SessionLocal() as s:
        row = await s.get(ConfigValue, "latest_version")
        row.value = 95
        await s.commit()
    remote_config.invalidate()
    assert (await report(client, p, 95)).json()["bonus_coins"] == 50
    assert await paid_rows(p["player_id"]) == 2


async def test_off_default_and_bounds(client):
    await set_cfg(latest_version=90, update_bonus_coins=0)
    p = await new_player(client, "dev-ub-6")
    await set_build(p["player_id"], 80)
    assert (await report(client, p, 90)).json()["bonus_coins"] == 0
    for bad, expect in ((10**9, 300), ("x", 50), (-5, 0), (True, 50)):
        async with db.SessionLocal() as s:
            row = await s.get(ConfigValue, "update_bonus_coins")
            row.value = bad
            await s.commit()
        remote_config.invalidate()
        from app.services import app_update
        async with db.SessionLocal() as s:
            assert app_update.bonus_coins(await remote_config.load_config(s)) == expect


async def test_race_pays_once(client):
    await set_cfg(latest_version=90)
    p = await new_player(client, "dev-ub-7")
    await set_build(p["player_id"], 80)
    before = await coins(p["player_id"])
    rs = await asyncio.gather(*[report(client, p, 90) for _ in range(4)])
    assert all(r.status_code == 200 for r in rs)
    assert sorted(r.json()["bonus_coins"] for r in rs)[-1] == 50
    assert await paid_rows(p["player_id"]) == 1 and await coins(p["player_id"]) == before + 50


async def test_config_and_admin_block(client):
    cfg = (await client.get("/v1/config")).json()
    assert cfg["update_bonus_coins"] == 50
    await set_cfg(latest_version=90)
    p = await new_player(client, "dev-ub-8")
    await set_build(p["player_id"], 80)
    await report(client, p, 90)
    v = (await client.get("/admin/api/app-update", headers=ADMIN)).json()
    assert v["bonus_paid"] == 1 and v["update_bonus_coins"] == 50
    r = await client.post("/admin/api/app-update", headers=ADMIN,
                          json={"latest_version": 90, "min_version": 1, "update_bonus_coins": 120})
    assert r.status_code == 200 and r.json()["update_bonus_coins"] == 120
    assert (await client.get("/v1/config")).json()["update_bonus_coins"] == 120
    bad = await client.post("/admin/api/app-update", headers=ADMIN,
                            json={"latest_version": 90, "min_version": 1, "update_bonus_coins": 301})
    assert bad.status_code == 422
