"""Quick riddles («معمای سریع»): one-minute mini mysteries, loaded from app/content/riddles.json.

Every Tehran day has the same set of RIDDLES_PER_DAY riddles for everyone. The order is shuffled once
per cycle (all riddles once), so the same riddle comes back only after a full cycle. The answer and
the explanation stay on the server until the player has answered.
"""
from __future__ import annotations

import json
import random
from dataclasses import dataclass
from datetime import date
from functools import lru_cache
from pathlib import Path

from . import economy as eco
from .content import SCENES

PATH = Path(__file__).parent / "content" / "riddles.json"
EPOCH = date(2026, 1, 1)


@dataclass(frozen=True)
class Riddle:
    id: str
    title: str
    scene: str
    text: str
    clue: str
    choices: tuple[str, ...]  # in the order the player sees them
    answer: int               # index into choices
    explain: str

    def public(self) -> dict:
        return {"id": self.id, "title": self.title, "scene": self.scene, "text": self.text,
                "clue": self.clue, "choices": list(self.choices)}


def _build(d: dict) -> Riddle:
    for k in ("id", "title", "scene", "scene_text", "clue", "choices", "explain"):
        if not d.get(k):
            raise ValueError(f"riddle {d.get('id')}: missing {k}")
    if d["scene"] not in SCENES:
        raise ValueError(f"riddle {d['id']}: unknown scene {d['scene']}")
    choices = list(d["choices"])
    if len(choices) != 3 or len(set(choices)) != 3:
        raise ValueError(f"riddle {d['id']}: needs 3 different choices")
    # written with the right answer first; spread it over the three places (the same every time)
    order = [0, 1, 2]
    random.Random(f"riddle-{d['id']}").shuffle(order)
    return Riddle(id=d["id"], title=d["title"], scene=d["scene"], text=d["scene_text"], clue=d["clue"],
                  choices=tuple(choices[i] for i in order), answer=order.index(0), explain=d["explain"])


@lru_cache
def all_riddles() -> tuple[Riddle, ...]:
    items = tuple(_build(d) for d in json.loads(PATH.read_text(encoding="utf-8")))
    if len({r.id for r in items}) != len(items):
        raise ValueError("duplicate riddle id")
    if len(items) < eco.RIDDLES_PER_DAY:
        raise ValueError("not enough riddles")
    return items


def by_id(riddle_id: str) -> Riddle | None:
    return next((r for r in all_riddles() if r.id == riddle_id), None)


def for_day(day: str) -> list[Riddle]:
    """The riddles of a Tehran day (YYYY-MM-DD), in order. Slot 1..RIDDLE_FREE are free."""
    items = sorted(all_riddles(), key=lambda r: r.id)
    per = eco.RIDDLES_PER_DAY
    days_per_cycle = len(items) // per
    n = (date.fromisoformat(day) - EPOCH).days
    cycle, k = divmod(n, days_per_cycle)
    order = random.Random(f"riddle-cycle-{cycle}").sample(items, len(items))
    return order[k * per:(k + 1) * per]
