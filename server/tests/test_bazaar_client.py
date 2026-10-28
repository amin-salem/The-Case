"""Cafe Bazaar purchase check (28 Oct 2026: paid purchases were refused by the server)."""
import json

import httpx
import pytest

from app.config import Settings
from app.services.bazaar import BazaarClient

BASE = "https://pardakht.cafebazaar.ir/devapi/v2"
NEW = f"{BASE}/api/validate/inapp/purchases/"
OLD = f"{BASE}/api/validate/ir.gammly.parvandeh/inapp/coins_small/purchases/tok123/"


def client(handler, mode="api_secret"):
    s = Settings(bazaar_mode=mode, bazaar_api_secret="sec", bazaar_base_url=BASE,
                 bazaar_package_name="ir.gammly.parvandeh")
    return BazaarClient(s, http=httpx.AsyncClient(transport=httpx.MockTransport(handler)))


@pytest.mark.asyncio
async def test_new_endpoint_post_with_secret_header():
    seen = []

    def handler(req: httpx.Request):
        seen.append(req)
        return httpx.Response(200, json={"purchaseState": 0, "consumptionState": 1})

    r = await client(handler).check_inapp("coins_small", "tok123")
    assert r.valid and not r.consumed and not r.refunded
    assert len(seen) == 1 and seen[0].method == "POST" and str(seen[0].url) == NEW
    assert seen[0].headers["CAFEBAZAAR-PISHKHAN-API-SECRET"] == "sec"
    assert json.loads(seen[0].content) == {"token": "tok123"}


@pytest.mark.asyncio
async def test_falls_back_to_old_get_path():
    def handler(req: httpx.Request):
        if req.method == "POST":
            return httpx.Response(404, json={"detail": "not here"})
        assert str(req.url) == OLD and req.headers["CAFEBAZAAR-PISHKHAN-API-SECRET"] == "sec"
        return httpx.Response(200, json={"purchaseState": 0, "consumptionState": 0})

    r = await client(handler).check_inapp("coins_small", "tok123")
    assert r.valid and r.consumed


@pytest.mark.asyncio
async def test_both_refuse_keeps_both_statuses():
    r = await client(lambda req: httpx.Response(403 if req.method == "POST" else 401, json={})).check_inapp(
        "coins_small", "tok123")
    assert not r.valid and r.reason == "bazaar_error:401" and r.raw["post_status"] == 403


@pytest.mark.asyncio
async def test_refunded_purchase_is_refused():
    r = await client(lambda req: httpx.Response(200, json={"purchaseState": 1, "consumptionState": 1})).check_inapp(
        "coins_small", "tok123")
    assert not r.valid and r.refunded


@pytest.mark.asyncio
async def test_answer_without_purchase_state_never_grants():
    r = await client(lambda req: httpx.Response(200, json={"error": "invalid_token"})).check_inapp(
        "coins_small", "tok123")
    assert not r.valid and r.reason == "bazaar_bad_answer"


@pytest.mark.asyncio
async def test_bazaar_5xx_counts_as_unreachable():
    r = await client(lambda req: httpx.Response(502, text="bad gateway")).check_inapp("coins_small", "tok123")
    assert not r.valid and r.reason.startswith("bazaar_unreachable")


@pytest.mark.asyncio
async def test_network_error_counts_as_unreachable():
    def handler(req):
        raise httpx.ConnectError("down")

    r = await client(handler).check_inapp("coins_small", "tok123")
    assert r.reason.startswith("bazaar_unreachable")
