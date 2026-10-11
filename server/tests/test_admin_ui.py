from conftest import ADMIN, new_player


async def test_admin_page_and_api_need_the_key(client):
    page = await client.get("/admin/ui")
    assert page.status_code == 200 and "text/html" in page.headers["content-type"]
    assert "test-admin-key" not in page.text  # the page holds no secrets
    for path in ("overview", "feed", "players", "cases", "money", "health", "log"):
        assert (await client.get(f"/admin/api/{path}")).status_code == 403
        assert (await client.get(f"/admin/api/{path}", headers={"X-Admin-Key": "wrong"})).status_code == 403


async def test_admin_api_reads(client):
    p = await new_player(client, "admin-ui-dev-1")
    h = p["headers"]
    await client.get("/v1/cases/today", headers=h)
    ov = (await client.get("/admin/api/overview?days=7", headers=ADMIN)).json()
    assert len(ov["days"]) == 7 and ov["totals"]["players"] >= 1
    assert sum(d["new"] for d in ov["days"]) >= 1
    feed = (await client.get("/admin/api/feed", headers=ADMIN)).json()
    assert any(i["kind"] == "signup" for i in feed)
    pl = (await client.get("/admin/api/players?sort=created", headers=ADMIN)).json()
    assert pl["total"] >= 1 and pl["items"]
    pid = pl["items"][0]["id"]
    d = (await client.get(f"/admin/api/players/{pid}", headers=ADMIN)).json()
    assert d["player"]["id"] == pid and isinstance(d["timeline"], list)
    assert (await client.get("/admin/api/players/nope", headers=ADMIN)).status_code == 404
    assert isinstance((await client.get("/admin/api/cases", headers=ADMIN)).json(), list)
    assert "purchases_by_product" in (await client.get("/admin/api/money", headers=ADMIN)).json()
    assert (await client.get("/admin/api/health", headers=ADMIN)).json()["db_ok"] is True


async def test_admin_actions_are_logged(client):
    p = await new_player(client, "admin-ui-dev-2")
    pid = (await client.get("/admin/api/players?sort=created", headers=ADMIN)).json()["items"][0]["id"]
    r = await client.post("/admin/gifts", headers=ADMIN, json={"title": "سلام", "message": "x", "player_id": pid,
                                                            "grants": [{"type": "coins", "amount": 5}]})
    assert r.status_code == 200
    assert (await client.post(f"/admin/players/{pid}/ban", headers=ADMIN, json={"banned": True})).status_code == 200
    assert (await client.post(f"/admin/players/{pid}/ban", headers=ADMIN, json={"banned": False})).status_code == 200
    log = (await client.get("/admin/api/log", headers=ADMIN)).json()
    assert [x["action"] for x in log][:3] == ["unban", "ban", "gift"]
