"""«شکار سه‌روزه» (app/hunt.py, Amin 18 Nov 2026): hidden unless the config shows it, suspects leave on time, «منع خروج»
and early evidence cost coins once, one accusation, the answer never leaks before it is earned. SQLite and PostgreSQL."""
from datetime import datetime, timezone

import pytest
from sqlalchemy import delete

from app import db, gameclock, hunt
from app.models import ConfigValue, HuntState
from app.services import remote_config
from .conftest import ADMIN, new_player
from .test_difficulty_economy import balance, fund

START = int(datetime(2026, 11, 25, 18, 30, tzinfo=timezone.utc).timestamp())   # Wednesday 22:00 Tehran
H = 60


@pytest.fixture(autouse=True)
async def clean():
    async def wipe():
        async with db.SessionLocal() as s:
            await s.execute(delete(ConfigValue).where(ConfigValue.key == "hunt"))
            await s.execute(delete(HuntState))
            await s.commit()
        remote_config.invalidate()
    await wipe()
    yield
    gameclock.set_clock(None)
    await wipe()


def at_minute(m):
    gameclock.set_clock(lambda: datetime.fromtimestamp(START + m * 60, tz=timezone.utc))


async def configure(client, audience="testers"):
    r = await client.put("/admin/config", headers=ADMIN, json={"values": {"hunt": {
        "id": "h001", "audience": audience, "starts_at": START, "speed": 1}}})
    assert r.status_code == 200, r.text


async def make_tester(client, device):
    p = await new_player(client, device, aged=True)
    r = await client.post(f"/admin/api/players/{p['player_id']}/tester", headers=ADMIN, json={"tester": True})
    assert r.status_code == 200, r.text
    await fund(p["player_id"], 500)
    return p


async def test_hidden_from_players_who_are_not_testers(client):
    await configure(client)
    p = await new_player(client, "hunt-plain-1", aged=True)
    at_minute(10)
    r = await client.get("/v1/hunt", headers=p["headers"])
    assert r.json() == {"visible": False}
    assert (await client.post("/v1/hunt/early", headers=p["headers"])).status_code == 404


async def test_off_by_default_even_for_testers(client):
    p = await make_tester(client, "hunt-off-1")
    at_minute(10)
    assert (await client.get("/v1/hunt", headers=p["headers"])).json() == {"visible": False}


async def test_scheduled_shows_no_suspects_or_evidence(client):
    await configure(client)
    p = await make_tester(client, "hunt-sched-1")
    at_minute(-30)
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    assert j["status"] == "scheduled" and "suspects" not in j and "drops" not in j


async def test_timeline_and_no_answer_before_the_end(client):
    await configure(client)
    p = await make_tester(client, "hunt-time-1")
    at_minute(11 * H + 1)
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    gone = {s["id"] for s in j["suspects"] if s["gone"]}
    assert gone == {"s8"}                       # the driver left at Thursday 04:00
    opened = [d["id"] for d in j["drops"] if d["open"]]
    assert opened == ["d0", "d1"]
    assert all(not d["items"] for d in j["drops"] if not d["open"])
    text = str(j)
    assert "ending" not in j and "culprit" not in text and "e_contact" not in text
    assert j["schedule"] and all(e["at"] > j["now"] for e in j["schedule"])


async def test_hold_costs_once_and_keeps_the_suspect(client):
    await configure(client)
    p = await make_tester(client, "hunt-hold-1")
    at_minute(5 * H)
    r = await client.post("/v1/hunt/hold", headers=p["headers"], json={"suspect": "s8"})
    assert r.status_code == 200, r.text
    assert await balance(p["player_id"]) == 460
    again = await client.post("/v1/hunt/hold", headers=p["headers"], json={"suspect": "s8"})
    assert again.status_code == 409 and again.json()["detail"]["error"] == "already_held"
    at_minute(7 * H)    # past the old 04:00 departure, before the new 10:00 one
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    assert not next(s for s in j["suspects"] if s["id"] == "s8")["gone"]
    at_minute(12 * H)
    gone = await client.post("/v1/hunt/hold", headers=p["headers"], json={"suspect": "s8"})
    assert gone.status_code == 409


async def test_hold_without_coins_changes_nothing(client):
    await configure(client)
    p = await make_tester(client, "hunt-poor-1")
    await fund(p["player_id"], 10)
    at_minute(H)
    r = await client.post("/v1/hunt/hold", headers=p["headers"], json={"suspect": "s5"})
    assert r.status_code == 402
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    assert next(s for s in j["suspects"] if s["id"] == "s5")["held"] == 0


