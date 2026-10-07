"""Daily missions: three a day (tonight's case, how you solve, the investigation or the weekend case),
the same three for everyone. Progress comes from what players really do (see progress.record)."""
from __future__ import annotations

import random
from dataclasses import dataclass
from datetime import date, datetime, time

from . import content


@dataclass(frozen=True)
class Mission:
    id: str
    title: str
    event: str     # the counter it watches (progress.record(..., event=n))
    target: int
    group: str     # riddle | case | extra


POOL = [
    Mission("riddle_play3", "به ۳ معمای سریع جواب بده", "riddle_answer", 3, "riddle"),
    Mission("riddle_correct2", "۲ معمای سریع را درست جواب بده", "riddle_correct", 2, "riddle"),
    Mission("riddle_correct3", "۳ معمای سریع را درست جواب بده", "riddle_correct", 3, "riddle"),
    Mission("riddle_fast", "یک معما را زیر ۲۰ ثانیه درست جواب بده", "riddle_fast", 1, "riddle"),
    # core: every day
    Mission("daily_case", "پرونده‌ی امشب رو حل کن", "daily_solved", 1, "core"),
    # skill: how you solve it
    Mission("case_3stars", "یک پرونده رو با ۳ ستاره حل کن", "case_3stars", 1, "case"),
    Mission("case_no_hint", "یک پرونده رو بدون خریدن سرنخ حل کن", "case_no_hint", 1, "case"),
    Mission("case_first_try", "یک پرونده رو بدون حتی یک اتهام اشتباه حل کن", "first_try", 1, "case"),
    # investigation: the work around it
    Mission("interrogate_all", "از همه‌ی مظنون‌های یک پرونده بازجویی کن", "interrogate_all", 1, "extra"),
    Mission("talk3", "با ۳ مظنون حرف بزن", "suspect_seen", 3, "extra"),
    Mission("case_solve2", "۲ پرونده حل کن (امشب یا بایگانی)", "case_solved", 2, "extra"),
    # Friday and Saturday, while a weekend case is open
    Mission("weekend_talk", "تو پرونده‌ی آخر هفته از ۲ مظنون بازجویی کن", "weekly_seen", 2, "weekend"),
    # only when quick riddles are on (these cost coins or need riddles)
    Mission("hint_use", "یک سرنخ بخر", "hint", 1, "extra_paid"),
    Mission("archive_open", "یک پرونده‌ی بایگانی را باز کن", "case_unlock", 1, "extra_paid"),
    Mission("riddle_unlock", "یک معمای قفل را باز کن", "riddle_unlock", 1, "extra_paid"),
]
BY_ID = {m.id: m for m in POOL}


# Quick riddles are hidden in the app for now (owner's call, 2026-10-07): no riddle missions.
RIDDLES_ON = False


def _weekend_open(day: str) -> bool:
    """Friday or Saturday with a weekend case open (at noon that day)."""
    d = date.fromisoformat(day)
    if d.weekday() not in (4, 5):
        return False
    return content.current_weekly(datetime.combine(d, time(12), tzinfo=content.now_local().tzinfo)) is not None


def for_day(day: str) -> list[Mission]:
    """Three missions: tonight's case, one about how you solve, one about the investigation
    (on weekend days: the weekend case). No mission makes you spend coins."""
    rnd = random.Random(f"missions-{day}")
    if RIDDLES_ON:
        extra = [m for m in POOL if m.group in ("extra", "extra_paid")]
        return [rnd.choice([m for m in POOL if m.group == "riddle"]),
                rnd.choice([m for m in POOL if m.group in ("core", "case")]), rnd.choice(extra)]
    skill = rnd.choice([m for m in POOL if m.group == "case"])
    third = BY_ID["weekend_talk"] if _weekend_open(day) else rnd.choice([m for m in POOL if m.group == "extra"])
    return [BY_ID["daily_case"], skill, third]
