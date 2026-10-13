"""Sending SMS codes. One provider (Ghasedak) behind a tiny interface; `fake` never sends and is for tests.

Rules: the API key comes from the environment only and is never logged; the phone number is never logged;
a broken provider means "no code" (fail closed), never "let them in".
"""
from __future__ import annotations

import hashlib
import hmac
import logging
import re
import secrets

import httpx

from ..config import get_settings

log = logging.getLogger("sms")

FAKE_OUTBOX: list[tuple[str, str]] = []  # (phone, code): tests read it; bounded
_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
CODE_TTL = 300
MAX_TRIES = 5


class SmsError(Exception):
    def __init__(self, code: str, detail: str = ""):
        super().__init__(code)
        self.code = code  # "sms_unavailable" | "sms_failed"
        self.detail = detail  # what the provider said (short, never the key); only the admin test shows it


def normalize_phone(raw: str) -> str | None:
    """Iranian mobile numbers only -> '09xxxxxxxxx' (accepts Persian digits, +98, 0098, spaces, dashes)."""
    s = re.sub(r"[\s\-()]", "", (raw or "").translate(_DIGITS))
    for prefix in ("+98", "0098", "98"):
        if s.startswith(prefix) and len(s) >= 12:
            s = "0" + s[len(prefix):]
            break
    if re.fullmatch(r"9\d{9}", s):
        s = "0" + s
    return s if re.fullmatch(r"09\d{9}", s) else None


def _pepper() -> bytes:
    s = get_settings()
    return (s.phone_pepper or ("phone:" + s.jwt_secret)).encode()


def phone_hash(phone: str) -> str:
    return hmac.new(_pepper(), b"p:" + phone.encode(), hashlib.sha256).hexdigest()


def code_hash(phash: str, code: str) -> str:
    return hmac.new(_pepper(), f"c:{phash}:{code}".encode(), hashlib.sha256).hexdigest()


def new_code() -> str:
    return "".join(secrets.choice("0123456789") for _ in range(5))


def available() -> bool:
    s = get_settings()
    if not s.sms_enabled:
        return False
    if s.sms_mode == "ghasedak":
        return bool(s.sms_api_key and s.sms_template)
    return s.sms_mode == "fake" and s.env != "prod"


async def send_code(phone: str, code: str) -> None:
    s = get_settings()
    if not available():
        raise SmsError("sms_unavailable")
    if s.sms_mode == "fake":
        FAKE_OUTBOX.append((phone, code))
        del FAKE_OUTBOX[:-50]
        return
    body = {"receptors": [{"mobile": phone, "clientReferenceId": secrets.token_hex(6)}],
            "templateName": s.sms_template, "param1": code, "isVoice": False, "udh": False}
    try:
        async with httpx.AsyncClient(timeout=8.0) as c:
            r = await c.post(s.sms_url, json=body, headers={"apikey": s.sms_api_key})
        data = r.json() if r.content else {}
        ok = r.status_code == 200 and bool((data or {}).get("isSuccess", False))
    except Exception as e:  # network, bad JSON...
        log.warning("sms: provider error %s", type(e).__name__)
        raise SmsError("sms_failed", "no valid answer from the provider: " + type(e).__name__)
    if not ok:
        log.warning("sms: provider refused (http %s)", r.status_code)
        msg = str((data or {}).get("message", "")) if isinstance(data, dict) else ""
        raise SmsError("sms_failed", f"http {r.status_code} {msg}"[:160])
    log.info("sms: sent")
