"""Phone-secured accounts: SMS code (fake provider), one phone per account, new-device login, abuse paths."""
from datetime import timedelta

import pytest
from sqlalchemy import select, update

from app import db
from app.config import get_settings
from app.models import PhoneCode, Player, utcnow
from app.services import sms

from .conftest import new_player
from .test_ratelimit import clock, mk  # noqa: F401  (fixture + helper for the rate-limit tests)

PHONE = "09123456789"


@pytest.fixture(autouse=True)
def _fake_sms(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "sms_enabled", True)
    monkeypatch.setattr(s, "sms_mode", "fake")
    sms.FAKE_OUTBOX.clear()


def last_code():
    return sms.FAKE_OUTBOX[-1][1]


async def secure(client, p, phone=PHONE):
    r = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": phone})
    assert r.status_code == 200, r.text
    return await client.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": phone, "code": last_code()})


def test_normalize_phone():
    for raw in ("09123456789", "9123456789", "+989123456789", "00989123456789", "0912 345 6789", "۰۹۱۲۳۴۵۶۷۸۹"):
        assert sms.normalize_phone(raw) == PHONE
    for bad in ("", "0212345678", "09123", "abcdefghijk", "08123456789"):
        assert sms.normalize_phone(bad) is None


async def test_secure_account_with_phone(client):
    p = await new_player(client, "dev-phone-1")
    before = (await client.get("/v1/me", headers=p["headers"])).json()
    assert before["secured"] is False and before["phone"] is None
    r = await secure(client, p)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["reward"] > 0 and body["profile"]["secured"] is True and body["profile"]["phone"].endswith("6789")
    assert PHONE not in r.text
    async with db.SessionLocal() as s:  # the plain number is never stored
        pl = await s.get(Player, p["player_id"])
        assert pl.phone_hash and PHONE not in pl.phone_hash and pl.phone_last4 == "6789"
        codes = (await s.scalars(select(PhoneCode))).all()
        assert all(PHONE not in c.code_hash for c in codes)
    # a second time: already set; no second reward
    again = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09120000001"})
    assert again.status_code == 409 and again.json()["detail"] == "phone_already_set"


async def test_wrong_code_expiry_and_attempt_cap(client):
    p = await new_player(client, "dev-phone-2")
    await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09121111111"})
    good = last_code()
    wrong = "00000" if good != "00000" else "11111"
    r = await client.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": "09121111111", "code": wrong})
    assert r.status_code == 400 and r.json()["detail"] == "bad_code"
    for _ in range(sms.MAX_TRIES):  # the code is burnt after too many wrong tries, even the right one then fails
        await client.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": "09121111111", "code": wrong})
    r = await client.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": "09121111111", "code": good})
    assert r.status_code == 400 and r.json()["detail"] == "code_expired"
    # expiry
    await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09121111111"})
    code = last_code()
    async with db.SessionLocal() as s:
        await s.execute(update(PhoneCode).values(expires_at=utcnow() - timedelta(seconds=1)))
        await s.commit()
    r = await client.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": "09121111111", "code": code})
    assert r.status_code == 400 and r.json()["detail"] == "code_expired"


async def test_code_works_once_and_only_for_the_asking_player(client):
    a = await new_player(client, "dev-phone-3a")
    b = await new_player(client, "dev-phone-3b")
    await client.post("/v1/auth/phone/send", headers=a["headers"], json={"phone": "09122222222"})
    code = last_code()
    r = await client.post("/v1/auth/phone/verify", headers=b["headers"], json={"phone": "09122222222", "code": code})
    assert r.status_code == 400  # b can't use a's code
    r = await client.post("/v1/auth/phone/verify", headers=a["headers"], json={"phone": "09122222222", "code": code})
    assert r.status_code == 200  # b's try did not burn a's code
    r = await client.post("/v1/auth/phone/verify", headers=a["headers"], json={"phone": "09122222222", "code": code})
    assert r.status_code == 400  # a code works once


