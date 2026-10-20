"""The game's numbers (coins, prices, rewards, stars). Pure Python: easy to test and tune."""
from __future__ import annotations

from dataclasses import dataclass

START_COINS = 100                # was 150: a throwaway account should not start rich
HINT_COSTS = [30, 50, 80]        # hint 1, 2, 3 of a case
UNLOCK_COST = 150                # open an old case from the archive
MAX_ATTEMPTS = 3                 # wrong accusations allowed before the case is lost
SOLVE_REWARD = {3: 30, 2: 20, 1: 10}
# Level 3 retains the old baseline; bonuses are added by the caller exactly once.
ARCHIVE_PRICES = (100, 120, 150, 180, 220)
WEEKEND_ARCHIVE_PRICES = (170, 200, 250, 300, 370)
DIFFICULTY_REWARDS = {3: (20, 25, 30, 36, 45), 2: (12, 16, 20, 24, 30), 1: (6, 8, 10, 12, 15)}
LIVE_WEEKEND_REWARDS = {3: (200, 250, 300, 360, 450), 2: (120, 160, 200, 240, 300), 1: (72, 96, 120, 144, 180)}


# A case the player LOST stays closed. Playing it again is a paid second chance, always dearer than the normal
# archive price of the same difficulty (Amin, 20 Oct 2026).
LOST_REOPEN_FACTOR = 2


def difficulty_level(value) -> int:
    return value if type(value) is int and 1 <= value <= 5 else 3


def archive_unlock_cost(difficulty, *, weekend: bool = False) -> int:
    return (WEEKEND_ARCHIVE_PRICES if weekend else ARCHIVE_PRICES)[difficulty_level(difficulty) - 1]


def reopen_lost_cost(difficulty, *, weekend: bool = False) -> int:
    return archive_unlock_cost(difficulty, weekend=weekend) * LOST_REOPEN_FACTOR


def solve_reward(difficulty, stars: int, *, live_weekend: bool = False) -> int:
    if stars not in (1, 2, 3):
        raise ValueError("stars must be 1..3")
    return (LIVE_WEEKEND_REWARDS if live_weekend else DIFFICULTY_REWARDS)[stars][difficulty_level(difficulty) - 1]


def difficulty_policy() -> dict:
    return {"version": 1, "fallback_difficulty": 3, "archive_prices": list(ARCHIVE_PRICES),
            "weekend_archive_prices": list(WEEKEND_ARCHIVE_PRICES),
            "lost_reopen_factor": LOST_REOPEN_FACTOR,
            "base_rewards": {n: [solve_reward(n, s) for s in (1, 2, 3)] for n in range(1, 6)},
            "live_weekend_base_rewards": {n: [solve_reward(n, s, live_weekend=True) for s in (1, 2, 3)] for n in range(1, 6)}}
DAILY_BONUS = 15                 # extra for solving the case on its own day
STREAK_BONUS_EVERY = 7           # every 7 days in a row ...
STREAK_BONUS = 60                # ... this many coins
LOGIN_CALENDAR = [10, 10, 15, 15, 20, 25]  # daily login reward, days 1-6 in a row
LOGIN_ENVELOPE = [40, 50, 60, 80]      # day 7: a sealed envelope with one of these
LOGIN_REWARD = LOGIN_CALENDAR[0]           # first day (and after a missed day)
FREEZE_COST = 150                # "streak insurance": saves the streak for one missed case
MAX_FREEZES = 2                  # how many a player can hold
STREAK_BADGES = (7, 30, 100)     # badges for daily cases solved in a row
AD_REWARD = 25
AD_PER_DAY = 5
SECURE_REWARD = 100              # first time an email is added
INVITE_NEW_PLAYER = 100
INVITE_INVITER = 150
MAX_REWARDED_INVITES = 20        # lifetime cap of paid invites per inviter
INVITE_MIN_DAYS = 3              # the inviter is paid after the invited player solved cases on this many different days
INVITE_PAID_PER_WEEK = 5         # paid invites per inviter per week (Saturday to Friday); also 1 paid invite per device

