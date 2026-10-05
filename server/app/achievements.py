"""Achievements: about thirty badges with coin and XP rewards, computed on the server.

Each one watches a number about the player (a lifetime counter in Player.stats, or a column like
cases_solved / best_streak) and is earned once that number reaches its target.
"""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from . import economy as eco
from .models import Player


def stat(key: str) -> Callable[[Player], int]:
    return lambda p: int((p.stats or {}).get(key, 0))


METRICS: dict[str, Callable[[Player], int]] = {
    "cases_solved": lambda p: p.cases_solved or 0,
    "best_streak": lambda p: p.best_streak or 0,
    "chests": lambda p: p.chests or 0,
    "rank": lambda p: eco.rank_of(p.xp or 0),
    "secured": lambda p: 1 if p.email else 0,
    "invites": lambda p: p.invites_rewarded or 0,
    # lifetime counters (progress.record adds every event to Player.stats)
    **{k: stat(k) for k in ("case_3stars", "case_no_hint", "first_try", "fast5", "fast2", "early_daily",
                            "riddle_correct", "riddle_fast", "riddle_perfect_day", "interrogate_all",
                            "case_unlock", "full_week", "best_chest_streak")},
}


@dataclass(frozen=True)
class Achievement:
    id: str
    title: str
    desc: str
    group: str      # cases | skill | streak | riddles | missions | account | rank (the app picks an icon)
    metric: str
    target: int
    coins: int
    xp: int = 0

    def value(self, p: Player) -> int:
        return METRICS[self.metric](p)


ALL = [
    Achievement("first_case", "اولین پرونده", "اولین پرونده‌ات را حل کن", "cases", "cases_solved", 1, 50, 20),
    Achievement("cases_10", "کارآگاه پرکار", "۱۰ پرونده حل کن", "cases", "cases_solved", 10, 100, 50),
    Achievement("cases_25", "پرونده‌خوار", "۲۵ پرونده حل کن", "cases", "cases_solved", 25, 200, 100),
    Achievement("cases_50", "بایگانی زنده", "۵۰ پرونده حل کن", "cases", "cases_solved", 50, 400, 200),
    Achievement("cases_100", "صدمین پرونده", "۱۰۰ پرونده حل کن", "cases", "cases_solved", 100, 800, 400),
    Achievement("stars_1", "بی‌نقص", "یک پرونده را با ۳ ستاره حل کن", "skill", "case_3stars", 1, 50, 20),
    Achievement("stars_10", "دقت بالا", "۱۰ پرونده را با ۳ ستاره حل کن", "skill", "case_3stars", 10, 200, 100),
    Achievement("no_hint_3", "بدون کمک", "۳ پرونده را بدون خریدن سرنخ حل کن", "skill", "case_no_hint", 3, 80, 40),
    Achievement("no_hint_10", "ذهن مستقل", "۱۰ پرونده را بدون خریدن سرنخ حل کن", "skill", "case_no_hint", 10, 250, 120),
    Achievement("first_try_5", "تیر اول", "۵ پرونده را با اولین اتهام حل کن", "skill", "first_try", 5, 150, 80),
    Achievement("fast_5", "تیزهوش", "یک پرونده را زیر ۵ دقیقه حل کن", "skill", "fast5", 1, 80, 40),
    Achievement("fast_2", "برق‌آسا", "یک پرونده را زیر ۲ دقیقه حل کن", "skill", "fast2", 1, 150, 80),
    Achievement("early_daily", "شب‌زنده‌دار", "پرونده‌ی تازه را در نیم ساعت اول حل کن", "skill", "early_daily", 1, 100, 50),
    Achievement("streak_3", "سه شب پیاپی", "۳ شب پشت سر هم پرونده‌ی روز را حل کن", "streak", "best_streak", 3, 50, 30),
    Achievement("streak_7", "یک هفته‌ی کامل", "۷ شب پشت سر هم پرونده‌ی روز را حل کن", "streak", "best_streak", 7, 150, 80),
    Achievement("streak_30", "یک ماه بی‌وقفه", "۳۰ شب پشت سر هم پرونده‌ی روز را حل کن", "streak", "best_streak", 30, 600, 300),
    Achievement("streak_100", "صد شب", "۱۰۰ شب پشت سر هم پرونده‌ی روز را حل کن", "streak", "best_streak", 100, 2000, 800),
    Achievement("riddle_1", "اولین معما", "اولین معمای سریع را درست جواب بده", "riddles", "riddle_correct", 1, 20, 10),
    Achievement("riddle_10", "معماباز", "۱۰ معمای سریع را درست جواب بده", "riddles", "riddle_correct", 10, 80, 40),
    Achievement("riddle_50", "حلّال معما", "۵۰ معمای سریع را درست جواب بده", "riddles", "riddle_correct", 50, 250, 120),
    Achievement("riddle_fast_5", "تند و دقیق", "۵ معما را زیر ۲۰ ثانیه درست جواب بده", "riddles", "riddle_fast", 5, 100, 50),
    Achievement("riddle_day_1", "روز بی‌خطا", "۳ معمای یک روز را بدون هیچ اشتباهی جواب بده", "riddles", "riddle_perfect_day", 1, 50, 30),
    Achievement("riddle_day_7", "هفت روز بی‌خطا", "۷ بار، ۳ معمای یک روز را بی‌اشتباه جواب بده", "riddles", "riddle_perfect_day", 7, 250, 120),
    Achievement("chest_1", "اولین صندوقچه", "همه‌ی مأموریت‌های یک روز را انجام بده", "missions", "chests", 1, 30, 20),
    Achievement("chest_week", "هفته‌ی مأموریت", "۷ روز پشت سر هم همه‌ی مأموریت‌ها را انجام بده", "missions", "best_chest_streak", 7, 300, 150),
    Achievement("chest_30", "مأمور ویژه", "۳۰ صندوقچه‌ی مأموریت باز کن", "missions", "chests", 30, 500, 250),
    Achievement("interrogate_10", "بازجوی خستگی‌ناپذیر", "در ۱۰ پرونده از همه‌ی مظنون‌ها بازجویی کن", "missions", "interrogate_all", 10, 100, 50),
    Achievement("archive_5", "موش بایگانی", "۵ پرونده‌ی بایگانی را باز کن", "missions", "case_unlock", 5, 150, 60),
    Achievement("full_week", "هفت روز سر زدن", "تقویم ورود را تا روز هفتم کامل کن", "account", "full_week", 1, 50, 30),
    Achievement("secured", "حساب امن", "حسابت را با ایمیل امن کن", "account", "secured", 1, 30, 20),
    Achievement("invite_1", "دعوت‌کننده", "یک دوست را به بازی دعوت کن", "account", "invites", 1, 50, 30),
    Achievement("rank_inspector", "نشان بازرسی", "به درجه‌ی «بازرس» برس", "rank", "rank", 4, 200),
    Achievement("rank_legend", "افسانه‌ی پرونده", "به درجه‌ی «افسانه» برس", "rank", "rank", 8, 1000),
]
BY_ID = {a.id: a for a in ALL}
