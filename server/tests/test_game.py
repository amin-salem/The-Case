from app import content, economy

from .conftest import ADMIN, new_player


def test_cases_load_and_hide_solutions():
    cases = content.all_cases()
    assert len(cases) >= 6
    for c in cases:
        pub = c.public()
        assert "solution" not in pub and "hints" not in pub


def test_stars():
    assert economy.stars_for(0, 0) == 3
    assert economy.stars_for(1, 0) == 3
    assert economy.stars_for(2, 0) == 2
    assert economy.stars_for(3, 1) == 1


async def test_welcome_coins_and_login_reward(client):
    p = await new_player(client)
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["coins"] == economy.START_COINS + economy.LOGIN_REWARD and me["login_reward"] == economy.LOGIN_REWARD
    again = (await client.get("/v1/me", headers=p["headers"])).json()
    assert again["login_reward"] == 0


async def test_today_case_flow_solve(client):
    p = await new_player(client, "solver-1")
    h = p["headers"]
    lst = (await client.get("/v1/cases", headers=h)).json()
    today = lst["today"]
    assert today and not today["locked"]
    c = content.by_id(today["id"])
    got = (await client.get(f"/v1/cases/{c.id}", headers=h)).json()
    assert "solution" not in got["case"] and got["today"] is True
    hint = (await client.post(f"/v1/cases/{c.id}/hint", headers=h)).json()
    assert hint["hint"] == c.hints[0]
    # wrong suspect first
    wrong = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": wrong, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "wrong_suspect" and r["attempts_left"] == economy.MAX_ATTEMPTS - 1
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                           json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved" and r["stars"] == 2 and r["streak"] == 1 and r["rank"] == 1
    assert r["reward"] == economy.SOLVE_REWARD[2] + economy.DAILY_BONUS
    lb = (await client.get("/v1/leaderboard?period=daily", headers=h)).json()
    assert lb["me"]["rank"] == 1
    again = await client.post(f"/v1/cases/{c.id}/accuse", headers=h,
                              json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})
    assert again.status_code == 409
    reopened = (await client.get(f"/v1/cases/{c.id}", headers=h)).json()
    assert reopened["case"]["solution"]["culprit"] == c.culprit


async def test_wrong_proof_and_fail(client):
    p = await new_player(client, "failer")
    h = p["headers"]
    c = content.todays_case()
    await client.get(f"/v1/cases/{c.id}", headers=h)
    bad_ev = next(e["id"] for e in c.data["evidence"] if e["id"] not in c.proof)
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})).json()
    assert r["result"] == "wrong_proof"
    for _ in range(2):
        r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})).json()
    assert r["result"] == "failed" and r["culprit"] == c.culprit and r["explanation"]


async def test_archive_unlock_costs_coins(client):
    p = await new_player(client, "archivist")
    h = p["headers"]
    lst = (await client.get("/v1/cases", headers=h)).json()
    old = lst["archive"][0]
    assert old["locked"]
    r = await client.get(f"/v1/cases/{old['id']}", headers=h)
    assert r.status_code == 402
    before = (await client.get("/v1/me", headers=h)).json()["coins"]
    r = await client.post(f"/v1/cases/{old['id']}/unlock", headers=h)
    assert r.status_code == 200
    after = (await client.get("/v1/me", headers=h)).json()["coins"]
    assert before - after == economy.UNLOCK_COST


async def test_not_enough_coins_for_hint(client):
    p = await new_player(client, "poor")
    h = p["headers"]
    c = content.todays_case()
    await client.get(f"/v1/cases/{c.id}", headers=h)
    for _ in range(2):  # 30 + 50 of the 150 welcome coins
        assert (await client.post(f"/v1/cases/{c.id}/hint", headers=h)).status_code == 200
    r = await client.post(f"/v1/cases/{c.id}/hint", headers=h)  # 80 needed, 70 left
    assert r.status_code == 402 and r.json()["detail"]["error"] == "not_enough_coins"


async def test_purchase_adds_coins_once(client):
    p = await new_player(client, "buyer")
    h = p["headers"]
    r = (await client.post("/v1/purchases/verify", headers=h,
                           json={"product_id": "coins_medium", "purchase_token": "test-tok-1"})).json()
    assert r["status"] == "granted" and r["added"] == 1300 and r["consume"] is True
    r = (await client.post("/v1/purchases/verify", headers=h,
                           json={"product_id": "coins_medium", "purchase_token": "test-tok-1"})).json()
    assert r["status"] == "already_granted" and r["added"] == 0
    r = (await client.post("/v1/purchases/verify", headers=h,
                           json={"product_id": "vip_monthly", "purchase_token": "test-vip-1"})).json()
    assert r["vip_until"] and r["no_ads"] is True


async def test_email_account_and_transfer(client):
    p = await new_player(client, "phone-a")
    r = await client.post("/v1/auth/email", headers=p["headers"], json={"email": "Det@Example.com", "password": "secret1"})
    assert r.status_code == 200 and r.json()["reward"] == economy.SECURE_REWARD
    r = await client.post("/v1/auth/login/email", json={"email": "det@example.com", "password": "secret1", "device_id": "phone-b"})
    assert r.status_code == 200 and r.json()["player_id"] == p["player_id"]
    assert (await client.get("/v1/me", headers=p["headers"])).status_code == 401


async def test_ads_limit_and_gifts(client):
    p = await new_player(client, "ad-watcher")
    h = p["headers"]
    for _ in range(economy.AD_PER_DAY):
        assert (await client.post("/v1/wallet/ad-reward", headers=h)).status_code == 200
    assert (await client.post("/v1/wallet/ad-reward", headers=h)).status_code == 429
    r = await client.post("/admin/gifts", headers=ADMIN, json={"title": "هدیه", "grants": [{"type": "coins", "amount": 99}],
                                                               "player_id": p["player_id"]})
    assert r.status_code == 200
    items = (await client.get("/v1/inbox", headers=h)).json()
    gift = next(i for i in items if i["title"] == "هدیه")
    claim = (await client.post(f"/v1/inbox/{gift['id']}/claim", headers=h)).json()
    assert claim["grants"][0]["amount"] == 99


async def test_config_and_admin(client):
    cfg = (await client.get("/v1/config")).json()
    assert cfg["economy"]["hint_costs"] == economy.HINT_COSTS and "next_case_at" in cfg
    assert (await client.get("/admin/stats")).status_code == 403
    stats = (await client.get("/admin/stats", headers=ADMIN)).json()
    assert stats["cases_written"] >= 6
    rep = (await client.get("/admin/cases", headers=ADMIN)).json()
    assert len(rep) >= 6
