"""Small helpers shared by the routers."""
import re
import secrets
import unicodedata
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import select, update
from sqlalchemy.orm.attributes import set_committed_value
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


_NAME_PUNCT = {"_", ".", "-"}


def nickname_problem(name: str) -> str | None:
    """Why a detective name is not acceptable, as a stable code (None = fine). Codes: `nickname_length` (2-16 letters),
    `nickname_chars` (only letters of any language, digits, one space between words, ZWNJ and _ . - are allowed; emoji,
    stickers, symbols, control and invisible characters are not), `bad_nickname` (a link, a blocked word, too many digits)."""
    name = " ".join(name.split())
    if not (2 <= len(name) <= 16):
        return "nickname_length"
    for ch in name:
        cat = unicodedata.category(ch)
        ok = cat[0] == "L" or cat == "Nd" or ch == " " or ch == "\u200c" or ch in _NAME_PUNCT
        if not ok:           # emoji (So, Sk, Cs), ZWJ and variation selectors (Cf, Mn), arrows, hearts, control characters ...
            return "nickname_chars"
    if not any(unicodedata.category(ch)[0] == "L" for ch in name):
        return "nickname_chars"   # digits and dots only
    if _URL.search(name):
        return "bad_nickname"
    low = name.lower().replace(" ", "")
    if any(b in low for b in _BLOCKED) or sum(ch.isdigit() for ch in name) > 6:
        return "bad_nickname"
    return None


def clean_nickname(name: str) -> str | None:
    return None if nickname_problem(name) else " ".join(name.split())


async def add_coins(session: AsyncSession, player: Player, amount: int, reason: str) -> None:
    """Atomic delta + ledger in the caller's transaction; never commit or silently clamp a debit.

    Eligibility/one-time flags must be read under db.lock_players before calling this helper.
    The SQL expression also protects callers holding a stale ORM balance.
    """
    await session.flush([player])  # new players need their defaults/id; defer unrelated unique claims to caller
    stmt = update(Player).where(Player.id == player.id)
    if amount < 0:
        stmt = stmt.where(Player.coins >= -amount)
    with session.no_autoflush:
        balance = await session.scalar(stmt.values(coins=Player.coins + amount).returning(Player.coins)
                                       .execution_options(synchronize_session=False))
    if balance is None:
        raise HTTPException(402, {"error": "not_enough_coins", "need": -amount})
    set_committed_value(player, "coins", balance)
    session.add(CoinLog(player_id=player.id, amount=amount, reason=reason[:48], balance=balance))
