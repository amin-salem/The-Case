"""The culprit album (app/album.py) and the first-guess feature (app/guess.py): behaviour, abuse paths, no spoilers."""
from datetime import timedelta

import pytest
from sqlalchemy import update

from app import album, content, db, guess
from app.models import CaseGuess, Player

from .conftest import new_player


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


async def _solve(client, h, cid):
    c = content.by_id(cid)
    await client.get(f"/v1/cases/{cid}", headers=h)
    r = await client.post(f"/v1/cases/{cid}/accuse", headers=h, json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})
    assert r.json()["result"] == "solved", r.text
    return r.json()


async def _unlock_all(pid):
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == pid).values(coins=100000))
        await s.commit()


async def _open(client, h, cid):
    r = await client.post(f"/v1/cases/{cid}/unlock", headers=h)
    assert r.status_code == 200, r.text


def test_group_function_is_the_one_place():
    for c in content.all_cases():
        key, name, icon = album.group_of(c.data)
        assert key.startswith("cat:") and name and icon  # every case has a category today
    k, name, _ = album.group_of({"scene": "train"})
    assert k == "scene:train" and name  # the fallback for a case without a category


async def test_album_hides_unsolved_and_shows_solved(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    p = await new_player(client, "album-1")
    h = p["headers"]
    first = (await client.get("/v1/album", headers=h)).json()
    assert first["solved"] == 0 and first["total"] >= 40 and first["groups_done"] == 0
    assert all(not c["solved"] and "title" not in c and "culprit" not in c and "line" not in c for c in first["cards"])
    await _unlock_all(p["player_id"])
    await _open(client, h, "c001")
    await _solve(client, h, "c001")
    a = (await client.get("/v1/album", headers=h)).json()
    c1 = next(c for c in a["cards"] if c["id"] == "c001")
    case = content.by_id("c001")
    culprit = next(s for s in case.data["suspects"] if s["id"] == case.culprit)
    assert c1["solved"] and c1["title"] == case.data["title"] and c1["stars"] >= 1
    assert c1["culprit"]["name"] == culprit["name"] and c1["culprit"]["role"] == culprit["role"] and c1["culprit"]["avatar"]
    assert c1["line"] == culprit["intro"].strip()
    # ABUSE PATH: nothing about any unsolved case leaks anywhere in the answer
    others = [c for c in a["cards"] if c["id"] != "c001"]
    for c in others:
        assert not c["solved"] and not ({"title", "culprit", "line", "location"} & set(c))
    raw = (await client.get("/v1/album", headers=h)).text
    for cs in content.all_cases():
        if cs.id != "c001":
            assert cs.data["title"] not in raw
    assert all(("price" in c and "open" in c) for c in others)


async def test_failed_case_stays_a_silhouette(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    p = await new_player(client, "album-fail")
    h = p["headers"]
    await _unlock_all(p["player_id"])
    await _open(client, h, "c002")
    c = content.by_id("c002")
    wrong = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    for _ in range(5):
        r = await client.post("/v1/cases/c002/accuse", headers=h, json={"suspect": wrong, "evidence": sorted(c.proof)[0]})
        if r.json()["result"] == "failed":
            break
    card = next(x for x in (await client.get("/v1/album", headers=h)).json()["cards"] if x["id"] == "c002")
    assert card["failed"] and not card["solved"] and "culprit" not in card and "title" not in card


async def test_group_reward_once_idempotent_and_permanent(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    p = await new_player(client, "album-group")
    h = p["headers"]
    await _unlock_all(p["player_id"])
    med = [c.id for c in content.opened() if c.data.get("category") == "medical"]
    assert len(med) >= album.GROUP_MIN
    coins_before = (await client.get("/v1/me", headers=h)).json()["coins"]
    got = None
    for cid in med:
        await _open(client, h, cid)
        r = await _solve(client, h, cid)
        if any(a["id"] == "frame_album" for a in r["gains"]["avatars"]):
            got = cid
    assert got == med[-1]  # only when the LAST case of the group is solved
    a = (await client.get("/v1/album", headers=h)).json()
    g = next(g for g in a["groups"] if g["key"] == "cat:medical")
    assert g["complete"] and a["groups_done"] == 1
    assert next(r for r in a["rewards"] if r["id"] == "frame_album")["owned"] and a["new"] == []
    owned = [x for x in (await client.get("/v1/avatars", headers=h)).json()["frames"] if x["id"] == "frame_album"]
    assert owned and owned[0]["owned"]
    # the reward is cosmetic: no coin, no warrant is added by the album itself
    again = (await client.get("/v1/album", headers=h)).json()
    assert again["new"] == []
    async with db.SessionLocal() as s:
        from sqlalchemy import func, select
        from app.models import PlayerAvatar
        n = await s.scalar(select(func.count()).select_from(PlayerAvatar).where(
            PlayerAvatar.player_id == p["player_id"], PlayerAvatar.avatar_id == "frame_album"))
    assert n == 1


async def test_viewing_the_album_pays_a_player_who_finished_a_group_before(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    p = await new_player(client, "album-old")
    h = p["headers"]
    await _unlock_all(p["player_id"])
    med = [c.id for c in content.opened() if c.data.get("category") == "medical"]
    for cid in med:
        await _open(client, h, cid)
        await _solve(client, h, cid)
    async with db.SessionLocal() as s:  # as if they solved these before the feature existed
        from sqlalchemy import delete
        from app.models import PlayerAvatar
        await s.execute(delete(PlayerAvatar).where(PlayerAvatar.player_id == p["player_id"]))
        pl = await s.get(Player, p["player_id"])
        pl.stats = {k: v for k, v in (pl.stats or {}).items() if k != "album_groups"}
        await s.commit()
    first = (await client.get("/v1/album", headers=h)).json()
    assert [x["id"] for x in first["new"]] == ["frame_album"]
    assert (await client.get("/v1/album", headers=h)).json()["new"] == []


async def test_album_is_bounded_and_unauthenticated_is_refused(client):
    assert (await client.get("/v1/album")).status_code in (401, 403)
    assert album.MAX_CARDS >= 400


# ---------------------------------------------------------------- first guess

async def test_guess_flow_and_community(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    cid = "c010"  # an archive case: a night's case solved here would change the daily ranks other tests expect
    c = content.by_id(cid)
    sids = [s["id"] for s in c.data["suspects"]]
    p = await new_player(client, "guess-1")
    h = p["headers"]
    await _unlock_all(p["player_id"])
    # the case must be opened first
    assert (await client.post(f"/v1/cases/{cid}/guess", headers=h, json={"suspect": sids[0]})).status_code in (402, 409)
    await _open(client, h, cid)
    assert (await client.post(f"/v1/cases/{cid}/guess", headers=h, json={"suspect": "nobody"})).status_code == 422
    r = await client.post(f"/v1/cases/{cid}/guess", headers=h, json={"suspect": sids[1]})
    assert r.json() == {"guess": sids[1], "already": False}
    # cannot guess twice: the first guess stays
    r = await client.post(f"/v1/cases/{cid}/guess", headers=h, json={"suspect": sids[2]})
    assert r.status_code == 200 and r.json() == {"guess": sids[1], "already": True}
    # before the case is solved or lost: own guess only, no percentages, no culprit
    g = (await client.get(f"/v1/cases/{cid}/guess", headers=h)).json()
    assert g == {"guess": sids[1], "community": None, "culprit": None, "correct": None}
    # 25 other detectives guessed: still hidden for this player until they have solved the case
    async with db.SessionLocal() as s:
        for i in range(25):
            s.add(CaseGuess(player_id=await _make_player(s, i), case_id=cid,
                            suspect=sids[0] if i < 15 else sids[1] if i < 20 else guess.UNKNOWN))
        await s.commit()
    guess._counts.clear()
    g = (await client.get(f"/v1/cases/{cid}/guess", headers=h)).json()
    assert g["community"] is None and g["culprit"] is None
    await _solve(client, h, cid)
    g = (await client.get(f"/v1/cases/{cid}/guess", headers=h)).json()
    assert g["culprit"] == c.culprit and g["correct"] == (sids[1] == c.culprit)
    com = g["community"]
    assert com["total"] == 26 and com["unknown_pct"] == round(100 * 5 / 26)
    assert {x["id"]: x["pct"] for x in com["suspects"]}[sids[0]] == round(100 * 15 / 26)
    assert "player" not in str(com)


async def _make_player(s, i):
    from app.models import Player
    pl = Player(id=f"g{i:030d}"[:32], device_id=f"gd{i}", secret_hash="x", invite_code=f"GI{i:08d}"[:12])
    s.add(pl)
    await s.flush()
    return pl.id


async def test_community_hidden_below_threshold(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    cid = "c010"
    sids = [s["id"] for s in content.by_id(cid).data["suspects"]]
    assert guess.community({sids[0]: 19}, sids) is None
    assert guess.community({sids[0]: 20}, sids)["total"] == 20
    assert guess.community({"ghost": 50}, sids) is None  # unknown ids never count


async def test_guess_too_late_after_the_investigation_started(client, clock):
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
    cid = "c010"
    c = content.by_id(cid)
    p = await new_player(client, "guess-late")
    h = p["headers"]
    await _unlock_all(p["player_id"])
    await _open(client, h, cid)
    await client.post(f"/v1/cases/{cid}/hint", headers=h)
    r = await client.post(f"/v1/cases/{cid}/guess", headers=h, json={"suspect": c.data["suspects"][0]["id"]})
    assert r.status_code == 409 and r.json()["detail"] == "too_late"
    # «نمی‌دونم» is a valid first guess for another player
    q = await new_player(client, "guess-unknown")
    await _unlock_all(q["player_id"])
    await _open(client, q["headers"], cid)
    r = await client.post(f"/v1/cases/{cid}/guess", headers=q["headers"], json={"suspect": "?"})
    assert r.json() == {"guess": "?", "already": False}


async def test_guess_uses_the_cheap_read_policy():
    from app.services import ratelimit
    pol = next(p for m, rx, p in ratelimit.ROUTES if rx.match("/v1/cases/c001/guess") and m == "POST")
    assert pol == "read"
