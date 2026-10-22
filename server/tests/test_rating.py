"""Stars-only rating route `POST /v1/cases/{id}/rating`: relaxed limiter policy, idempotent, abuse paths."""
import pytest
from sqlalchemy import update

from app import content, db
from app.models import CaseProgress, Player, utcnow
from app.services import ratelimit as rl

from .conftest import new_player
from .test_ratelimit import clock  # noqa: F401  (deterministic clock + real limiter)

CASES = [c.id for c in content.all_cases()]
CASE = CASES[0]


async def finish(pid: str, *case_ids: str):
    async with db.SessionLocal() as s:
        for cid in case_ids:
            s.add(CaseProgress(player_id=pid, case_id=cid, solved=True, finished_at=utcnow()))
        await s.commit()


async def rate(client, p, stars, case=CASE):
    return await client.post(f"/v1/cases/{case}/rating", headers=p["headers"], json={"rating": stars})


def test_policy_and_routes():
    pol = rl.DEFAULTS["rating"]
    assert pol.tiers == ((5, 10), (200, 3600)) and pol.store == "mem" and pol.fail == "open"
    assert rl.DEFAULTS["comment"].tiers == ((2, 20), (10, 3600)) and rl.DEFAULTS["comment"].store == "strict"

    def policy_of(method, path):
        for m, rx, name in rl.ROUTES:
            if m in (method, "*") and rx.match(path):
                return name

    assert policy_of("POST", "/v1/cases/c001/rating") == "rating"
    assert policy_of("POST", "/v1/cases/c001/comments") == "comment"


async def test_idempotent_double_tap_and_stars_kept(client):
    p = await new_player(client, "rt-a-1234")
    await finish(p["player_id"], CASE)
    r1 = await rate(client, p, 4)
    r2 = await rate(client, p, 4)  # double tap
    r3 = await rate(client, p, 1)  # a different value later changes nothing
    assert r1.status_code == r2.status_code == r3.status_code == 200
    assert r1.json()["already"] is False and r2.json()["already"] is True and r3.json()["rating"] == 4
    assert r1.json()["id"] == r2.json()["id"] == r3.json()["id"]
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=p["headers"])).json()
    assert lst["average"] == 4.0 and lst["has_mine"] is True  # counted once, at once (cache cleared)
    # a later text comment keeps the stars
    r = await client.post(f"/v1/cases/{CASE}/comments", headers=p["headers"], json={"body": "پرونده‌ی خوبی بود", "rating": 2})
    assert r.status_code == 200
    again = await rate(client, p, 3)
    assert again.json()["rating"] == 4


async def test_two_players_average(client):
    a, b = await new_player(client, "rt-b-1234"), await new_player(client, "rt-c-1234")
    for p in (a, b):
        await finish(p["player_id"], CASE)
    assert (await rate(client, a, 5)).status_code == 200
    assert (await rate(client, b, 3)).status_code == 200
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()
    assert lst["average"] == 4.0


async def test_old_comment_route_still_takes_rating_only(client):
    p = await new_player(client, "rt-d-1234")
    await finish(p["player_id"], CASE)
    r = await client.post(f"/v1/cases/{CASE}/comments", headers=p["headers"], json={"body": "", "rating": 4})
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert (await rate(client, p, 2)).json()["rating"] == 4  # the new route sees the same row


async def test_abuse_paths(client):
    p = await new_player(client, "rt-e-1234")
    await finish(p["player_id"], CASE)
    for bad in (0, 6, -1, "x", None, 4.5):
        assert (await rate(client, p, bad)).status_code == 422, bad
    r = await client.post(f"/v1/cases/{CASE}/rating", headers=p["headers"], json={})
    assert r.status_code == 422
    assert (await rate(client, p, 3, case="zzz-unknown")).status_code == 404
    assert (await rate(client, p, 3, case=CASES[1])).status_code == 409  # not finished
    assert (await client.post(f"/v1/cases/{CASE}/rating", json={"rating": 3})).status_code in (401, 403)
    async with db.SessionLocal() as s:
        await s.execute(update(Player).where(Player.id == p["player_id"]).values(banned=True))
        await s.commit()
    assert (await rate(client, p, 3)).status_code == 403


async def test_forty_cases_in_a_row_without_429(client, clock):  # noqa: F811
    p = await new_player(client, "rt-f-1234")
    ids = CASES[:40]
    assert len(ids) == 40
    await finish(p["player_id"], *ids)
    for cid in ids:
        r = await rate(client, p, 4, case=cid)
        assert r.status_code == 200, (cid, r.text)
        clock.advance(3)  # a player really taps about this fast


async def test_201st_rating_in_an_hour_is_blocked(client, clock):  # noqa: F811
    p = await new_player(client, "rt-g-1234")
    await finish(p["player_id"], CASE)
    for i in range(200):
        r = await rate(client, p, 4)
        assert r.status_code == 200, i
        clock.advance(2.5)
    r = await rate(client, p, 4)
    assert r.status_code == 429
    assert int(r.headers["retry-after"]) > 60 and r.json()["error"] == "rate_limited"
    clock.advance(3600)
    assert (await rate(client, p, 4)).status_code == 200


async def test_text_comments_stay_strict(client, clock):  # noqa: F811
    p = await new_player(client, "rt-h-1234")
    ids = CASES[:3]
    await finish(p["player_id"], *ids)
    codes = []
    for cid in ids:
        r = await client.post(f"/v1/cases/{cid}/comments", headers=p["headers"], json={"body": "یک نظر کوتاه", "rating": 4})
        codes.append(r.status_code)
    assert codes == [200, 200, 429]  # 2 per 20 s, unchanged
    # stars alone on the new route are not held back by the text-comment counter
    assert (await rate(client, p, 5, case=ids[2])).status_code == 200
