"""Star ratings and comment counts shown on the case cards (home, archive).

One aggregate over the approved root comments, the same for every player, so it is shared for 30 s per worker
(app/cache.py rules). A star-only rating counts at once (it is approved when written); a written comment counts
after the admin approved it. The player's own rating is read per request (one indexed query on player_id).
"""
from __future__ import annotations

from sqlalchemy import case as sql_case
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .cache import TTLCache
from .models import CaseComment

_summary = TTLCache("rating_summary", ttl=30, max_size=2)


def clear() -> None:
    """A comment was written or moderated: this worker shows it at once, the others within 30 s."""
    _summary.clear()


async def summary(session: AsyncSession) -> dict[str, tuple[float, int, int]]:
    """case_id -> (average stars, number of ratings, number of written comments), approved root comments only."""
    async def load():
        C = CaseComment
        rows = (await session.execute(
            select(C.case_id,
                   func.coalesce(func.avg(sql_case((C.rating > 0, C.rating))), 0),
                   func.sum(sql_case((C.rating > 0, 1), else_=0)),
                   func.sum(sql_case((C.body != "", 1), else_=0)))
            .where(C.parent_id.is_(None), C.status == "approved").group_by(C.case_id))).all()
        return {cid: (round(float(avg), 1), int(n or 0), int(w or 0)) for cid, avg, n, w in rows}
    return await _summary.get_or_load("s", load)


async def mine(session: AsyncSession, player_id: str) -> dict[str, int]:
    """case_id -> the stars this player gave (0 when none)."""
    rows = (await session.execute(select(CaseComment.case_id, CaseComment.rating).where(
        CaseComment.player_id == player_id, CaseComment.slot == "root"))).all()
    return {cid: int(r) for cid, r in rows}