async def test_early_opens_the_next_drop(client):
    await configure(client)
    p = await make_tester(client, "hunt-early-1")
    at_minute(H)
    r = await client.post("/v1/hunt/early", headers=p["headers"])
    assert r.status_code == 200, r.text
    d1 = next(d for d in r.json()["drops"] if d["id"] == "d1")
    assert d1["open"] and d1["early"] and d1["items"]
    assert await balance(p["player_id"]) == 440


async def test_accuse_once_with_visible_evidence(client):
    await configure(client)
    p = await make_tester(client, "hunt-acc-1")
    at_minute(18 * H)    # after Aghdas (Thursday 15:00): the tripod is visible, the photos are not
    hidden = await client.post("/v1/hunt/accuse", headers=p["headers"], json={"suspect": "s5", "evidence": "e_contact"})
    assert hidden.status_code == 409 and hidden.json()["detail"]["error"] == "no_evidence"
    gone = await client.post("/v1/hunt/accuse", headers=p["headers"], json={"suspect": "s6", "evidence": "e_tripod"})
    assert gone.status_code == 409 and gone.json()["detail"]["error"] == "gone"
    r = await client.post("/v1/hunt/accuse", headers=p["headers"], json={"suspect": "s5", "evidence": "e_tripod"})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["mine"]["solved"] and j["mine"]["stars"] == 3 and j["reward"] == 300
    assert await balance(p["player_id"]) == 800
    twice = await client.post("/v1/hunt/accuse", headers=p["headers"], json={"suspect": "s5", "evidence": "e_tripod"})
    assert twice.status_code == 409
    assert j["collective"]["solved"] == 1
    at_minute(37 * H)    # the culprit was accused: she does not leave, and her messages stop
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    assert not next(s for s in j["suspects"] if s["id"] == "s5")["gone"]
    assert "m4" not in [m["id"] for m in j["messages"]]


async def test_wrong_accusation_pays_nothing_and_ending_comes_at_the_deadline(client):
    await configure(client)
    p = await make_tester(client, "hunt-wrong-1")
    at_minute(20 * H)
    r = await client.post("/v1/hunt/accuse", headers=p["headers"], json={"suspect": "s4", "evidence": "e_check"})
    assert r.status_code == 200 and r.json()["mine"]["solved"] is False and r.json()["reward"] == 0
    assert await balance(p["player_id"]) == 500
    at_minute(47 * H + 5)
    j = (await client.get("/v1/hunt", headers=p["headers"])).json()
    assert j["status"] == "ended" and j["ending"]["culprit"] == "s5" and j["ending"]["reached"] is False
    assert (await client.post("/v1/hunt/early", headers=p["headers"])).json()["detail"]["error"] == "hunt_over"


async def test_admin_card_and_reset(client):
    r = await client.post("/admin/api/hunt", headers=ADMIN, json={"audience": "testers", "start": str(START), "speed": 60})
    assert r.status_code == 200, r.text
    assert r.json()["config"]["speed"] == 60 and r.json()["config"]["starts_at"] == START
    p = await make_tester(client, "hunt-admin-1")
    at_minute(0)
    await client.get("/v1/hunt", headers=p["headers"])
    v = (await client.get("/admin/api/hunt", headers=ADMIN)).json()
    assert v["stats"]["players"] == 1
    assert (await client.post("/admin/api/hunt/reset", headers=ADMIN)).json()["stats"]["players"] == 0
    await client.post("/admin/api/hunt", headers=ADMIN, json={"audience": "all", "start": str(START), "speed": 1})
    assert (await client.post("/admin/api/hunt/reset", headers=ADMIN)).status_code == 409


async def test_images_only_from_the_hunt_folder(client):
    assert (await client.get("/hunt-img/h001/..%2Fhunt.webp")).status_code == 404
    assert (await client.get("/hunt-img/x/map.webp")).status_code == 404


def test_content_is_consistent():
    h = hunt.load("h001")
    ids = {s["id"] for s in h["suspects"]}
    items = set(h["items"])
    for d in h["drops"]:
        assert set(d["items"]) <= items
    for m in h["messages"]:
        if m.get("evidence"):
            assert m["evidence"] in items
    a = h["answer"]
    assert a["culprit"] in ids and set(a["strong"] + a["partial"]) <= items
    leaves = sorted(s["leave"] for s in h["suspects"] if s["leave"] is not None)
    assert leaves == sorted(set(leaves)) and leaves[-1] < h["duration_minutes"]
    culprit = next(s for s in h["suspects"] if s["id"] == a["culprit"])
    strong_at = min(d["minute"] for d in h["drops"] if set(d["items"]) & set(a["strong"]))
    assert strong_at < culprit["leave"], "the proof must arrive before the culprit leaves"
    from pathlib import Path
    shipped = {p.stem for p in (Path(__file__).resolve().parents[2] / "app" / "assets" / "portraits").glob("*.webp")}
    assert {s["portrait"] for s in h["suspects"]} | {h["victim"]["portrait"]} <= shipped
