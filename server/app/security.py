"""Login tokens, secrets and the "who is calling" checks."""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from collections.abc import AsyncIterator

import jwt
from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .config import get_settings
from .db import get_session, lock_players
from .models import Player, utcnow

_bearer = HTTPBearer(auto_error=False)
_ALGO = "HS256"

# Letters that can't be confused with each other (no 0/O, 1/I/L)
_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def new_secret() -> str:
    """A long random secret the phone keeps (like a password nobody types)."""
    return secrets.token_urlsafe(32)


def hash_secret(secret: str) -> str:
    # The secret is 256 random bits, so a plain SHA-256 is enough here.
    return hashlib.sha256(secret.encode()).hexdigest()


def secret_matches(secret: str, hashed: str) -> bool:
    return hmac.compare_digest(hash_secret(secret), hashed)


def random_code(n: int = 6) -> str:
    return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(n))


def make_token(player_id: str, gen: int = 0) -> tuple[str, int]:
    s = get_settings()
    exp = datetime.now(timezone.utc) + timedelta(days=s.jwt_days)
    token = jwt.encode({"sub": player_id, "gen": gen, "exp": exp}, s.jwt_secret, algorithm=_ALGO)
    return token, int(exp.timestamp())


def read_token(token: str) -> tuple[str, int]:
    try:
        data = jwt.decode(token, get_settings().jwt_secret, algorithms=[_ALGO])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "token_expired")
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "bad_token")
    return str(data["sub"]), int(data.get("gen", 0))


async def current_player(
    request: Request,
    cred: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> AsyncIterator[Player]:
    if cred is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no_token")
    player_id, gen = read_token(cred.credentials)
    # Every authenticated mutation locks BEFORE reading one-time claims/counters/progress.
    # These two GETs grant rewards too. Inbox settlement locks its complete winner set itself.
    writing = request.method not in ("GET", "HEAD", "OPTIONS") or request.url.path.rstrip("/") in (
        "/v1/me", "/v1/avatars") or (request.method == "GET" and
        request.url.path.startswith("/v1/cases/") and request.url.path.count("/") == 3)
    player = ((await lock_players(session, [player_id])).get(player_id) if writing
              else await session.get(Player, player_id))
    if player is None or gen != player.token_gen:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no_player")
    if player.banned:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "banned")
    now = utcnow()
    touch = (now - player.last_seen).total_seconds() > 300
    if touch and not writing:
        player.last_seen = now
        await session.commit()
    try:
        yield player
        if writing:
            # Defer this write: rate-limit checks inside handlers use an independent
            # transaction and must not wait on a SQLite writer held by last_seen.
            if touch:
                player.last_seen = now
            await session.commit()
    except Exception:
        await session.rollback()
        raise


async def require_admin(x_admin_key: str = Header(default="")) -> None:
    # the built-in dev key is public (it is in the repo): never accept it, whatever ENV says
    if get_settings().admin_api_key == "change-me-admin-dev-only":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "admin_disabled")
    if not hmac.compare_digest(x_admin_key, get_settings().admin_api_key):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not_admin")



async def require_analytics(x_analytics_key: str = Header(default="")) -> None:
    """An independent, expiring report-only key; never an admin/JWT credential."""
    s = get_settings()
    digest = s.analytics_api_key_sha256
    now = int(datetime.now(timezone.utc).timestamp())
    if (not digest or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest)
            or s.analytics_api_key_expires_at <= now or not 32 <= len(x_analytics_key) <= 256):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "analytics_forbidden")
    supplied = hash_secret(x_analytics_key)
    if (not hmac.compare_digest(supplied, digest)
            or hmac.compare_digest(supplied, hash_secret(s.admin_api_key))
            or hmac.compare_digest(supplied, hash_secret(s.jwt_secret))):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "analytics_forbidden")
