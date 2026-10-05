"""What a player's actions are worth beyond coins: one place every router reports to.

    gains = await progress.record(session, player, riddle_correct=1)

Counters go into today's MissionDay (daily missions watch them). Returns a Gains with what the
player earned right now, so the app can celebrate it. Call before commit.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.ext.asyncio import AsyncSession

from . import content, missions
from . import economy as eco
from .models import MissionDay, Player


@dataclass
class Gains:
    xp: int = 0
    rank_up: str | None = None
    missions_done: list[str] = field(default_factory=list)
    achievements: list[dict] = field(default_factory=list)

    def out(self) -> dict:
        return {"xp": self.xp, "rank_up": self.rank_up, "missions_done": self.missions_done,
                "achievements": self.achievements}


def add_xp(player: Player, xp: int, gains: Gains) -> None:
    if xp <= 0:
        return
    before = eco.rank_of(player.xp or 0)
    player.xp = (player.xp or 0) + xp
    gains.xp += xp
    after = eco.rank_of(player.xp)
    if after > before:
        gains.rank_up = eco.RANKS[after][1]


async def mission_day(session: AsyncSession, player: Player, day: str | None = None, create: bool = True) -> MissionDay | None:
    day = day or content.today_str()
    q = select(MissionDay).where(MissionDay.player_id == player.id, MissionDay.day == day)
    md = await session.scalar(q)
    if md is None and create:
        # two requests at once may both create it: insert-if-missing, then read it back
        dialect = session.bind.dialect.name if session.bind is not None else "sqlite"
        insert = pg_insert if dialect == "postgresql" else sqlite_insert
        await session.execute(insert(MissionDay).values(player_id=player.id, day=day, counts={}, claimed=False)
                              .on_conflict_do_nothing(index_elements=["player_id", "day"]))
        md = await session.scalar(q)
    return md


async def record(session: AsyncSession, player: Player, xp: int = 0, **events: int) -> Gains:
    """xp: experience earned by this action (ranks). events: counters for missions."""
    gains = Gains()
    add_xp(player, xp, gains)
    events = {k: v for k, v in events.items() if v}
    if not events:
        return gains
    md = await mission_day(session, player)
    before = dict(md.counts or {})
    after = dict(before)
    for k, v in events.items():
        after[k] = after.get(k, 0) + v
    md.counts = after  # a new dict, so the change is saved
    for m in missions.for_day(md.day):
        if before.get(m.event, 0) < m.target <= after.get(m.event, 0):
            gains.missions_done.append(m.title)
    return gains
