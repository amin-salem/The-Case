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
        old_url = f"{self.s.bazaar_base_url}/api/validate/{pkg}/inapp/{product_id}/purchases/{token}/"
        try:
            headers, params = await self._auth()
            if self.s.bazaar_mode == "api_secret":
                # 28 Oct 2026: purchases were paid in Bazaar but refused here. With the API secret Bazaar's current
                # endpoint is a POST with the token in the body; the old GET path is tried only when that one
                # does not answer 2xx, so either form of the API works.
                r = await self.http.post(f"{self.s.bazaar_base_url}/api/validate/inapp/purchases/",
                                         headers=headers, json={"token": token})
                if r.status_code >= 300:
                    first = r.status_code
                    r = await self.http.get(old_url, headers=headers)
                    if r.status_code >= 300:
                        return _refused(r, extra={"post_status": first})
                return _parsed(r)
            r = await self.http.get(old_url, headers=headers, params=params)
        except httpx.HTTPError as e:
            return PurchaseCheck(valid=False, reason=f"bazaar_unreachable:{type(e).__name__}")
        if r.status_code >= 300:
            return _refused(r)
        return _parsed(r)

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


def _refused(r: httpx.Response, extra: dict | None = None) -> PurchaseCheck:
    """A non-2xx answer. 5xx = Bazaar is having trouble: the app keeps the purchase unconsumed and retries later."""
    body = {**_json(r), **(extra or {})}
    if r.status_code >= 500:
        return PurchaseCheck(valid=False, reason=f"bazaar_unreachable:http{r.status_code}", raw=body)
    if r.status_code == 404:
        return PurchaseCheck(valid=False, reason="not_found", raw=body)
    return PurchaseCheck(valid=False, reason=f"bazaar_error:{r.status_code}", raw=body)


def _parsed(r: httpx.Response) -> PurchaseCheck:
    body = _json(r)
    if "purchaseState" not in body:  # never grant on an answer that is not a purchase (an error page with 200)
        return PurchaseCheck(valid=False, reason="bazaar_bad_answer", raw=body)
    # purchaseState: 0 = bought, 1 = refunded. consumptionState: 0 = consumed
    try:
        refunded = int(body.get("purchaseState", 0)) != 0
        consumed = int(body.get("consumptionState", 1)) == 0
    except (TypeError, ValueError):
        return PurchaseCheck(valid=False, reason="bazaar_bad_answer", raw=body)
    return PurchaseCheck(valid=not refunded, refunded=refunded, consumed=consumed,
                         reason="refunded" if refunded else "", raw=body)


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
