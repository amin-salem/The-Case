"""Removes players completely (every row that belongs to them). Used for the throw-away «smoke-» test players
(tools/smoke_test.py): the smoke test deletes its own player at the end, and the admin purge call clears old ones."""
from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from .models import Base, Player, ReferralPayout

SMOKE_PREFIX = "smoke-"


def is_smoke(device_id: str | None) -> bool:
    return (device_id or "").startswith(SMOKE_PREFIX)


async def purge_players(session: AsyncSession, ids: list[str]) -> int:
    """Deletes the players and their rows in every table that has a player_id column. One transaction (the caller
    commits). Works on SQLite (CI, no cascade) and Postgres alike."""
    ids = list(ids)
    if not ids:
        return 0
    for table in reversed(Base.metadata.sorted_tables):
        if table.name == "players":
            continue
        col = table.c.get("player_id")
        if col is not None:
            await session.execute(delete(table).where(col.in_(ids)))
    await session.execute(delete(ReferralPayout).where(or_(
        ReferralPayout.inviter_id.in_(ids), ReferralPayout.invitee_id.in_(ids))))
    res = await session.execute(delete(Player).where(Player.id.in_(ids)))
    return int(res.rowcount or 0)


async def smoke_player_ids(session: AsyncSession, limit: int = 1000) -> list[str]:
    return list((await session.execute(select(Player.id).where(
        Player.device_id.startswith(SMOKE_PREFIX)).limit(limit))).scalars().all())