# anti-cheat (docs/operations.md): proof of investigation and delayed answers
MIN_ACTIVE_SECONDS = 90          # 3 stars and a leaderboard place need this much active time on a difficulty-3 case ...
# ... scaled by the case's difficulty (1-5): an easy case asks for less, a hard one for more (60/75/90/110/130 s)
ACTIVE_TIME_FACTOR = {1: 0.67, 2: 0.83, 3: 1.0, 4: 1.22, 5: 1.44}
MIN_SUSPECTS_SEEN = 2            # ... and at least this many suspects interrogated
STORY_ANSWER_DELAY_HOURS = 24    # a failed story chapter shows its answer this long after the failure
HIDE_NEW_ACCOUNT_HOURS = 48      # accounts younger than this and without email are hidden from the leaderboards


def min_active_seconds(difficulty: int | None) -> int:
    """Active time a case of this difficulty needs for 3 stars and a leaderboard place (an unknown difficulty counts as 3)."""
    return round(MIN_ACTIVE_SECONDS * ACTIVE_TIME_FACTOR.get(int(difficulty or 3), 1.0))


def login_reward(day: int, pick=None) -> int:
    """Coins for day 1..7 of the login calendar. Day 7 opens a random envelope."""
    import random

    if 1 <= day <= len(LOGIN_CALENDAR):
        return LOGIN_CALENDAR[day - 1]
    return (pick or random.choice)(LOGIN_ENVELOPE)


FREE_PROOF_MISSES = 2            # right suspect, wrong proof: costs a star, not a try (this many times)


def stars_for(hints: int, wrong: int, proof_misses: int = 0) -> int:
    penalty = wrong + proof_misses + (1 if hints >= 2 else 0) + (1 if hints >= 3 else 0)
    return max(1, 3 - penalty)


@dataclass(frozen=True)
class Product:
    id: str
    kind: str  # consumable | permanent | subscription
    coins: int = 0
    no_ads: bool = False
    vip_days: int = 0


PRODUCTS = {
    p.id: p
    for p in [
        Product("coins_small", "consumable", coins=400),
        Product("coins_medium", "consumable", coins=1300),
        Product("coins_large", "consumable", coins=3600),
        Product("starter_pack", "permanent", coins=1000, no_ads=True),
        Product("remove_ads", "permanent", no_ads=True),
        Product("vip_monthly", "consumable", vip_days=30),
    ]
}

GRANT_TYPES = {"coins", "no_ads", "vip_until"}


def check_grants(grants: list) -> list[dict]:
    """Validate grants written by the admin. Raises ValueError if wrong."""
    out = []
    for g in grants:
        if not isinstance(g, dict) or g.get("type") not in GRANT_TYPES:
            raise ValueError(f"bad grant: {g!r}")
        if g["type"] == "coins":
            n = int(g.get("amount", 0))
            if not 0 < n <= 1_000_000:
                raise ValueError(f"bad amount in {g!r}")
            out.append({"type": "coins", "amount": n})
        elif g["type"] == "vip_until":
            out.append({"type": "vip_until", "ts": int(g["ts"])})
        else:
            out.append({"type": "no_ads"})
    return out


# quick riddles («معمای سریع»): a few one-minute mini mysteries every day, the same for everyone
RIDDLES_PER_DAY = 5
RIDDLE_FREE = 3                  # the first ones of the day are free ...
RIDDLE_UNLOCK_COST = 20          # ... the rest are opened with coins
RIDDLE_REWARD = 10               # coins for a right answer
RIDDLE_SECONDS = 60              # the timer in the app (an answer after it runs out counts as wrong)


# daily missions: three a day, a chest when all three are done
CHEST_COINS = 30
CHEST_BONUS_EVERY = 7            # every 7 days in a row with all missions done ...
CHEST_BONUS = 60                 # ... this many extra coins
RIDDLE_FAST_SECONDS = 20
TICK_MAX = 120
WEEKLY_REWARD = {3: 300, 2: 200, 1: 120}   # the weekend's big case pays more ...
WEEKLY_EARLY_BONUS = 80            # a weekend case solved (both parts right) before its last chapter opens (was 50; 18 Oct 2026: a real reason to play night 1)
WEEKEND_LIAR_REWARD = 10           # format 3, night 1: «کی دروغ می‌گه؟» answered right (one try). Small on purpose: coins are sold
WEEKEND_SHOWS_PER_CHAPTER = 3      # «show an evidence card to a suspect»: this many per opened chapter
WEEKEND_ARCHIVE_COST = 250         # an expired weekend case in the archive (normal archive case: UNLOCK_COST)
WEEKLY_XP = {3: 150, 2: 100, 1: 60}       # ... and gives more XP                   # one time report from the app counts at most this many seconds         # "fast" riddle answer (missions, achievements)


