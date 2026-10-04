"""Login tokens, secrets and the "who is calling" checks."""
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from .config import get_settings
from .db import get_session
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
    cred: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> Player:
    if cred is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no_token")
    player_id, gen = read_token(cred.credentials)
    player = await session.get(Player, player_id)
    if player is None or gen != player.token_gen:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "no_player")
    if player.banned:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "banned")
    now = utcnow()
    if (now - player.last_seen).total_seconds() > 300:
        player.last_seen = now
        await session.commit()
    return player


async def require_admin(x_admin_key: str = Header(default="")) -> None:
    if not hmac.compare_digest(x_admin_key, get_settings().admin_api_key):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not_admin")
