"""«به نظر تو کیه؟»: the player's first guess (before the evidence is opened) and what other detectives first guessed.

- One row per player and case (case_guesses, unique): written once with insert-or-ignore, never changed.
- Community numbers: one grouped count per case, cached per worker for 60 s (bounded), no player ids in them. They are
  hidden until MIN_PUBLIC guesses exist, and the endpoint shows them only to a player who may see the answer.
"""
from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .cache import TTLCache
from .models import CaseGuess

UNKNOWN = "?"      # «نمی‌دونم»
MIN_PUBLIC = 20    # fewer guesses than this show no percentages (they would be noise, or identify a person)

_counts = TTLCache("guess_counts", ttl=60, max_size=256)


async def counts(session: AsyncSession, case_id: str) -> dict[str, int]:
    async def load():
        return {k: int(n) for k, n in (await session.execute(
            select(CaseGuess.suspect, func.count()).where(CaseGuess.case_id == case_id)
            .group_by(CaseGuess.suspect))).all()}
    return await _counts.get_or_load(case_id, load)


def community(raw: dict[str, int], suspect_ids: list[str]) -> dict | None:
    """Percent of detectives who first suspected each suspect (and who said «نمی‌دونم»); None below MIN_PUBLIC."""
    total = sum(n for k, n in raw.items() if k == UNKNOWN or k in suspect_ids)
    if total < MIN_PUBLIC:
        return None
    return {"total": total, "unknown_pct": round(100 * raw.get(UNKNOWN, 0) / total),
            "suspects": [{"id": sid, "pct": round(100 * raw.get(sid, 0) / total)} for sid in suspect_ids]}
