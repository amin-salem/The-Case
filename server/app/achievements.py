"""Achievements: about ninety tiers in chains (cases, stars, streaks ...), computed on the server.

A CHAIN watches one number about the player (a lifetime counter in Player.stats, or a column like cases_solved /
best_streak); each TIER of the chain is earned once that number reaches its target, and pays its coins and XP at that
moment (no claim button: the payout is automatic, once, the unique row in PlayerAchievement guards it).
Early tiers pay a few coins; later ones pay XP only (and frames/tools), so coins stay worth buying (Amin, Oct 2026).
Tier ids that already existed keep their id, title and reward: nothing a player earned changes.
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
    "secured": lambda p: 1 if (p.email or p.phone_hash) else 0,
    "invites": lambda p: p.invites_rewarded or 0,
    "weekly_solved": lambda p: int((p.stats or {}).get("weekly_solved", 0)),
    "weekly_top3": lambda p: int((p.stats or {}).get("weekly_top3", 0)),
    "album_groups": lambda p: int((p.stats or {}).get("album_groups", 0)),
    # lifetime counters (progress.record adds every event to Player.stats)
    **{k: stat(k) for k in ("case_3stars", "case_no_hint", "first_try", "fast5", "fast2", "early_daily",
                            "riddle_correct", "riddle_fast", "riddle_perfect_day", "interrogate_all",
                            "case_unlock", "full_week", "best_chest_streak", "weekend_night1")},
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
    chain: str = ""        # the chain this tier belongs to ("" for none)
    tier: int = 0          # 1-based position in the chain

    def value(self, p: Player) -> int:
        return METRICS[self.metric](p)

_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def fa(n: int) -> str:
    return str(n).translate(_DIGITS)


@dataclass(frozen=True)
class Chain:
    id: str
    title: str          # shown on the chain card
    unit: str           # what is counted, for the "12 / 25 <unit>" line
    group: str          # the filter chip: cases | skill | streak | riddles | missions | account | rank
    metric: str
    desc: str           # {n} becomes the Persian number
    tiers: tuple        # (target, id, title, coins, xp [, own desc])


CHAINS: list[Chain] = [
    Chain("cases", "پرونده‌خوان", "پرونده‌ی حل‌شده", "cases", "cases_solved", "{n} پرونده حل کن", (
        (1, "first_case", "اولین پرونده", 20, 20, "اولین پرونده‌ات را حل کن"), (5, "cases_5", "کارآموز", 10, 20),
        (10, "cases_10", "کارآگاه پرکار", 40, 50), (25, "cases_25", "پرونده‌خوار", 80, 100),
        (50, "cases_50", "بایگانی زنده", 160, 200), (100, "cases_100", "صدمین پرونده", 300, 400),
        (200, "cases_200", "دویست پرونده", 0, 600), (300, "cases_300", "استاد بایگانی", 0, 900))),
    Chain("stars", "دقت بالا", "پرونده‌ی سه‌پلاکی", "skill", "case_3stars", "{n} پرونده را با ۳ پلاک حل کن", (
        (1, "stars_1", "بی‌نقص", 20, 20, "یک پرونده را با ۳ پلاک حل کن"), (5, "stars_5", "نشانه‌گیر", 10, 40),
        (10, "stars_10", "دقت بالا", 80, 100), (25, "stars_25", "سه‌پلاکِ واقعی", 0, 200),
        (50, "stars_50", "تیرانداز", 0, 350), (100, "stars_100", "بی‌خطا", 0, 600))),
    Chain("hint", "ذهن مستقل", "پرونده بدون سرنخ خریده‌شده", "skill", "case_no_hint",
          "{n} پرونده را بدون خریدن سرنخ حل کن", (
              (3, "no_hint_3", "بدون کمک", 30, 40), (10, "no_hint_10", "ذهن مستقل", 100, 120),
              (25, "no_hint_25", "چشم‌تیز", 0, 250), (50, "no_hint_50", "بی‌نیاز از سرنخ", 0, 500))),
    Chain("first", "تیر اول", "پرونده با اولین اتهام", "skill", "first_try", "{n} پرونده را با اولین اتهام حل کن", (
        (5, "first_try_5", "تیر اول", 60, 80), (15, "first_try_15", "نشانه‌گیر دقیق", 0, 180),
        (40, "first_try_40", "خطاناپذیر", 0, 450))),
    Chain("fast", "تیزهوش", "پرونده زیر ۵ دقیقه", "skill", "fast5", "{n} پرونده را زیر ۵ دقیقه حل کن", (
        (1, "fast_5", "تیزهوش", 30, 40, "یک پرونده را زیر ۵ دقیقه حل کن"), (5, "fast5_5", "سریع‌السیر", 0, 120),
        (15, "fast5_15", "رکوردشکن", 0, 300))),
    Chain("fast2", "برق‌آسا", "پرونده زیر ۲ دقیقه", "skill", "fast2", "{n} پرونده را زیر ۲ دقیقه حل کن", (
        (1, "fast_2", "برق‌آسا", 60, 80, "یک پرونده را زیر ۲ دقیقه حل کن"), (5, "fast2_5", "صاعقه", 0, 200),
        (15, "fast2_15", "سرعت نور", 0, 400))),
    Chain("early", "شب‌زنده‌دار", "پرونده‌ی تازه در نیم ساعت اول", "skill", "early_daily",
          "{n} بار پرونده‌ی تازه را در نیم ساعت اول حل کن", (
              (1, "early_daily", "شب‌زنده‌دار", 40, 50, "پرونده‌ی تازه را در نیم ساعت اول حل کن"),
              (5, "early_5", "سحرخیز", 0, 120), (20, "early_20", "همیشه اول", 0, 300))),
    Chain("wknight", "شب اول", "پرونده‌ی آخر هفته در شب اول", "skill", "weekend_night1",
          "{n} پرونده‌ی آخر هفته را همان شب اول حل کن", (
              (1, "weekend_night1", "پلاک شب اول", 25, 40,
               "پرونده‌ی آخر هفته را همون شب اول، قبل از باز شدن فصل دوم، کامل حل کن"),
              (5, "wknight_5", "شب اولی", 0, 150), (15, "wknight_15", "همیشه شب اول", 0, 350))),
    Chain("weekend", "آخر هفته‌ها", "پرونده‌ی آخر هفته", "cases", "weekly_solved", "{n} پرونده‌ی آخر هفته را حل کن", (
        (1, "wk_1", "اولین آخر هفته", 10, 20), (3, "wk_3", "استاد آخر هفته", 0, 100),
        (10, "wk_10", "ده آخر هفته", 0, 250), (25, "wk_25", "حاکم آخر هفته‌ها", 0, 500))),
    Chain("top3", "روی سکو", "هفته در ۳ نفر اول", "skill", "weekly_top3", "{n} بار جزو ۳ کارآگاه اول هفته شو", (
        (1, "top3_1", "روی سکو", 0, 150), (3, "top3_3", "سه بار روی سکو", 0, 350),
        (10, "top3_10", "قهرمان همیشگی", 0, 800))),
    Chain("album", "آلبوم‌دار", "گروه کامل‌شده در آلبوم", "cases", "album_groups",
          "{n} گروه از آلبوم مجرم‌ها را کامل کن", (
              (1, "album_1", "اولین گروه", 0, 60, "یک گروه از آلبوم مجرم‌ها را کامل کن"), (3, "album_3", "سه گروه", 0, 150),
              (4, "album_4", "چهار گروه", 0, 200), (5, "album_5", "پنج گروه", 0, 300),
              (7, "album_7", "آلبوم کامل", 0, 800))),
    Chain("streak", "زنجیره‌ی شب‌ها", "شب پیاپی", "streak", "best_streak",
          "{n} شب پشت سر هم پرونده‌ی روز را حل کن", (
              (3, "streak_3", "سه شب پیاپی", 20, 30), (7, "streak_7", "یک هفته‌ی کامل", 60, 80),
              (14, "streak_14", "دو هفته‌ی بی‌وقفه", 0, 150), (30, "streak_30", "یک ماه بی‌وقفه", 250, 300),
              (60, "streak_60", "دو ماه بی‌وقفه", 0, 120,
               "۶۰ شب پشت سر هم پرونده‌ی روز را حل کن (جایزه: قاب «شعله»)"),
              (100, "streak_100", "صد شب", 800, 800),
              (200, "streak_200", "دویست شب", 0, 400,
               "۲۰۰ شب پشت سر هم پرونده‌ی روز را حل کن (جایزه: قاب «آتشفشان»)"),
              (365, "streak_365", "یک سال کامل", 0, 800,
               "۳۶۵ شب پشت سر هم پرونده‌ی روز را حل کن (جایزه: قاب «شعله‌ی جاودان»)"))),
    Chain("riddle", "معماباز", "معمای درست", "riddles", "riddle_correct", "{n} معمای سریع را درست جواب بده", (
        (1, "riddle_1", "اولین معما", 10, 10, "اولین معمای سریع را درست جواب بده"), (10, "riddle_10", "معماباز", 30, 40),
        (25, "riddle_25", "ذهن تیز", 0, 80), (50, "riddle_50", "حلّال معما", 100, 120),
        (100, "riddle_100", "گنجینه‌ی معما", 0, 250), (250, "riddle_250", "افسانه‌ی معما", 0, 500))),
    Chain("rfast", "تند و دقیق", "معمای زیر ۲۰ ثانیه", "riddles", "riddle_fast", "{n} معما را زیر ۲۰ ثانیه درست جواب بده", (
        (5, "riddle_fast_5", "تند و دقیق", 40, 50), (25, "riddle_fast_25", "برق معما", 0, 150),
        (100, "riddle_fast_100", "بی‌درنگ", 0, 400))),
    Chain("rday", "روز بی‌خطا", "روز بدون اشتباه", "riddles", "riddle_perfect_day",
          "{n} بار ۳ معمای یک روز را بی‌اشتباه جواب بده", (
              (1, "riddle_day_1", "روز بی‌خطا", 20, 30, "۳ معمای یک روز را بدون هیچ اشتباهی جواب بده"),
              (7, "riddle_day_7", "هفت روز بی‌خطا", 100, 120), (30, "riddle_day_30", "سی روز بی‌خطا", 0, 400))),
    Chain("chest", "مأمور ویژه", "صندوقچه‌ی مأموریت", "missions", "chests", "{n} صندوقچه‌ی مأموریت باز کن", (
        (1, "chest_1", "اولین صندوقچه", 10, 20, "همه‌ی مأموریت‌های یک روز را انجام بده"),
        (10, "chest_10", "مأمور فعال", 0, 60), (30, "chest_30", "مأمور ویژه", 200, 250),
        (60, "chest_60", "مأمور ارشد", 0, 300), (100, "chest_100", "مأمور صدگانه", 0, 500))),
    Chain("cstreak", "هفته‌ی مأموریت", "روز پیاپی مأموریت کامل", "missions", "best_chest_streak",
          "{n} روز پشت سر هم همه‌ی مأموریت‌ها را انجام بده", (
              (7, "chest_week", "هفته‌ی مأموریت", 120, 150), (14, "chest_streak_14", "دو هفته‌ی مأموریت", 0, 250),
              (30, "chest_streak_30", "ماه مأموریت", 0, 500))),
    Chain("inter", "بازجو", "پرونده با بازجویی از همه", "missions", "interrogate_all",
          "در {n} پرونده از همه‌ی مظنون‌ها بازجویی کن", (
              (10, "interrogate_10", "بازجوی خستگی‌ناپذیر", 40, 50), (25, "interrogate_25", "بازجوی کهنه‌کار", 0, 120),
              (50, "interrogate_50", "بازجوی بی‌رحم", 0, 300))),
    Chain("arch", "موش بایگانی", "پرونده‌ی بایگانی", "missions", "case_unlock", "{n} پرونده‌ی بایگانی را باز کن", (
        (5, "archive_5", "موش بایگانی", 60, 60), (15, "archive_15", "گنج‌یاب", 0, 150),
        (30, "archive_30", "بایگانی‌دار", 0, 300))),
    Chain("invite", "دعوت‌کننده", "دوست دعوت‌شده", "account", "invites", "{n} دوست را به بازی دعوت کن", (
        (1, "invite_1", "دعوت‌کننده", 20, 30, "یک دوست را به بازی دعوت کن"), (3, "invite_3", "سه دوست", 0, 100),
        (10, "invite_10", "سفیر پرونده", 0, 300))),
    Chain("login", "هفت روز سر زدن", "تقویم ورود کامل", "account", "full_week", "تقویم ورود را تا روز هفتم کامل کن", (
        (1, "full_week", "هفت روز سر زدن", 20, 30),)),
    Chain("secure", "حساب امن", "حساب امن‌شده", "account", "secured", "حسابت را با شماره‌ی موبایل امن کن", (
        (1, "secured", "حساب امن", 10, 20),)),
    # rank badges: the target is the index into economy.RANKS (looked up by title, so adding ranks never shifts them)
    Chain("rank", "درجه‌ها", "درجه", "rank", "rank", "به درجه‌ی «{t}» برس", (
        ("کارآگاه", "rank_detective", "نشان کارآگاهی", 20, 0), ("بازرس", "rank_inspector", "نشان بازرسی", 80, 0),
        ("کارآگاه نخبه", "rank_elite", "نشان نخبگان", 120, 0), ("استاد معما", "rank_master", "نشان استاد", 200, 0),
        ("افسانه", "rank_legend", "افسانه‌ی پرونده", 400, 0), ("اسطوره‌ی کارآگاهی", "rank_myth", "اسطوره", 600, 0))),
]


def _rank_index(title: str) -> int:
    return next(i for i, (_, t) in enumerate(eco.RANKS) if t == title)


def _build() -> list[Achievement]:
    out: list[Achievement] = []
    for ch in CHAINS:
        for n, row in enumerate(ch.tiers, 1):
            target, id_, title, coins, xp = row[:5]
            if ch.metric == "rank":
                desc = ch.desc.format(t=target)
                target = _rank_index(target)
            else:
                desc = row[5] if len(row) > 5 else ch.desc.format(n=fa(target))
            out.append(Achievement(id_, title, desc, ch.group, ch.metric, target, coins, xp, ch.id, n))
    return out


ALL = _build()
BY_ID = {a.id: a for a in ALL}
CHAIN_BY_ID = {c.id: c for c in CHAINS}
