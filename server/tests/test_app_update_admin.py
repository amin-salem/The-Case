"""Admin: app update notice (services/app_update.py). The banner is only a number in the remote config; the panel block
must save it safely, never lock players out by accident, and keep the audit trail. Runs on SQLite and PostgreSQL."""
import pytest
from sqlalchemy import delete, func, select, update

from app import db
from app.models import AdminLog, ConfigValue, Player
from app.services import remote_config
from .conftest import ADMIN, new_player

URL = "/admin/api/app-update"


@pytest.fixture(autouse=True)
async def clean(client):
    async def wipe():
        async with db.SessionLocal() as s:
            await s.execute(delete(ConfigValue).where(ConfigValue.key.in_(["latest_version", "min_version", "update_url"])))
            await s.commit()
        remote_config.invalidate()
    await wipe()
    yield
    await wipe()


async def set_build(pid, build):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(client_build=build))
        await s.commit()
    return pid


async def test_needs_admin_key(client):
    assert (await client.get(URL)).status_code in (401, 403)
    assert (await client.post(URL, json={"latest_version": 5})).status_code in (401, 403)


async def test_save_shows_in_app_config_and_counts_players(client):
    p = await new_player(client, "dev-au-1")
    await set_build(p["player_id"], 80)
    r = await client.post(URL, headers=ADMIN, json={"latest_version": 86})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["latest_version"] == 86 and body["min_version"] == 1
    assert body["banner_now"] >= 1 and body["blocked_now"] == 0
    cfg = (await client.get("/v1/config")).json()
    assert cfg["latest_version"] == 86          # the app reads exactly this
    async with db.SessionLocal() as s:
        assert (await s.scalar(select(func.count()).select_from(AdminLog).where(AdminLog.action == "app_update"))) >= 1


async def test_bad_values_change_nothing(client):
    for body in ({"latest_version": 0}, {"latest_version": 100000}, {"latest_version": "x"},
                 {"latest_version": 10, "min_version": 11}, {"latest_version": 10, "update_url": "javascript:alert(1)"},
                 {"latest_version": 10, "update_url": "ftp://x.ir/a"}):
        assert (await client.post(URL, headers=ADMIN, json=body)).status_code == 422, body
    assert (await client.get(URL, headers=ADMIN)).json()["latest_version"] == 1


async def test_blocking_active_players_needs_confirmation(client):
    p = await new_player(client, "dev-au-2")
    await set_build(p["player_id"], 70)
    r = await client.post(URL, headers=ADMIN, json={"latest_version": 86, "min_version": 80})
    assert r.status_code == 409 and "confirm_block" in r.text
    assert (await client.get(URL, headers=ADMIN)).json()["min_version"] == 1     # nothing saved
    ok = await client.post(URL, headers=ADMIN, json={"latest_version": 86, "min_version": 80, "confirm_block": True})
    assert ok.status_code == 200 and ok.json()["blocked_now"] >= 1
    # lowering it again never needs a confirmation
    assert (await client.post(URL, headers=ADMIN, json={"latest_version": 86, "min_version": 1})).status_code == 200


async def test_old_apps_without_a_build_are_counted_apart(client):
    p = await new_player(client, "dev-au-3")
    await set_build(p["player_id"], 0)
    body = (await client.get(URL, headers=ADMIN)).json()
    assert body["unknown_build"] >= 1                      # they cannot show a banner, so they are listed separately
    assert all(x["build"] > 0 for x in body["builds"] if x["build"] != 0) 
