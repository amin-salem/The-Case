"""What a player's actions are worth beyond coins: one place every router reports to.

    gains = await progress.record(session, player, riddle_correct=1)

Returns a Gains with what the player earned right now, so the app can celebrate it.
(Missions, XP/ranks and achievements plug in here.)
"""
from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy.ext.asyncio import AsyncSession

from .models import Player


@dataclass
class Gains:
    xp: int = 0
    rank_up: str | None = None
    missions_done: list[str] = field(default_factory=list)
    achievements: list[dict] = field(default_factory=list)

    def out(self) -> dict:
        return {"xp": self.xp, "rank_up": self.rank_up, "missions_done": self.missions_done,
                "achievements": self.achievements}


async def record(session: AsyncSession, player: Player, **events: int) -> Gains:
    """Call before commit. events are counters like riddle_answer=1, case_solved=1."""
    return Gains()
