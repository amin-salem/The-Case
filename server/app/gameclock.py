"""THE game clock: the only place that knows when a game day, a week and a rollover start and end.

The rule (docs/operations.md, «ساعت بازی»):
- A GAME DAY starts at GAME_DAY_START (21:00 Tehran, = the moment the night's case opens) and lasts 24 hours.
  It is named by the date it starts on, which is also the `publish` date of the case released at its start.
  So 22:00 on Saturday and 02:00 on Sunday are both game day «Saturday»; 20:59 on Sunday still is, 21:00 is «Sunday».
- A WEEK starts on WEEK_START_WEEKDAY (Friday) at GAME_DAY_START and lasts exactly 7 game days (7 daily cases).
  It is named by the date of its first game day (a Friday). The case released on Friday 21:00 is the first of the NEW week.
- A week is settled (prizes) only SETTLE_MARGIN after it ended.
- Calendar days (midnight Tehran) exist only for things that are not about cases: the daily login reward, the rewarded-ad
  limit and the riddles. They come from calendar_day(), also from this module.

Everything is computed with zoneinfo (Asia/Tehran), never with a hard-coded +3:30, and stored/compared in UTC
(naive UTC datetimes in the database, see to_utc_naive). The clock is injectable: set_clock(fn) in tests.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from typing import Callable
from zoneinfo import ZoneInfo

from .config import get_settings

SETTLE_MARGIN = timedelta(minutes=10)  # prizes are paid this long after the week closed
_clock: Callable[[], datetime] | None = None


def set_clock(fn: Callable[[], datetime] | None) -> None:
    """Tests: make now() return fn(). None puts the real clock back."""
    global _clock
    _clock = fn


def tz() -> ZoneInfo:
    return ZoneInfo(get_settings().timezone)


def start_hour() -> int:
    return get_settings().new_case_hour


def week_weekday() -> int:
    return get_settings().week_start_weekday  # Monday = 0 ... Friday = 4


def now() -> datetime:
    """Now in Tehran time (aware)."""
    if _clock is not None:
        n = _clock()
        return n if n.tzinfo else n.replace(tzinfo=tz())
    return datetime.now(tz())


def _local(dt: datetime | None) -> datetime:
    dt = now() if dt is None else dt
    if dt.tzinfo is None:  # naive = UTC, like the database
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(tz())


def to_utc_naive(dt: datetime) -> datetime:
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def calendar_day(dt: datetime | None = None) -> date:
    """Midnight-to-midnight Tehran date (login reward, ads, riddles)."""
    return _local(dt).date()


def game_day(dt: datetime | None = None) -> date:
    """The game day a moment belongs to (named by the date it starts on)."""
    loc = _local(dt)
    return loc.date() if loc.hour >= start_hour() else loc.date() - timedelta(days=1)


def day_start(gd: date) -> datetime:
    """The moment game day `gd` starts (aware, Tehran)."""
    return datetime.combine(gd, time(start_hour()), tzinfo=tz())


def day_end(gd: date) -> datetime:
    return day_start(gd + timedelta(days=1))


def next_rollover(dt: datetime | None = None) -> datetime:
    """When the next game day (the next daily case) starts."""
    return day_end(game_day(dt))


def week_start(gd: date) -> date:
    """The first game day (the date label) of the week that game day `gd` belongs to."""
    return gd - timedelta(days=(gd.weekday() - week_weekday()) % 7)


def week_of(dt: datetime | None = None) -> date:
    return week_start(game_day(dt))


def week_begin(ws: date) -> datetime:
    return day_start(ws)


def week_end(ws: date) -> datetime:
    """The moment the week closes = the moment the next week's first case is released."""
    return day_start(ws + timedelta(days=7))


def settle_at(ws: date) -> datetime:
    return week_end(ws) + SETTLE_MARGIN


def next_week_start(dt: datetime | None = None) -> datetime:
    return week_end(week_of(dt))


def case_week(opens: datetime) -> date:
    """The week a case belongs to, from the moment it opens (never from when it is solved)."""
    return week_start(game_day(opens))
