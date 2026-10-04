"""Small helpers shared by the routers."""
import re
import secrets
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import CoinLog, Player
from .security import random_code


def ts(dt: datetime | None) -> int | None:
    """UTC datetime (stored without tz) -> unix seconds."""
    if dt is None:
        return None
    return int(dt.replace(tzinfo=timezone.utc).timestamp())


def from_ts(seconds: int) -> datetime:
    return datetime.fromtimestamp(seconds, timezone.utc).replace(tzinfo=None)


async def unique_invite_code(session: AsyncSession) -> str:
    for _ in range(20):
        code = random_code(6)
        found = await session.scalar(select(Player.id).where(Player.invite_code == code))
        if not found:
            return code
    return random_code(10)


def default_nickname() -> str:
    return f"کارآگاه{secrets.randbelow(9000) + 1000}"


_URL = re.compile(r"(https?://|www\.|\.ir\b|\.com\b|@|t\.me)", re.I)
_BLOCKED = ["کس", "کیر", "کون", "جنده", "fuck", "sex", "admin", "مدیر"]


def clean_nickname(name: str) -> str | None:
    name = " ".join(name.split())
    if not (2 <= len(name) <= 16) or _URL.search(name):
        return None
    low = name.lower().replace(" ", "")
    if any(b in low for b in _BLOCKED) or sum(ch.isdigit() for ch in name) > 6:
        return None
    return name


def add_coins(session: AsyncSession, player: Player, amount: int, reason: str) -> None:
    """Changes the wallet and writes a log line (caller commits)."""
    player.coins = max(0, player.coins + amount)
    session.add(CoinLog(player_id=player.id, amount=amount, reason=reason[:48], balance=player.coins))
