"""Myket purchase verification (the Myket API is replaced by a fake HTTP server)."""
import httpx

from app.config import Settings
from app.main import app
from app.services.myket import MyketClient, get_myket

from .conftest import new_player


def myket_with(answer: dict, status: int = 200, seen: list | None = None) -> MyketClient:
    def handler(req: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(req)
        return httpx.Response(status, json=answer)
    s = Settings(myket_access_token="tok-123", env="dev")
    return MyketClient(s, httpx.AsyncClient(transport=httpx.MockTransport(handler)))


async def test_myket_purchase_is_verified_with_myket(client):
    p = await new_player(client, "myket-buyer")
    seen: list = []
    app.dependency_overrides[get_myket] = lambda: myket_with(
        {"purchaseState": 0, "consumptionState": 0, "developerPayload": p["player_id"]}, seen=seen)
    try:
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "coins_small", "purchase_token": "mk-real-1", "store": "myket"})).json()
        assert r["status"] == "granted" and r["added"] == 400 and r["consume"] is True
        req = seen[0]
        assert req.headers["X-Access-Token"] == "tok-123"
        assert req.url.path.endswith("/ir.aminsalem.the_case/purchases/products/coins_small/verify")
        # the same token can't be used twice
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "coins_small", "purchase_token": "mk-real-1", "store": "myket"})).json()
        assert r["status"] == "already_granted" and r["added"] == 0
        # VIP is a 30-day pass
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "vip_monthly", "purchase_token": "mk-vip-1", "store": "myket"})).json()
        assert r["status"] == "granted" and r["vip_until"]
    finally:
        app.dependency_overrides.pop(get_myket, None)


async def test_myket_rejects_unpaid_or_someone_elses_purchase(client):
    p = await new_player(client, "myket-cheater")
    try:
        app.dependency_overrides[get_myket] = lambda: myket_with({"purchaseState": 1})
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "coins_small", "purchase_token": "mk-unpaid", "store": "myket"})).json()
        assert r["status"] == "rejected"
        app.dependency_overrides[get_myket] = lambda: myket_with({"purchaseState": 0, "developerPayload": "other-player"})
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "coins_small", "purchase_token": "mk-other", "store": "myket"})).json()
        assert r["status"] == "rejected" and r["reason"] == "payload_mismatch"
        app.dependency_overrides[get_myket] = lambda: myket_with({"purchaseState": 0, "consumptionState": 1})
        r = (await client.post("/v1/purchases/verify", headers=p["headers"],
                               json={"product_id": "coins_small", "purchase_token": "mk-used", "store": "myket"})).json()
        assert r["status"] == "rejected" and r["reason"] == "already_consumed"
        app.dependency_overrides[get_myket] = lambda: myket_with({}, status=503)
        r = await client.post("/v1/purchases/verify", headers=p["headers"],
                              json={"product_id": "coins_small", "purchase_token": "mk-down", "store": "myket"})
        assert r.status_code == 503
    finally:
        app.dependency_overrides.pop(get_myket, None)


async def test_production_never_accepts_test_tokens():
    prod = MyketClient(Settings(env="prod", myket_access_token=""))
    check = await prod.check_inapp("coins_small", "test-free-coins")
    assert not check.valid and check.reason == "store_not_configured"
