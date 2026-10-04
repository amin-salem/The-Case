"""Case files: loaded from app/content/cases/*.json when the server starts.

Each case opens on its "publish" day at NEW_CASE_HOUR (Tehran time). The
newest opened case is "today's case"; older ones go to the archive.
The phone never gets the solution or the hints: they stay on the server.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from functools import lru_cache
from pathlib import Path
from zoneinfo import ZoneInfo

from .config import get_settings

CASES_DIR = Path(__file__).parent / "content" / "cases"
SECRET_KEYS = ("hints", "solution")
# the scenes the app can draw and play sound for (app/lib/widgets/scene.dart, app/assets/sounds)
SCENES = frozenset({
    "bazaar_night", "office", "train", "museum", "villa_rain", "warehouse", "harbor", "hospital", "library",
    "theater", "hotel", "kitchen", "snow_lodge", "desert", "subway", "lab", "wedding", "school", "airport", "tower",
})


class CaseError(ValueError):
    pass


@dataclass(frozen=True)
class Case:
    id: str
    number: int
    publish: date
    data: dict

    @property
    def culprit(self) -> str:
        return self.data["solution"]["culprit"]

    @property
    def proof(self) -> set[str]:
        return set(self.data["solution"]["proof"])

    @property
    def hints(self) -> list[str]:
        return self.data["hints"]

    def public(self) -> dict:
        """Everything except the hints and the solution."""
        return {k: v for k, v in self.data.items() if k not in SECRET_KEYS}

    def summary(self) -> dict:
        d = self.data
        return {"id": self.id, "number": self.number, "title": d["title"], "location": d["location"],
                "scene": d["scene"], "difficulty": d["difficulty"], "publish": self.publish.isoformat()}


def validate(d: dict) -> None:
    for key in ("id", "number", "publish", "title", "location", "scene", "difficulty", "intro",
                "suspects", "evidence", "hints", "solution"):
        if key not in d:
            raise CaseError(f"{d.get('id', '?')}: missing {key}")
    if d["scene"] not in SCENES:
        raise CaseError(f"{d['id']}: unknown scene {d['scene']!r}")
    if d["difficulty"] not in (1, 2, 3, 4, 5):
        raise CaseError(f"{d['id']}: difficulty must be 1-5")
    sids = [s["id"] for s in d["suspects"]]
    eids = [e["id"] for e in d["evidence"]]
    if len(eids) < 5:
        raise CaseError(f"{d['id']}: needs at least 5 pieces of evidence")
    if len(set(sids)) != len(sids) or len(set(eids)) != len(eids):
        raise CaseError(f"{d['id']}: duplicate suspect/evidence id")
    if not 3 <= len(sids) <= 6:
        raise CaseError(f"{d['id']}: needs 3-6 suspects")
    if len(d["hints"]) != 3:
        raise CaseError(f"{d['id']}: needs exactly 3 hints")
    sol = d["solution"]
    if sol["culprit"] not in sids:
        raise CaseError(f"{d['id']}: culprit is not a suspect")
    if not sol["proof"] or any(p not in eids for p in sol["proof"]):
        raise CaseError(f"{d['id']}: proof must be evidence ids")
    for s in d["suspects"]:
        for key in ("name", "role", "avatar", "statement", "questions"):
            if key not in s:
                raise CaseError(f"{d['id']}/{s['id']}: missing {key}")
        if len(s["questions"]) < 2:
            raise CaseError(f"{d['id']}/{s['id']}: needs at least 2 questions")
    for e in d["evidence"]:
        for key in ("type", "title", "text"):
            if key not in e:
                raise CaseError(f"{d['id']}/{e['id']}: missing {key}")
    date.fromisoformat(d["publish"])


@lru_cache
def all_cases() -> tuple[Case, ...]:
    cases = []
    for path in sorted(CASES_DIR.glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        validate(d)
        cases.append(Case(id=d["id"], number=int(d["number"]), publish=date.fromisoformat(d["publish"]), data=d))
    cases.sort(key=lambda c: (c.publish, c.number))
    return tuple(cases)


def by_id(case_id: str) -> Case | None:
    return next((c for c in all_cases() if c.id == case_id), None)


def _tz() -> ZoneInfo:
    return ZoneInfo(get_settings().timezone)


def now_local() -> datetime:
    return datetime.now(_tz())


def today_str() -> str:
    return now_local().date().isoformat()


def opens_at(c: Case) -> datetime:
    return datetime.combine(c.publish, time(get_settings().new_case_hour), tzinfo=_tz())


def opened(now: datetime | None = None) -> list[Case]:
    now = now or now_local()
    return [c for c in all_cases() if opens_at(c) <= now]


def todays_case(now: datetime | None = None) -> Case | None:
    o = opened(now)
    return o[-1] if o else None


def next_case_at(now: datetime | None = None) -> datetime:
    """When the next case opens (tomorrow 21:00 if no newer case is written yet)."""
    now = now or now_local()
    future = [opens_at(c) for c in all_cases() if opens_at(c) > now]
    if future:
        return min(future)
    t = datetime.combine(now.date(), time(get_settings().new_case_hour), tzinfo=_tz())
    return t if t > now else t + timedelta(days=1)


def week_start(d: date) -> date:
    """Iranian weeks start on Saturday."""
    return d - timedelta(days=(d.weekday() - 5) % 7)
