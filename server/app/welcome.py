"""First-days offers for a new detective (Amin, 28 Oct 2026): no dead end on the first nights, nothing given away.

A player in his first NEWBIE_DAYS days gets two ONE-TIME lower prices (he still pays coins, the sink stays):
- the first paid reopening of a case he LOST costs NEWBIE_REOPEN_COST (the normal price is twice the archive price, 200-440,
  more than the 100 start coins: a player who lost the first night had nothing left to do until the next case);
- the first archive case of difficulty 1-2 costs NEWBIE_ARCHIVE_COST.
No new column: "used" is read from the coin ledger (`reopen:` / `unlock:` rows), under the player lock at purchase time,
so a double tap cannot use an offer twice and a restart forgets nothing.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import economy as eco
from .models import CoinLog, Player, utcnow

NEWBIE_DAYS = 3
NEWBIE_REOPEN_COST = 100
NEWBIE_ARCHIVE_COST = 50
NEWBIE_ARCHIVE_MAX_DIFFICULTY = 2


@dataclass(frozen=True)
class Offers:
    reopen: bool = False
    archive: bool = False


NONE = Offers()


async def offers_for(session: AsyncSession, player: Player, now: datetime | None = None) -> Offers:
    """Which offers this player may still use. Players older than NEWBIE_DAYS cost no query."""
    now = now or utcnow()
    if player.created_at is None or player.created_at < now - timedelta(days=NEWBIE_DAYS):
        return NONE
    rows = dict((await session.execute(
        select(func.substr(CoinLog.reason, 1, 7), func.count()).where(
            CoinLog.player_id == player.id, CoinLog.reason.like("reopen:%") | CoinLog.reason.like("unlock:%"))
        .group_by(func.substr(CoinLog.reason, 1, 7)))).all())
    return Offers(reopen=not rows.get("reopen:"), archive=not rows.get("unlock:"))


def reopen_cost(base: int, offers: Offers) -> int:
    return min(base, NEWBIE_REOPEN_COST) if offers.reopen else base


def archive_cost(base: int, difficulty, offers: Offers) -> int:
    if offers.archive and eco.difficulty_level(difficulty) <= NEWBIE_ARCHIVE_MAX_DIFFICULTY:
        return min(base, NEWBIE_ARCHIVE_COST)
    return base
