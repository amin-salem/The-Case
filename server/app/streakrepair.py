"""Streak repair and the live streak shown to other players (Amin, 16 Oct 2026).

The streak is stored lazily: `Player.streak` only drops to 1 when the player next solves a daily case, so a broken
streak keeps its old number until then. Two things need to know whether it is really alive:

- the repair offer: the player missed EXACTLY ONE daily case, the case after it opened less than 24 hours ago, no
  streak insurance covers the gap, and nobody has repaired this break yet. The server decides, never the app;
- the flame on the leaderboards, which must not show the number of a streak that is already gone.

Pure functions over a Player and the case list (no queries), so a profile or a board row costs nothing extra.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta

from . import content
from . import economy as eco
from .config import get_settings
from .models import Player

log = logging.getLogger("streak")

MAX_SHOWN_STREAK = 9999   # bound for anything that goes to other players


def missed_between(last_solved: str, c) -> int | None:
    """How many daily cases came between the last one solved (by publish date) and c.
    0 = c is the very next case; None = nothing solved before (or unknown)."""
    cases = content.all_cases()
    last = next((i for i, x in enumerate(cases) if x.publish.isoformat() == last_solved), None)
    if last is None:
        return None
    return cases.index(c) - last - 1


def repair_offer(p: Player, now: datetime | None = None) -> dict | None:
    """The repair this player may buy right now, or None. {key, streak, price, bridge}: `key` names the break (the
    publish date of the last daily case solved), `bridge` is the publish date of the missed case."""
    if not get_settings().streak_repair_enabled:
        return None
    streak = p.streak or 0
    last = p.last_daily_solved or ""
    if streak < eco.REPAIR_MIN_STREAK or not last or last == (p.streak_repair_mark or ""):
        return None
    if (p.streak_freezes or 0) >= 1:
        return None  # the insurance already covers a single missed case
    now = now or content.now_local()
    today = content.todays_case(now)
    if today is None or content.is_weekly(today.id) or content.is_story(today.id):
        return None
    if missed_between(last, today) != 1:
        return None
    if not timedelta(0) <= now - content.opens_at(today) < timedelta(hours=eco.REPAIR_WINDOW_HOURS):
        return None
    cases = content.all_cases()
    missed = cases[cases.index(today) - 1]
    return {"key": last, "streak": streak, "price": eco.streak_repair_cost(streak), "bridge": missed.publish.isoformat()}


class LiveStreak:
    """Is a stored streak still alive? Built once per request; `of(player)` is then a dictionary lookup."""

    def __init__(self, now: datetime | None = None):
        now = now or content.now_local()
        today = content.todays_case(now)
        self.keys: set[str] = set()
        if today is not None:
            cases = content.all_cases()
            i = cases.index(today)
            self.keys.add(today.publish.isoformat())
            if i > 0:
                self.keys.add(cases[i - 1].publish.isoformat())

    def of(self, p: Player) -> int:
        """The streak to show others: 0 once the last daily case solved is older than yesterday's. (A player holding
        insurance may still be alive; the board is conservative and shows no flame for him until he plays.)"""
        if (p.last_daily_solved or "") not in self.keys:
            return 0
        return max(0, min(int(p.streak or 0), MAX_SHOWN_STREAK))


def log_decision(decision: str, streak: int = 0, price: int = 0) -> None:
    """One structured line per repair decision; no player id, no name."""
    log.info("streak_repair decision=%s streak=%d price=%d", decision, streak, price)
