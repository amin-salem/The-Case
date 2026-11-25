"""«کی کجا؟» — the small deduction game (Amin, 25 Nov 2026). Rules live here; the page that plays it is shipped with the app
(app/assets/kikoja/index.html) and never knows an answer: the pool of verified puzzles stays on the server and everything
that earns something (coins, stars, the accusation) is decided here, once, under the player's row lock.

A puzzle (content/kikoja/puzzles.json, made and verified by tools/kikoja/generate.js) has a public part (house, statements,
locks, cast) and `answer` (thief, the one false statement, real paths, every accepted proof, hints). The answer reaches a
phone only after the player solved the puzzle."""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from datetime import date, datetime, timedelta

from . import gameclock

POOL = Path(__file__).resolve().parent / "content" / "kikoja" / "puzzles.json"
AUDIENCES = ("off", "testers", "all")
DEFAULT_CONFIG = {"audience": "off"}
LEVELS = ("easy", "medium", "hard")
OPEN_HOUR = 9               # the three puzzles change every day at 09:00 Tehran (the main case still opens at 21:00)
UNLOCK = {"easy": 0, "medium": 30, "hard": 50}   # coins to open a level for today; easy is free (Amin, 25 Nov 2026)
PRICES = {"time": 15, "pair": 35, "reopen": 15}
REWARD = 5                  # coins, only for the FREE level solved cleanly (3 stars) the first time: a paid level never pays coins
REWARD_LEVELS = ("easy",)
MAX_MISTAKES = 3
MAX_SECS = 6 * 3600


@lru_cache(maxsize=1)
def pool() -> list[dict]:
    try:
        return json.loads(POOL.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []


def config(cfg: dict) -> dict:
    raw = cfg.get("kikoja") if isinstance(cfg.get("kikoja"), dict) else {}
    out = dict(DEFAULT_CONFIG) | {k: raw[k] for k in DEFAULT_CONFIG if k in raw}
    if out["audience"] not in AUDIENCES:
        out["audience"] = "off"
    return out


def visible(cfg: dict, player) -> bool:
    if cfg["audience"] == "all":
        return True
    return cfg["audience"] == "testers" and bool(getattr(player, "tester", False))


def day(dt: datetime | None = None) -> date:
    """The «کی کجا؟» day a moment belongs to: it starts at 09:00 Tehran (named by the date it starts on)."""
    loc = gameclock._local(dt)
    return loc.date() if loc.hour >= OPEN_HOUR else loc.date() - timedelta(days=1)


def next_open(dt: datetime | None = None) -> datetime:
    """When the next set of puzzles opens (aware, Tehran)."""
    d = day(dt) + timedelta(days=1)
    return datetime(d.year, d.month, d.day, OPEN_HOUR, tzinfo=gameclock.tz())


def level_pool(level: str) -> list[dict]:
    return [p for p in pool() if p.get("level") == level]


def today_puzzle(level: str = "easy") -> dict | None:
    """The level's puzzle of today: the verified pool turns round one puzzle a day (ids are stable, order never changes)."""
    p = level_pool(level)
    return p[day().toordinal() % len(p)] if p else None


def price_of(level: str) -> int:
    return int(UNLOCK.get(level, 0))


def by_id(pid: str) -> dict | None:
    return next((x for x in pool() if x["id"] == pid), None)


def public(p: dict) -> dict:
    """What a phone may see before the puzzle is solved: everything except `answer`."""
    return {k: v for k, v in p.items() if k != "answer"}


def reveal(p: dict, proof: list | None) -> dict:
    a = p["answer"]
    return {"thief": a["thief"], "lie": a["lie"], "paths": a["paths"], "proof": proof or []}


def hint_data(p: dict, kinds: list[str]) -> dict:
    h = p["answer"]["hints"]
    return {k: h[k] for k in kinds if k in h}


def judge(p: dict, who: int, lie: str, con: str, wit: list[str]) -> str | None:
    """None = a complete proof; else the step the player goes back to: who | lie | con | wit."""
    a = p["answer"]
    if who != a["thief"]:
        return "who"
    if lie != a["lie"]:
        return "lie"
    wits = a["cons"].get(con)
    if wits is None:
        return "con"
    if not wits:                       # a fact, or the rule alone clears the other speaker: no witness needed
        return None
    ids = sorted(set(wit))
    if len(ids) > 2 or not any(sorted(w) == ids for w in wits):
        return "wit"
    return None


def stars_for(mistakes: int, hints: list, reopened: bool) -> int:
    if reopened:
        return 1
    return max(1, 3 - mistakes - (1 if hints else 0))
