"""Checks Myket purchases with Myket's server-to-server validation API.

Never trust the phone alone: a hacked app can say "payment OK" without paying, so the server
asks Myket whether the purchase token is real, paid, and for this product.

    POST {MYKET_BASE_URL}/{package}/purchases/products/{sku}/verify
    header  X-Access-Token: <from the Myket developer panel>
    body    {"tokenId": "<purchase token>"}
    answer  {"purchaseState": 0 (paid) | 1, "consumptionState": ..., "developerPayload": "...", ...}

https://myket.ir/kb/pages/server-to-server-payment-validation-api/

Without MYKET_ACCESS_TOKEN (development only) tokens starting with "test-" are accepted; in
production that fallback is switched off.
"""
from __future__ import annotations

import httpx

from ..config import Settings
from .bazaar import PurchaseCheck


class MyketClient:
    def __init__(self, s: Settings, http: httpx.AsyncClient | None = None):
        self.s = s
        self.http = http or httpx.AsyncClient(timeout=15)

    @property
    def configured(self) -> bool:
        return bool(self.s.myket_access_token)

    async def check_inapp(self, product_id: str, token: str, payload: str | None = None) -> PurchaseCheck:
        if not self.configured:
            if self.s.env == "prod":
                return PurchaseCheck(valid=False, reason="store_not_configured")
            ok = token.startswith("test-")
            return PurchaseCheck(valid=ok, reason="" if ok else "fake_mode_needs_test_token", raw={"fake": True})
        url = f"{self.s.myket_base_url}/{self.s.myket_package_name}/purchases/products/{product_id}/verify"
        try:
            r = await self.http.post(url, json={"tokenId": token},
                                     headers={"X-Access-Token": self.s.myket_access_token})
        except httpx.HTTPError as e:
            return PurchaseCheck(valid=False, reason=f"store_unreachable:{type(e).__name__}")
        if r.status_code >= 500:
            return PurchaseCheck(valid=False, reason=f"store_unreachable:{r.status_code}")
        try:
            data = r.json()
        except ValueError:
            data = {}
        if r.status_code != 200 or not isinstance(data, dict):
            return PurchaseCheck(valid=False, reason=f"myket_{r.status_code}", raw={"status": r.status_code})
        raw = {k: data.get(k) for k in ("purchaseState", "consumptionState", "purchaseTime", "developerPayload", "kind")}
        if data.get("purchaseState") != 0:
            return PurchaseCheck(valid=False, refunded=data.get("purchaseState") == 1, reason="not_paid", raw=raw)
        # the app sends the player id as payload: a token bought by someone else can't be redeemed here
        if payload is not None and data.get("developerPayload") not in (None, "", payload):
            return PurchaseCheck(valid=False, reason="payload_mismatch", raw=raw)
        # Google-style states: consumptionState 0 = not consumed yet, 1 = consumed
        return PurchaseCheck(valid=True, consumed=data.get("consumptionState") == 1, raw=raw)


_client: MyketClient | None = None


def get_myket() -> MyketClient:
    """FastAPI dependency (tests replace it with a fake)."""
    global _client
    if _client is None:
        from ..config import get_settings

        _client = MyketClient(get_settings())
    return _client
