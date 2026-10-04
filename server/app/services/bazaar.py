"""Checks Cafe Bazaar purchases with Bazaar's developer API.

Never trust the phone alone: a hacked app can say "payment OK" without
paying. The server asks Bazaar whether the purchase token is real.

Modes (BAZAAR_MODE):
  fake        tokens starting with "test-" are accepted (development only)
  api_secret  API secret from the developer panel, sent as a header
  oauth       older method: client_id + client_secret + refresh_token

NOTE: check the exact URLs/header against Bazaar's current docs
(developers.cafebazaar.ir -> In-app billing -> API) before going live.
They are all in this file so they are easy to change.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import httpx

from ..config import Settings


@dataclass
class PurchaseCheck:
    valid: bool
    refunded: bool = False
    consumed: bool = False
    reason: str = ""
    raw: dict = field(default_factory=dict)
    valid_until_ms: int | None = None  # subscriptions


class BazaarClient:
    def __init__(self, s: Settings, http: httpx.AsyncClient | None = None):
        self.s = s
        self.http = http or httpx.AsyncClient(timeout=15)
        self._token: str | None = None
        self._token_exp = 0.0

    # ---------------------------------------------------------------- auth
    async def _auth(self) -> tuple[dict, dict]:
        """Returns (headers, query params) for an API call."""
        if self.s.bazaar_mode == "api_secret":
            return {"CAFEBAZAAR-PISHKHAN-API-SECRET": self.s.bazaar_api_secret}, {}
        # oauth: refresh the access token when it expires
        if not self._token or time.time() > self._token_exp - 60:
            r = await self.http.post(
                f"{self.s.bazaar_base_url}/auth/token/",
                data={
                    "grant_type": "refresh_token",
                    "client_id": self.s.bazaar_client_id,
                    "client_secret": self.s.bazaar_client_secret,
                    "refresh_token": self.s.bazaar_refresh_token,
                },
            )
            r.raise_for_status()
            body = r.json()
            self._token = body["access_token"]
            self._token_exp = time.time() + int(body.get("expires_in", 3600))
        return {}, {"access_token": self._token}

    # ---------------------------------------------------------------- checks
    async def check_inapp(self, product_id: str, token: str) -> PurchaseCheck:
        if self.s.bazaar_mode == "fake":
            ok = token.startswith("test-")
            return PurchaseCheck(valid=ok, reason="" if ok else "fake_mode_needs_test_token",
                                 raw={"fake": True})
        pkg = self.s.bazaar_package_name
        url = f"{self.s.bazaar_base_url}/api/validate/{pkg}/inapp/{product_id}/purchases/{token}/"
        try:
            headers, params = await self._auth()
            r = await self.http.get(url, headers=headers, params=params)
        except httpx.HTTPError as e:
            return PurchaseCheck(valid=False, reason=f"bazaar_unreachable:{type(e).__name__}")
        body = _json(r)
        if r.status_code == 404:
            return PurchaseCheck(valid=False, reason="not_found", raw=body)
        if r.status_code >= 400:
            return PurchaseCheck(valid=False, reason=f"bazaar_error:{r.status_code}", raw=body)
        # purchaseState: 0 = bought, 1 = refunded. consumptionState: 0 = consumed
        refunded = int(body.get("purchaseState", 0)) != 0
        consumed = int(body.get("consumptionState", 1)) == 0
        return PurchaseCheck(valid=not refunded, refunded=refunded, consumed=consumed,
                             reason="refunded" if refunded else "", raw=body)

    async def check_subscription(self, product_id: str, token: str) -> PurchaseCheck:
        if self.s.bazaar_mode == "fake":
            ok = token.startswith("test-")
            until = int((time.time() + 30 * 86400) * 1000)
            return PurchaseCheck(valid=ok, raw={"fake": True}, valid_until_ms=until if ok else None,
                                 reason="" if ok else "fake_mode_needs_test_token")
        pkg = self.s.bazaar_package_name
        url = f"{self.s.bazaar_base_url}/api/applications/{pkg}/subscriptions/{product_id}/purchases/{token}/"
        try:
            headers, params = await self._auth()
            r = await self.http.get(url, headers=headers, params=params)
        except httpx.HTTPError as e:
            return PurchaseCheck(valid=False, reason=f"bazaar_unreachable:{type(e).__name__}")
        body = _json(r)
        if r.status_code >= 400:
            return PurchaseCheck(valid=False, reason=f"bazaar_error:{r.status_code}", raw=body)
        until = int(body.get("validUntilTimestampMsec", 0))
        active = until > time.time() * 1000
        return PurchaseCheck(valid=active, reason="" if active else "expired", raw=body,
                             valid_until_ms=until)


def _json(r: httpx.Response) -> dict:
    try:
        v = r.json()
        return v if isinstance(v, dict) else {"body": v}
    except ValueError:
        return {"text": r.text[:500]}


_client: BazaarClient | None = None


def get_bazaar() -> BazaarClient:
    """FastAPI dependency (tests replace it with a fake)."""
    global _client
    if _client is None:
        from ..config import get_settings

        _client = BazaarClient(get_settings())
    return _client