async def test_one_phone_one_account(client):
    a = await new_player(client, "dev-phone-4a")
    b = await new_player(client, "dev-phone-4b")
    assert (await secure(client, a, "09123333333")).status_code == 200
    n = len(sms.FAKE_OUTBOX)
    r = await client.post("/v1/auth/phone/send", headers=b["headers"], json={"phone": "09123333333"})
    assert r.status_code == 409 and r.json()["detail"] == "phone_taken"
    assert len(sms.FAKE_OUTBOX) == n  # no SMS was paid for


async def test_new_device_login_logs_the_old_one_out(client):
    a = await new_player(client, "dev-phone-5a")
    assert (await secure(client, a, "09124444444")).status_code == 200
    r = await client.post("/v1/auth/phone/login/send", json={"phone": "09124444444", "device_id": "dev-phone-5new"})
    assert r.status_code == 200
    r = await client.post("/v1/auth/phone/login", json={"phone": "09124444444", "code": last_code(),
                                                        "device_id": "dev-phone-5new"})
    assert r.status_code == 200, r.text
    assert r.json()["player_id"] == a["player_id"]
    new_headers = {"Authorization": "Bearer " + r.json()["token"]}
    assert (await client.get("/v1/me", headers=new_headers)).status_code == 200
    assert (await client.get("/v1/me", headers=a["headers"])).status_code == 401  # old phone logged out


async def test_login_send_for_unknown_number_sends_nothing(client):
    n = len(sms.FAKE_OUTBOX)
    r = await client.post("/v1/auth/phone/login/send", json={"phone": "09129999999", "device_id": "dev-phone-6"})
    assert r.status_code == 200 and len(sms.FAKE_OUTBOX) == n  # same answer, no cost, no enumeration
    r = await client.post("/v1/auth/phone/login", json={"phone": "09129999999", "code": "12345", "device_id": "dev-phone-6"})
    assert r.status_code == 400


async def test_bad_phone_and_kill_switch(client, monkeypatch):
    p = await new_player(client, "dev-phone-7")
    r = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "12345678901"})
    assert r.status_code == 422 and r.json()["detail"] == "bad_phone"
    monkeypatch.setattr(get_settings(), "sms_enabled", False)
    r = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09127000001"})
    assert r.status_code == 503 and r.json()["detail"] == "sms_unavailable"


async def test_fake_provider_refused_in_production(client, monkeypatch):
    p = await new_player(client, "dev-phone-8")
    monkeypatch.setattr(get_settings(), "env", "prod")
    r = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09127000002"})
    assert r.status_code == 503 and sms.FAKE_OUTBOX == []


async def test_provider_failure_fails_closed(client, monkeypatch):
    p = await new_player(client, "dev-phone-9")

    async def boom(phone, code):
        raise sms.SmsError("sms_failed")
    monkeypatch.setattr(sms, "send_code", boom)
    r = await client.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09125555555"})
    assert r.status_code == 503 and r.json()["detail"] == "sms_failed"
    async with db.SessionLocal() as s:  # the unsent code is not usable
        assert all(c.used for c in (await s.scalars(select(PhoneCode).where(
            PhoneCode.phone_hash == sms.phone_hash("09125555555")))).all())


async def test_ghasedak_request_shape(monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "sms_mode", "ghasedak")
    monkeypatch.setattr(s, "sms_api_key", "k" * 20)
    monkeypatch.setattr(s, "sms_template", "tpl")
    seen = {}

    class R:
        status_code = 200

        def json(self):
            return {"isSuccess": True}

    class C:
        def __init__(self, **kw):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, url, json=None, headers=None):
            seen.update(url=url, json=json, headers=headers)
            return R()
    monkeypatch.setattr(sms.httpx, "AsyncClient", C)
    await sms.send_code(PHONE, "12345")
    assert seen["headers"] == {"apikey": "k" * 20} and seen["json"]["param1"] == "12345"
    assert seen["json"]["templateName"] == "tpl" and seen["json"]["receptors"][0]["mobile"] == PHONE


