"""Unique detective names (Amin, 28 Oct 2026): nobody can take a name another detective already has.

A name is compared by its KEY, not by its letters: case, spaces, zero-width joiners, punctuation, Arabic/Persian letter
variants (ي/ی, ك/ک) and digit scripts are ignored, so «علی»، «علي»، «Ali» and «ali » all collide. One row per taken key
(`nickname_claims`, key = primary key) makes two simultaneous requests safe: only one INSERT wins, on SQLite and Postgres.
The random default name «کارآگاه1234» is never claimed (only 9000 of them exist); players that already share a name keep
it: the migration claims each name for its oldest owner and the others stay unclaimed until they rename.
"""
from __future__ import annotations

import re
import unicodedata

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .models import NicknameClaim

DEFAULT_RE = re.compile(r"^کارآگاه\d{4}$")
_DIGITS = {ord(c): str(i) for i, c in enumerate("۰۱۲۳۴۵۶۷۸۹")} | {ord(c): str(i) for i, c in enumerate("٠١٢٣٤٥٦٧٨٩")}
_LETTERS = {ord("ي"): "ی", ord("ى"): "ی", ord("ك"): "ک", ord("ە"): "ه", ord("ة"): "ه"}


def nickname_key(name: str) -> str:
    """The comparison key of a name (at most 16 letters and digits, so it fits the 40-character column)."""
    s = unicodedata.normalize("NFKC", name).lower().translate(_DIGITS).translate(_LETTERS)
    key = "".join(ch for ch in s if ch.isalnum() and not 0x064B <= ord(ch) <= 0x065F)
    return key[:40] or "".join(s.split())[:40]


def is_default(name: str) -> bool:
    return bool(DEFAULT_RE.match(name or ""))


async def claim(session: AsyncSession, player_id: str, name: str) -> bool:
    """Takes `name` for the player (and frees the name he had). False = another detective has it. Call it BEFORE changing
    anything else in the request: on a lost race the session is rolled back."""
    key = nickname_key(name)
    mine = list((await session.execute(select(NicknameClaim).where(NicknameClaim.player_id == player_id))).scalars())
    if any(c.key == key for c in mine):
        return True
    if await session.scalar(select(NicknameClaim.player_id).where(NicknameClaim.key == key)) is not None:
        return False
    for c in mine:
        await session.delete(c)
    if not is_default(name):
        session.add(NicknameClaim(key=key, player_id=player_id))
    try:
        await session.flush()
    except IntegrityError:
        await session.rollback()
        return False
    return True
