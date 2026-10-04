"""The game's numbers (coins, prices, rewards, stars). Pure Python: easy to test and tune."""
from __future__ import annotations

from dataclasses import dataclass

START_COINS = 150
HINT_COSTS = [30, 50, 80]        # hint 1, 2, 3 of a case
UNLOCK_COST = 120                # open an old case from the archive
MAX_ATTEMPTS = 3                 # wrong accusations allowed before the case is lost
SOLVE_REWARD = {3: 60, 2: 40, 1: 20}
DAILY_BONUS = 30                 # extra for solving the case on its own day
STREAK_BONUS_EVERY = 7           # every 7 days in a row ...
STREAK_BONUS = 150               # ... this many coins
LOGIN_REWARD = 20                # once a day
AD_REWARD = 25
AD_PER_DAY = 5
SECURE_REWARD = 200              # first time an email is added
INVITE_NEW_PLAYER = 150
INVITE_INVITER = 300
MAX_REWARDED_INVITES = 20


def stars_for(hints: int, wrong: int) -> int:
    penalty = wrong + (1 if hints >= 2 else 0) + (1 if hints >= 3 else 0)
    return max(1, 3 - penalty)


@dataclass(frozen=True)
class Product:
    id: str
    kind: str  # consumable | permanent | subscription
    coins: int = 0
    no_ads: bool = False


PRODUCTS = {
    p.id: p
    for p in [
        Product("coins_small", "consumable", coins=400),
        Product("coins_medium", "consumable", coins=1300),
        Product("coins_large", "consumable", coins=3600),
        Product("starter_pack", "permanent", coins=1000, no_ads=True),
        Product("remove_ads", "permanent", no_ads=True),
        Product("vip_monthly", "subscription"),
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
