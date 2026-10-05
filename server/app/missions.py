"""Daily missions: three a day from a pool (one about quick riddles, one about cases, one extra),
the same three for everyone. Progress comes from what players really do (see progress.record)."""
from __future__ import annotations

import random
from dataclasses import dataclass


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
    Mission("daily_case", "پرونده‌ی امروز را حل کن", "daily_solved", 1, "case"),
    Mission("case_3stars", "یک پرونده را با ۳ ستاره حل کن", "case_3stars", 1, "case"),
    Mission("case_no_hint", "یک پرونده را بدون سرنخ خریدن حل کن", "case_no_hint", 1, "case"),
    Mission("interrogate_all", "از همه‌ی مظنون‌های یک پرونده بازجویی کن", "interrogate_all", 1, "extra"),
    Mission("hint_use", "یک سرنخ بخر", "hint", 1, "extra"),
    Mission("archive_open", "یک پرونده‌ی بایگانی را باز کن", "case_unlock", 1, "extra"),
    Mission("riddle_unlock", "یک معمای قفل را باز کن", "riddle_unlock", 1, "extra"),
    Mission("case_solve2", "۲ پرونده حل کن (امروز یا بایگانی)", "case_solved", 2, "extra"),
]
BY_ID = {m.id: m for m in POOL}


def for_day(day: str) -> list[Mission]:
    rnd = random.Random(f"missions-{day}")
    return [rnd.choice([m for m in POOL if m.group == g]) for g in ("riddle", "case", "extra")]