async def test_abuse_limits(clock, client):  # noqa: F811
    """SMS pumping: one phone gets 1 a minute / 3 an hour; one device 6 a day; a daily ceiling for everything."""
    p = await new_player(client, "dev-phone-10")
    async with mk() as c:
        h = p["headers"]
        send = lambda ph: c.post("/v1/auth/phone/send", headers=h, json={"phone": ph})  # noqa: E731
        assert (await send("09126666666")).status_code == 200
        r = await send("09126666666")  # again within a minute
        assert r.status_code == 429
        ok = 2
        for _ in range(5):  # same number: at most 3 an hour
            clock.advance(61)
            ok += (await send("09126666666")).status_code == 200
        assert ok == 3
        # many different numbers from one device: stopped at 6 a day in total
        total = ok
        for i in range(10):
            clock.advance(61)
            total += (await send(f"091277000{i:02d}")).status_code == 200
        assert total <= 6


async def test_wrong_code_guessing_is_limited(clock, client):  # noqa: F811
    p = await new_player(client, "dev-phone-11")
    async with mk() as c:
        await c.post("/v1/auth/phone/send", headers=p["headers"], json={"phone": "09128888888"})
        codes = []
        for _ in range(30):
            r = await c.post("/v1/auth/phone/verify", headers=p["headers"], json={"phone": "09128888888", "code": "00000"})
            codes.append(r.status_code)
        assert 429 in codes


async def test_admin_sms_test_button(client, monkeypatch):
    from .conftest import ADMIN
    r = await client.post("/admin/api/sms-test", json={"phone": "0912"})
    assert r.status_code in (401, 403)  # needs the admin key
    r = await client.post("/admin/api/sms-test", headers=ADMIN, json={"phone": "abcdefghijk"})
    assert r.json()["ok"] is False and r.json()["error"] == "bad_phone"
    r = await client.post("/admin/api/sms-test", headers=ADMIN, json={"phone": "09128000001"})
    assert r.json()["ok"] is True and len(sms.FAKE_OUTBOX) == 1  # fake mode: no real SMS

    async def boom(phone, code):
        raise sms.SmsError("sms_failed", "http 400 template not approved")
    monkeypatch.setattr(sms, "send_code", boom)
    r = await client.post("/admin/api/sms-test", headers=ADMIN, json={"phone": "09128000002"})
    assert r.json() == {"ok": False, "error": "sms_failed", "detail": "http 400 template not approved"}


async def test_email_account_needs_phone_until_linked(client, monkeypatch):
    p = await new_player(client, "dev-phone-12")
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["needs_phone"] is False  # a guest is never forced
    r = await client.post("/v1/auth/email", headers=p["headers"], json={"email": "gate12@example.com", "password": "secret12"})
    assert r.status_code == 200
    assert (await client.get("/v1/me", headers=p["headers"])).json()["needs_phone"] is True
    r = await secure(client, p, "09129000012")  # linking the phone keeps the account and pays no second reward
    assert r.status_code == 200 and r.json()["reward"] == 0
    me = (await client.get("/v1/me", headers=p["headers"])).json()
    assert me["needs_phone"] is False and me["secured"] is True and me["phone"].endswith("0012")
    q = await new_player(client, "dev-phone-13")
    await client.post("/v1/auth/email", headers=q["headers"], json={"email": "gate13@example.com", "password": "secret12"})
    monkeypatch.setattr(get_settings(), "require_phone_for_email", False)
    assert (await client.get("/v1/me", headers=q["headers"])).json()["needs_phone"] is False  # switch off


async def test_new_email_accounts_are_closed_by_default(client, monkeypatch):
    p = await new_player(client, "dev-phone-14")
    monkeypatch.setattr(get_settings(), "email_signup_enabled", False)
    r = await client.post("/v1/auth/email", headers=p["headers"], json={"email": "closed14@example.com", "password": "secret12"})
    assert r.status_code == 403 and r.json()["detail"] == "email_closed"
    assert (await client.get("/v1/me", headers=p["headers"])).json()["secured"] is False
