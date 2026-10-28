"""Cafe Bazaar reviews in the admin panel (28 Oct 2026): list, filters, pagination, reply, and every failure."""
import json

import httpx
import pytest

from app.config import Settings
from app.services import bazaar_reviews as br
from .conftest import ADMIN

BASE = "https://sandoghche.cafebazaar.ir"


@pytest.fixture(autouse=True)
def fresh_cache():
    br._cache.clear()
    yield
    br._cache.clear()


def settings(secret="sec"):
    return Settings(bazaar_api_secret=secret, bazaar_reviews_base_url=BASE)


def client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def page(n=2, nxt=None, replied=False):
    return {"results": [{"id": 100 + i, "rate": 1 + i, "text": f"نظر {i}", "app_version_code": 79, "sdk_version": 30,
                         "publish_date": "2026-10-28T10:00:00Z", "likes": 0, "dislikes": 0,
                         "developer_reply": {"text": "ممنون", "publish_date": "2026-10-28T11:00:00Z"} if replied else None}
                        for i in range(n)], "next": nxt, "previous": None}


async def test_list_sends_secret_and_filters_and_normalises():
    seen = []

    def handler(req):
        seen.append(req)
        return httpx.Response(200, json=page(2, f"{BASE}/api/v0/reviews/?cursor=abc123"))

    d = await br.list_reviews(settings(), only_unreplied=True, max_rate=3, http=client(handler))
    r = seen[0]
    assert r.headers["CAFEBAZAAR-PISHKHAN-API-SECRET"] == "sec"
    assert r.url.params["is_replied"] == "false" and r.url.params["rate_max"] == "3"
    assert [i["id"] for i in d["items"]] == [100, 101] and d["next"] == "abc123"
    assert d["items"][0]["reply"] is None


async def test_next_link_on_another_host_is_ignored_and_cursor_is_passed_back():
    seen = []

    def handler(req):
        seen.append(req)
        return httpx.Response(200, json=page(1, "https://evil.example/api/v0/reviews/?cursor=zzz"))

    d = await br.list_reviews(settings(), cursor="abc123", http=client(handler))
    assert d["next"] is None and seen[0].url.params["cursor"] == "abc123"
    assert str(seen[0].url).startswith(BASE)


async def test_list_is_cached_for_a_minute():
    calls = []

    def handler(req):
        calls.append(1)
        return httpx.Response(200, json=page(1))

    c = client(handler)
    await br.list_reviews(settings(), http=c)
    await br.list_reviews(settings(), http=c)
    assert len(calls) == 1
    await br.list_reviews(settings(), only_unreplied=True, http=c)
    assert len(calls) == 2


@pytest.mark.parametrize("status,code", [(401, "denied"), (403, "denied"), (429, "rate_limited"),
                                           (500, "unreachable"), (503, "unreachable"), (404, "bazaar_error")])
async def test_list_failures_have_stable_codes(status, code):
    with pytest.raises(br.ReviewsError) as e:
        await br.list_reviews(settings(), http=client(lambda req: httpx.Response(status, json={})))
    assert e.value.code == code and e.value.message


async def test_timeout_and_garbage_and_no_secret():
    def boom(req):
        raise httpx.ConnectTimeout("slow")

    with pytest.raises(br.ReviewsError) as e:
        await br.list_reviews(settings(), http=client(boom))
    assert e.value.code == "unreachable"
    with pytest.raises(br.ReviewsError) as e:
        await br.list_reviews(settings(), http=client(lambda req: httpx.Response(200, text="<html>")))
    assert e.value.code == "bazaar_error"
    with pytest.raises(br.ReviewsError) as e:
        await br.list_reviews(settings(secret=""), http=client(lambda req: httpx.Response(200, json=page())))
    assert e.value.code == "no_secret"


async def test_reply_201_sends_trimmed_text_and_clears_the_cache():
    sent = []

    def handler(req):
        if req.method == "POST":
            sent.append(req)
            return httpx.Response(201, json={})
        return httpx.Response(200, json=page(1))

    c = client(handler)
    await br.list_reviews(settings(), http=c)
    await br.reply(settings(), "100", "  ممنون از نظرت  ", http=c)
    assert str(sent[0].url) == f"{BASE}/api/v0/reviews/100/"
    assert json.loads(sent[0].content) == {"text": "ممنون از نظرت"}
    assert sent[0].headers["CAFEBAZAAR-PISHKHAN-API-SECRET"] == "sec"
    assert br._cache._d == {} or len(br._cache._d) == 0


@pytest.mark.parametrize("rid,text,code", [("x", "ممنون از نظرت", "bad_id"), (0, "ممنون از نظرت", "bad_id"),
                                           (5, "کم", "bad_reply"), (5, "ا" * 501, "bad_reply"), (5, "   ", "bad_reply")])
async def test_reply_validates_before_sending(rid, text, code):
    def handler(req):
        raise AssertionError("must not be sent")

    with pytest.raises(br.ReviewsError) as e:
        await br.reply(settings(), rid, text, http=client(handler))
    assert e.value.code == code


@pytest.mark.parametrize("status,code", [(403, "denied"), (429, "rate_limited"), (502, "unreachable"), (400, "bazaar_error")])
async def test_reply_failures(status, code):
    with pytest.raises(br.ReviewsError) as e:
        await br.reply(settings(), 7, "ممنون از نظرت", http=client(lambda req: httpx.Response(status, json={})))
    assert e.value.code == code


async def test_reply_log_has_no_text(caplog):
    caplog.set_level("INFO", logger="bazaar_reviews")
    await br.reply(settings(), 7, "متن محرمانه پاسخ", http=client(lambda req: httpx.Response(201, json={})))
    assert "id=7" in caplog.text and "محرمانه" not in caplog.text and "sec" not in caplog.text


# ---- the admin routes
async def test_admin_routes_need_the_key_and_never_500(client, monkeypatch):
    assert (await client.get("/admin/api/bazaar-reviews")).status_code == 403
    assert (await client.post("/admin/api/bazaar-reviews/5/reply", json={"text": "ممنون از نظرت"})).status_code == 403
    # no token configured in tests: a friendly answer, not an error page
    d = (await client.get("/admin/api/bazaar-reviews", headers=ADMIN)).json()
    assert d["ok"] is False and d["error"] == "no_secret" and "BAZAAR_API_SECRET" in d["detail"]
    r = (await client.post("/admin/api/bazaar-reviews/5/reply", headers=ADMIN, json={"text": "ممنون از نظرت"})).json()
    assert r["ok"] is False and r["error"] == "no_secret"
    assert (await client.get("/admin/api/bazaar-reviews?max_rate=9", headers=ADMIN)).status_code == 422
    assert "reviews" in (await client.get("/admin/ui")).text
