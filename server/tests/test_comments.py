"""Case comments: stars, replies, admin approval, abuse paths."""
import pytest

from app import content, db
from app.config import get_settings
from app.models import CaseProgress, utcnow

from .conftest import ADMIN, new_player

CASE = content.all_cases()[0].id


async def finish(pid: str, case_id: str = CASE):
    async with db.SessionLocal() as s:
        s.add(CaseProgress(player_id=pid, case_id=case_id, solved=True, finished_at=utcnow()))
        await s.commit()


async def post(client, p, body, rating=0, parent=None, case=CASE):
    return await client.post(f"/v1/cases/{case}/comments", headers=p["headers"],
                             json={"body": body, "rating": rating, "parent_id": parent})


async def approve(client, cid, action="approve"):
    r = await client.post(f"/admin/api/comments/{cid}", headers=ADMIN, json={"action": action})
    assert r.status_code == 200, r.text


async def test_full_flow(client):
    a = await new_player(client, "cm-a-1234")
    b = await new_player(client, "cm-b-1234")
    # must finish the case first
    assert (await post(client, a, "پرونده‌ی خوبی بود", 5)).status_code == 409
    await finish(a["player_id"])
    await finish(b["player_id"])
    r = await post(client, a, "پرونده‌ی خوبی بود", 5)
    assert r.status_code == 200 and r.json()["status"] == "pending"
    cid = r.json()["id"]
    # nobody else sees it; the writer sees it as theirs, waiting
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=b["headers"])).json()
    assert lst["count"] == 0 and lst["items"] == [] and lst["mine"] is None and lst["can_write"] is True
    mine = (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()
    assert mine["mine"]["status"] == "pending" and mine["has_mine"] is True
    # one comment per player
    assert (await post(client, a, "یکی دیگر", 4)).status_code == 409
    # a reply needs an approved comment
    assert (await post(client, b, "موافقم", parent=cid)).status_code == 404
    await approve(client, cid)
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=b["headers"])).json()
    assert lst["count"] == 1 and lst["average"] == 5.0 and lst["items"][0]["body"] == "پرونده‌ی خوبی بود"
    rep = await post(client, b, "موافقم", parent=cid)
    assert rep.status_code == 200
    seen_by_b = (await client.get(f"/v1/cases/{CASE}/comments", headers=b["headers"])).json()
    assert seen_by_b["items"][0]["replies"][0]["status"] == "pending"
    seen_by_a = (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()
    assert seen_by_a["items"][0]["replies"] == []  # a pending reply is private until approved
    await approve(client, rep.json()["id"])
    seen_by_a = (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()
    assert len(seen_by_a["items"][0]["replies"]) == 1
    # hiding removes it from the public list and the average
    await approve(client, cid, "hide")
    gone = (await client.get(f"/v1/cases/{CASE}/comments", headers=b["headers"])).json()
    assert gone["count"] == 0 and gone["items"] == []


async def test_rejected_can_be_rewritten(client):
    a = await new_player(client, "cm-rej-1234")
    await finish(a["player_id"])
    cid = (await post(client, a, "متن اول", 2)).json()["id"]
    await approve(client, cid, "reject")
    again = await post(client, a, "متن اصلاح‌شده", 3)
    assert again.status_code == 200 and again.json()["id"] == cid and again.json()["status"] == "pending"


async def test_validation_and_abuse(client):
    a = await new_player(client, "cm-val-1234")
    await finish(a["player_id"])
    assert (await post(client, a, "ok text", 0)).status_code == 422          # rating needed
    assert (await post(client, a, "ok text", 6)).status_code == 422          # out of range (schema)
    assert (await post(client, a, "ab", 3)).status_code == 422               # too short
    assert (await post(client, a, "x" * 301, 3)).json()["detail"] == "comment_too_long"
    assert (await post(client, a, "برو به https://spam.example", 3)).json()["detail"] == "no_links"
    assert (await post(client, a, "پیام بده @spammer", 3)).json()["detail"] == "no_links"
    assert (await client.post("/v1/cases/zzz/comments", headers=a["headers"],
                              json={"body": "سلام سلام", "rating": 3})).status_code == 404
    assert (await client.get(f"/v1/cases/{CASE}/comments")).status_code == 401


async def test_kill_switch(client, monkeypatch):
    a = await new_player(client, "cm-off-1234")
    monkeypatch.setattr(get_settings(), "comments_enabled", False)
    assert (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).status_code == 503


async def test_admin_lists_and_needs_key(client):
    assert (await client.get("/admin/api/comments")).status_code in (401, 403)
    a = await new_player(client, "cm-adm-1234")
    await finish(a["player_id"], content.all_cases()[1].id)
    other = content.all_cases()[1].id
    cid = (await post(client, a, "یک نظر برای مدیر", 4, case=other)).json()["id"]
    pend = (await client.get("/admin/api/comments?status=pending", headers=ADMIN)).json()
    assert any(i["id"] == cid and i["case_id"] == other for i in pend["items"])
    only = (await client.get(f"/admin/api/comments?status=pending&case_id={other}", headers=ADMIN)).json()
    assert {i["case_id"] for i in only["items"]} == {other}
    cases = (await client.get("/admin/api/comments/cases", headers=ADMIN)).json()
    assert cases["pending"] >= 1 and any(c["case_id"] == other and c["pending"] >= 1 for c in cases["items"])
    assert (await client.get("/admin/api/comments?status=bogus", headers=ADMIN)).status_code == 422
    await approve(client, cid, "delete")
    assert (await client.post(f"/admin/api/comments/{cid}", headers=ADMIN, json={"action": "delete"})).status_code == 404
    assert (await client.post(f"/admin/api/comments/{cid}", headers=ADMIN, json={"action": "nuke"})).status_code == 422


async def test_stars_without_a_comment(client):
    a = await new_player(client, "cm-star-1234")
    b = await new_player(client, "cm-star-5678")
    await finish(a["player_id"])
    await finish(b["player_id"])
    # no text: the stars count at once, nothing waits for the admin
    r = await post(client, a, "", 4)
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert (await post(client, a, "", 4)).status_code == 409                 # one rating per player and case
    assert (await post(client, b, "   ", 0)).status_code == 422              # stars are still needed
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=b["headers"])).json()
    assert lst["count"] == 1 and lst["average"] == 4.0 and lst["items"] == []  # counted, not listed as a comment
    assert (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()["has_mine"] is True
    # a written comment still waits for approval
    r = await post(client, b, "پرونده‌ی خوبی بود", 2)
    assert r.json()["status"] == "pending"
    lst = (await client.get(f"/v1/cases/{CASE}/comments", headers=a["headers"])).json()
    assert lst["items"] == [] and lst["count"] == 1
