"""Cafe Bazaar reviews of the app: list them and reply (admin panel «نظرات بازار»; Amin, 28 Oct 2026).

API (Bazaar developer docs «Comments API»): base https://sandoghche.cafebazaar.ir
  GET  /api/v0/reviews/        filters publish_date_after/before, rate_min, rate_max, app_version_code, sdk_version,
                               is_replied=true|false; cursor pagination with `next` / `previous` links
  POST /api/v0/reviews/{id}/   JSON {"text": ..., "email": optional}; 201. Bazaar approves the reply before players see it.
Auth: header CAFEBAZAAR-PISHKHAN-API-SECRET (the same Pishkhan token as the purchase check: settings.bazaar_api_secret).

Safety: only the admin panel calls this. A Bazaar failure never breaks the panel: every problem is a ReviewsError with a
stable code the page shows in Persian. The list is cached per worker for a minute (bounded, never holds the token).
The reply is fail-closed (no token, bad text, bad id: nothing is sent). Logs carry the review id and the status only,
never the review or the reply text.
"""
from __future__ import annotations

import logging
from urllib.parse import parse_qsl, urlsplit

import httpx

from ..cache import TTLCache
from ..config import Settings

log = logging.getLogger("bazaar_reviews")

_cache = TTLCache("bazaar_reviews", ttl=60, max_size=50)
REPLY_MIN, REPLY_MAX = 5, 500
PAGE = "/api/v0/reviews/"

MESSAGES = {
    "no_secret": "توکن پیشخان تنظیم نشده (BAZAAR_API_SECRET در لیارا)",
    "denied": "بازار توکن را قبول نکرد (۴۰۱/۴۰۳)؛ توکن تازه از پیشخان بگیر",
    "rate_limited": "بازار الان درخواست‌ها را محدود کرده؛ چند دقیقه بعد دوباره امتحان کن",
    "unreachable": "به بازار وصل نشد؛ چند دقیقه بعد دوباره امتحان کن",
    "bad_reply": f"متن پاسخ باید بین {REPLY_MIN} تا {REPLY_MAX} حرف باشد",
    "bad_id": "شناسه‌ی نظر درست نیست",
    "bad_cursor": "صفحه‌ی بعد معتبر نیست",
    "bazaar_error": "بازار خطا داد؛ بعداً دوباره امتحان کن",
}


class ReviewsError(Exception):
    def __init__(self, code: str, status: int | None = None):
        super().__init__(code)
        self.code, self.status = code, status

    @property
    def message(self) -> str:
        return MESSAGES.get(self.code, MESSAGES["bazaar_error"])


def _headers(s: Settings) -> dict:
    if not s.bazaar_api_secret:
        raise ReviewsError("no_secret")
    return {"CAFEBAZAAR-PISHKHAN-API-SECRET": s.bazaar_api_secret}


def _fail(r: httpx.Response) -> ReviewsError:
    if r.status_code in (401, 403):
        return ReviewsError("denied", r.status_code)
    if r.status_code == 429:
        return ReviewsError("rate_limited", 429)
    if r.status_code >= 500:
        return ReviewsError("unreachable", r.status_code)
    return ReviewsError("bazaar_error", r.status_code)


def _item(x: dict) -> dict:
    reply = x.get("developer_reply") if isinstance(x.get("developer_reply"), dict) else None
    return {
        "id": x.get("id"), "rate": x.get("rate"), "text": str(x.get("text") or "")[:2000],
        "app_version_code": x.get("app_version_code"), "sdk_version": x.get("sdk_version"),
        "publish_date": x.get("publish_date"), "is_edited": bool(x.get("is_edited")),
        "likes": x.get("likes") or 0, "dislikes": x.get("dislikes") or 0,
        "reply": ({"text": str(reply.get("text") or "")[:2000], "publish_date": reply.get("publish_date")} if reply else None),
    }


def _cursor_of(link: object, s: Settings) -> str | None:
    """The `cursor` query value of a next/previous link. Only links on Bazaar's own host are followed, and only the
    cursor value is kept, so the admin page can never make the server fetch another address."""
    if not isinstance(link, str) or not link:
        return None
    u = urlsplit(link)
    base = urlsplit(s.bazaar_reviews_base_url)
    if u.netloc and u.netloc != base.netloc:
        return None
    return dict(parse_qsl(u.query)).get("cursor") or None


async def list_reviews(s: Settings, *, only_unreplied: bool = False, max_rate: int | None = None,
                       cursor: str | None = None, http: httpx.AsyncClient | None = None) -> dict:
    """One page of reviews, newest first as Bazaar returns them: {"items": [...], "next": cursor | None}."""
    headers = _headers(s)
    if max_rate is not None and not 1 <= max_rate <= 5:
        max_rate = None
    if cursor is not None and (len(cursor) > 300 or not cursor.strip()):
        raise ReviewsError("bad_cursor")
    params: dict = {}
    if only_unreplied:
        params["is_replied"] = "false"
    if max_rate is not None:
        params["rate_max"] = max_rate
    if cursor:
        params["cursor"] = cursor

    async def load() -> dict:
        client = http or httpx.AsyncClient(timeout=10)
        try:
            r = await client.get(f"{s.bazaar_reviews_base_url}{PAGE}", headers=headers, params=params)
        except httpx.HTTPError:
            raise ReviewsError("unreachable")
        finally:
            if http is None:
                await client.aclose()
        if r.status_code != 200:
            raise _fail(r)
        try:
            body = r.json()
        except ValueError:
            raise ReviewsError("bazaar_error", r.status_code)
        rows = body.get("results") if isinstance(body, dict) else None
        rows = rows if isinstance(rows, list) else []
        return {"items": [_item(x) for x in rows[:50] if isinstance(x, dict)], "next": _cursor_of(body.get("next"), s)}

    key = (s.bazaar_reviews_base_url, only_unreplied, max_rate, cursor or "")
    return await _cache.get_or_load(key, load)


async def reply(s: Settings, review_id: object, text: object, *, http: httpx.AsyncClient | None = None) -> None:
    """Sends one reply (Bazaar shows it after its own approval). Raises ReviewsError; returns None on 201."""
    headers = _headers(s)
    try:
        rid = int(review_id)
    except (TypeError, ValueError):
        raise ReviewsError("bad_id")
    if rid <= 0:
        raise ReviewsError("bad_id")
    body = str(text or "").strip()
    if not REPLY_MIN <= len(body) <= REPLY_MAX:
        raise ReviewsError("bad_reply")
    client = http or httpx.AsyncClient(timeout=10)
    try:
        r = await client.post(f"{s.bazaar_reviews_base_url}{PAGE}{rid}/", headers=headers, json={"text": body})
    except httpx.HTTPError:
        log.info("review reply id=%s status=unreachable", rid)
        raise ReviewsError("unreachable")
    finally:
        if http is None:
            await client.aclose()
    log.info("review reply id=%s status=%s", rid, r.status_code)
    if r.status_code != 201:
        raise _fail(r)
    _cache.clear()
