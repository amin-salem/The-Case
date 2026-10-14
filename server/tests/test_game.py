from datetime import datetime, timedelta

import pytest

from app import content, economy

from .conftest import ADMIN, new_player


@pytest.fixture
def clock(monkeypatch):
    def set_to(dt: datetime):
        monkeypatch.setattr(content, "now_local", lambda: dt)
        return dt
    return set_to


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
    assert economy.stars_for(0, 0, 1) == 2 and economy.stars_for(0, 0, 2) == 1


async def test_welcome_coins_and_login_reward(client):
    p = await new_player(client)
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["coins"] == economy.START_COINS + economy.LOGIN_REWARD and me["login_reward"] == economy.LOGIN_REWARD
    again = (await client.get("/v1/me", headers=p["headers"])).json()
    assert again["login_reward"] == 0


async def test_today_case_flow_solve(client, clock):
    # a fixed night whose case no other test solves (the real "today" can clash with other tests)
    clock(content.opens_at(content.by_id("c040")) + timedelta(hours=1))
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
    # the right suspect with the wrong proof costs a star, not a try (twice)
    assert r["result"] == "wrong_proof" and r["attempts_left"] == economy.MAX_ATTEMPTS
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})).json()
    assert r["result"] == "wrong_proof" and r["attempts_left"] == economy.MAX_ATTEMPTS
    # after that, wrong proofs use up tries
    for _ in range(3):
        r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})).json()
    # the answer of tonight's case stays secret until the next case opens (docs/operations.md, anti-cheat)
    assert r["result"] == "failed" and r["culprit"] is None and r["explanation"] is None and r["proof"] == []
    assert r["answer_at"] == int(content.next_case_at().timestamp())


async def test_wrong_proof_costs_a_star(client):
    p = await new_player(client, "proof-misser")
    h = p["headers"]
    c = content.todays_case()
    await client.get(f"/v1/cases/{c.id}", headers=h)
    bad_ev = next(e["id"] for e in c.data["evidence"] if e["id"] not in c.proof)
    await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved" and r["stars"] == 2


async def test_archive_unlock_costs_coins(client, monkeypatch):
    # a new player (100 coins + the first login reward) cannot afford the full price on day 1: that is intended
    monkeypatch.setattr(economy, "UNLOCK_COST", 100)
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


async def test_wrong_tries_are_remembered_for_the_red_marks(client):
    p = await new_player(client, "marker")
    h = p["headers"]
    c = content.todays_case()
    await client.get(f"/v1/cases/{c.id}", headers=h)
    bad_ev = next(e["id"] for e in c.data["evidence"] if e["id"] not in c.proof)
    innocent = next(s["id"] for s in c.data["suspects"] if s["id"] != c.culprit)
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": innocent, "evidence": bad_ev})).json()
    assert r["result"] == "wrong_suspect" and r["progress"]["wrong_tries"] == [
        {"s": innocent, "e": bad_ev, "m": None, "r": "wrong_suspect"}]
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": bad_ev})).json()
    assert r["result"] == "wrong_proof"
    # the list survives a reload (another device) and is the player's own
    got = (await client.get(f"/v1/cases/{c.id}", headers=h)).json()["progress"]["wrong_tries"]
    assert [t["r"] for t in got] == ["wrong_suspect", "wrong_proof"] and got[1]["e"] == bad_ev
    other = await new_player(client, "marker-2")
    await client.get(f"/v1/cases/{c.id}", headers=other["headers"])
    assert (await client.get(f"/v1/cases/{c.id}", headers=other["headers"])).json()["progress"]["wrong_tries"] == []
    # solved: the review still has both mistakes
    r = (await client.post(f"/v1/cases/{c.id}/accuse", headers=h, json={"suspect": c.culprit, "evidence": sorted(c.proof)[0]})).json()
    assert r["result"] == "solved" and len(r["progress"]["wrong_tries"]) == 2


async def test_smoke_players_are_removed_completely(client):
    from sqlalchemy import func, select
    from app import db
    from app.models import CoinLog, Player
    smoke = await new_player(client, device="smoke-abc123")
    real = await new_player(client, device="device-real-1")
    # a real player can never delete itself through the smoke call
    r = await client.delete("/v1/me/smoke", headers=real["headers"])
    assert r.status_code == 403
    # a smoke player can, and nothing of it stays behind
    r = await client.delete("/v1/me/smoke", headers=smoke["headers"])
    assert r.status_code == 200 and r.json() == {"deleted": 1}
    async with db.SessionLocal() as s:
        assert await s.get(Player, smoke["player_id"]) is None
        assert await s.scalar(select(func.count()).select_from(CoinLog).where(CoinLog.player_id == smoke["player_id"])) == 0
        assert await s.get(Player, real["player_id"]) is not None


async def test_admin_purges_old_smoke_players(client):
    from app import db
    from app.models import Player
    a = await new_player(client, device="smoke-old1")
    b = await new_player(client, device="smoke-old2")
    keep = await new_player(client, device="device-keep-9")
    r = await client.post("/admin/players/purge-smoke")
    assert r.status_code == 403
    r = await client.post("/admin/players/purge-smoke", headers=ADMIN)
    assert r.status_code == 200 and r.json()["deleted"] >= 2
    async with db.SessionLocal() as s:
        assert await s.get(Player, a["player_id"]) is None and await s.get(Player, b["player_id"]) is None
        assert await s.get(Player, keep["player_id"]) is not None
    r = await client.post("/admin/players/purge-smoke", headers=ADMIN)
    assert r.json()["deleted"] == 0