# detective rank: XP from everything a player does
XP_CASE = {3: 60, 2: 40, 1: 25}  # a solved case, by stars
XP_DAILY_BONUS = 15              # solved on its own day
XP_CASE_FAILED = 5               # lost, but learned something
XP_RIDDLE_RIGHT = 10
XP_RIDDLE_WRONG = 2
XP_CHEST = 40                    # all daily missions done
RANKS = [                        # (XP needed, title)
    (0, "کارآگاه تازه‌کار"),
    (200, "دستیار کارآگاه"),
    (600, "کارآگاه"),
    (1300, "کارآگاه ارشد"),
    (2500, "بازرس"),
    (4200, "سربازرس"),
    (6500, "کارآگاه نخبه"),
    (10000, "استاد معما"),
    (15000, "افسانه"),
]


def rank_of(xp: int) -> int:
    """Index into RANKS for this much XP."""
    return max(i for i, (need, _) in enumerate(RANKS) if xp >= need)


# story mode: chapters 1-3 of a season are free; later ones need a warrant «حکم بازرسی», 12 hours of waiting,
# or coins to skip the wait (the price falls as the wait runs down)
STORY_FREE_CHAPTERS = 3
STORY_WAIT_HOURS = 12
STORY_SKIP_COST = 120
STORY_SKIP_MIN = 10
# Free warrants are scarce on purpose (Amin, 17 Oct 2026: players had so many that nobody spent coins on the story).
# Supply for a normal player: about one per two weeks. Everything else is bought: skip the wait with coins.
STREAK_WARRANTS = (14, 30)         # streak lengths that give a warrant (was 3, 7, 14, 30)
WEEKEND_WARRANT_EVERY = 2          # every 2nd live weekend case pays a warrant, the 1st, 3rd, 5th... (was every one)
# cut on 17 Oct 2026: tonight's case (was 1 a day) and "all daily missions done" (was 1 a day) give none any more


def warrants_for_solve(*, first_ever: bool, streak_up: bool, streak: int, live: bool, live_solved_before: int) -> int:
    """Free warrants for ONE first-time solve (the caller runs this once per solved case, inside the solve
    transaction, so a repeated request cannot pay twice):
    - the player's very first solved case: 1 (onboarding, so the feature is learned)
    - a streak milestone (STREAK_WARRANTS): 1
    - a live weekend case: 1 for the 1st, 3rd, 5th... one the player ever solves live"""
    n = int(first_ever)
    n += int(streak_up and streak in STREAK_WARRANTS)
    n += int(live and live_solved_before % WEEKEND_WARRANT_EVERY == 0)
    return n


def story_skip_cost(remaining_seconds: float) -> int:
    """Coins to skip what is left of the wait: full price at 12 h, down to STORY_SKIP_MIN near the end."""
    if remaining_seconds <= 0:
        return 0
    frac = min(1.0, remaining_seconds / (STORY_WAIT_HOURS * 3600))
    return max(STORY_SKIP_MIN, round(STORY_SKIP_COST * frac))


# profile avatars and frames (docs/avatars-plan.md): the shop sells each one once, forever
AVATAR_PRICE = {"ex_alchemist": 600, "ex_journalist": 600, "ex_qajar": 800, "ex_cat": 800, "ex_chef": 900,
                "ex_shadow": 1800, "ex_diva": 2200, "ex_gold": 2500}
FRAME_PRICE = {"frame_fingerprint": 300, "frame_blinds": 400, "frame_cuffs": 600, "frame_stamp": 600,
               "frame_neon": 900, "frame_royal": 1500}

