"""Streak repair and the live streak shown to other players (Amin, 16 Oct 2026).

Streak insurance like Duolingo (Amin, 30 Oct 2026): the streak and the insurance are SETTLED against the calendar,
not at the next solve. `effective_streak(player, now)` is the one pure function that says what a player's streak and
insurance are RIGHT NOW: the night a daily case is missed, one insurance is spent (and the night counts as one of the
streak's nights); without enough insurance the streak shows 0 at once. Everything that shows a streak uses it. Nothing
is written on a plain GET (two workers would race): the stored fields are settled by `settle()` inside the write paths
that already hold the player lock (solve, buy insurance, repair). The repair offer still reads the stored (old) streak.

Older note: the stored `Player.streak` used to drop to 1 only when the player next solved. Things that need to know
whether it is really alive:

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


def _calendar(now: datetime | None):
    """(daily cases, index of the publish date, index of today's case or None)."""
    cases = content.all_cases()
    today = content.todays_case(now or content.now_local())
    return cases, ({c.publish.isoformat(): i for i, c in enumerate(cases)}), (cases.index(today) if today else None)


def _effective(p: Player, cal) -> tuple[int, int, int, bool, int | None]:
    """(streak, freezes, covered, broken, missed). `missed` = daily cases strictly between the last one solved and
    today's case (today's own unsolved case is NOT missed); None when it cannot be told."""
    cases, index, today_i = cal
    streak, freezes = int(p.streak or 0), int(p.streak_freezes or 0)
    last = p.last_daily_solved or ""
    if streak <= 0 or not last or today_i is None or last not in index:
        return streak, freezes, 0, False, None
    missed = today_i - index[last] - 1
    if missed <= 0:
        return streak, freezes, 0, False, missed
    # a break already recorded by a write path stays a break (insurance bought AFTER the miss never covers it)
    if (p.stats or {}).get("streak_broken") == last:
        return 0, freezes, 0, True, missed
    if missed <= freezes:
        return streak + missed, freezes - missed, missed, False, missed
    return 0, freezes, 0, True, missed


def effective_streak(p: Player, now: datetime | None = None) -> tuple[int, int, int, bool]:
    """What the streak and the insurance of this player are right now: (streak, freezes, covered, broken).
    Pure: no query, no write. All-or-nothing: the missed nights are covered only when the player holds at least as
    many insurances as missed cases (and has a streak); otherwise the streak is broken (shows 0) and the insurances
    stay untouched. `covered` = nights covered by insurance (they count as nights of the streak)."""
    s, f, covered, broken, _ = _effective(p, _calendar(now))
    return s, f, covered, broken


def shown_streak(p: Player, now: datetime | None = None) -> int:
    return effective_streak(p, now)[0]


def shown_freezes(p: Player, now: datetime | None = None) -> int:
    return effective_streak(p, now)[1]


def settle(p: Player, now: datetime | None = None) -> dict:
    """PERSIST effective_streak() into the stored fields. Call only under the player lock, inside a write path, before
    the action. Idempotent: after it the player has no missed case left (covered) or carries the broken marker.
    Returns {covered, broken, base}: `base` is the streak value up to which streak rewards were already evaluated (a
    reward fires when the streak CROSSES a threshold above it, so a jump over 7 pays once and never twice)."""
    cal = _calendar(now)
    cases, index, today_i = cal
    pre = int(p.streak or 0)
    s, f, covered, broken, missed = _effective(p, cal)
    stats = p.stats or {}
    paid = stats.get("streak_paid")
    base = paid if isinstance(paid, int) and 0 <= paid <= pre else pre
    if covered:
        p.streak, p.streak_freezes = s, f
        p.best_streak = max(p.best_streak or 0, s)
        p.last_daily_solved = cases[today_i - 1].publish.isoformat()  # the case before today's: nothing missed any more
        if paid != base:
            p.stats = {**(p.stats or {}), "streak_paid": base}  # a later solve still pays what these nights crossed
        log.info("streak_insurance decision=spent nights=%d left=%d streak=%d", covered, f, s)
    elif broken:
        last = p.last_daily_solved or ""
        if stats.get("streak_broken") != last:
            p.stats = {**stats, "streak_broken": last}  # the stored streak stays: the repair offer still knows it
            log.info("streak_insurance decision=broken missed=%s held=%d streak=%d", missed, f, pre)
        base = 0
    return {"covered": covered, "broken": broken, "base": base}


def crossed(base: int, streak: int, ladder) -> int | None:
    """The highest step of `ladder` crossed when a streak goes from `base` to `streak` (None if none)."""
    hit = [m for m in ladder if base < m <= streak]
    return max(hit) if hit else None


def repair_offer(p: Player, now: datetime | None = None) -> dict | None:
    """The repair this player may buy right now, or None. {key, streak, price, bridge}: `key` names the break (the
    publish date of the last daily case solved), `bridge` is the publish date of the missed case."""
    if not get_settings().streak_repair_enabled:
        return None
    streak = p.streak or 0
    last = p.last_daily_solved or ""
    if streak < eco.REPAIR_MIN_STREAK or not last or last == (p.streak_repair_mark or ""):
        return None
    now = now or content.now_local()
    if _effective(p, _calendar(now))[2]:
        return None  # the insurance covers the missed case
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
    """The streak to show others, settled against the calendar. Built once per request; `of(player)` is then cheap."""

    def __init__(self, now: datetime | None = None):
        self.cal = _calendar(now)

    def of(self, p: Player) -> int:
        """0 once a missed case is not covered by insurance (a covered night counts as a night of the streak)."""
        if self.cal[2] is None or (p.last_daily_solved or "") not in self.cal[1]:
            return 0
        s = _effective(p, self.cal)[0]
        return max(0, min(s, MAX_SHOWN_STREAK))


def log_decision(decision: str, streak: int = 0, price: int = 0) -> None:
    """One structured line per repair decision; no player id, no name."""
    log.info("streak_repair decision=%s streak=%d price=%d", decision, streak, price)
