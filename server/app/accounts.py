"""Helpers for permanent accounts: email + password."""
from __future__ import annotations

import base64
import hashlib
import hmac
import re
import secrets

_EMAIL = re.compile(r"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$")


def normalize_email(raw: str) -> str | None:
    e = (raw or "").strip().lower()
    return e if len(e) <= 120 and _EMAIL.match(e) else None


def mask_email(email: str | None) -> str | None:
    if not email or "@" not in email:
        return None
    name, domain = email.split("@", 1)
    return (name[:2] + "***@" + domain) if len(name) > 2 else (name[:1] + "***@" + domain)


def password_ok(pw: str) -> bool:
    return 6 <= len(pw or "") <= 64


def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(h).decode()


def check_password(pw: str, stored: str | None) -> bool:
    if not stored or not stored.startswith("scrypt$"):
        return False
    _, salt_b64, h_b64 = stored.split("$")
    h = hashlib.scrypt(pw.encode(), salt=base64.b64decode(salt_b64), n=2**14, r=8, p=1, dklen=32)
    return hmac.compare_digest(h, base64.b64decode(h_b64))
