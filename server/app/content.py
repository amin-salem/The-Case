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
WEEKLY_DIR = Path(__file__).parent / "content" / "weekly"
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


def validate(d: dict, max_suspects: int = 6) -> None:
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
    if not 3 <= len(sids) <= max_suspects:
        raise CaseError(f"{d['id']}: needs 3-{max_suspects} suspects")
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
    # a weekend case may set its own `open_hour` (new ones open at 09:00, away from the 21:00 nightly case)
    hour = c.data.get("open_hour") if isinstance(c.data, dict) else None
    if not isinstance(hour, int) or not 0 <= hour <= 23:
        hour = get_settings().new_case_hour
    return datetime.combine(c.publish, time(hour), tzinfo=_tz())


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


# ---------------------------------------------------------------- weekly big case
# Opens on its publish day (a Thursday) at NEW_CASE_HOUR and stays "this weekend's case" until
# WEEKLY_DAYS later. It comes in chapters: evidence listed in a later chapter is hidden until
# that chapter opens (at_hours after the start). Solving it also asks for the motive.
WEEKLY_DAYS = 3


def validate_weekly(d: dict) -> None:
    validate(d, max_suspects=8)
    eids = {e["id"] for e in d["evidence"]}
    chapters = d.get("chapters") or []
    if not chapters or chapters[0].get("at_hours", 0) != 0:
        raise CaseError(f"{d['id']}: the first chapter must open at the start")
    hours = [c.get("at_hours", 0) for c in chapters]
    if hours != sorted(hours):
        raise CaseError(f"{d['id']}: chapters out of order")
    for c in chapters:
        if not set(c.get("evidence", [])) <= eids:
            raise CaseError(f"{d['id']}: chapter lists unknown evidence")
    if "open_hour" in d and not (isinstance(d["open_hour"], int) and 0 <= d["open_hour"] <= 23):
        raise CaseError(f"{d['id']}: open_hour must be 0..23")
    if "closes_hours" in d and not (isinstance(d["closes_hours"], int) and d["closes_hours"] > max(hours)):
        raise CaseError(f"{d['id']}: closes_hours must be after the last chapter")
    motives = {m["id"] for m in d.get("motives", [])}
    if len(motives) < 2 or d["solution"].get("motive") not in motives:
        raise CaseError(f"{d['id']}: needs motives and the right one in the solution")


@lru_cache
def weekly_cases() -> tuple[Case, ...]:
    out = []
    for path in sorted(WEEKLY_DIR.glob("*.json")):
        d = json.loads(path.read_text(encoding="utf-8"))
        validate_weekly(d)
        out.append(Case(id=d["id"], number=int(d["number"]), publish=date.fromisoformat(d["publish"]), data=d))
    out.sort(key=lambda c: c.publish)
    return tuple(out)


def is_weekly(case_id: str) -> bool:
    return case_id.startswith("w")


def weekly_by_id(case_id: str) -> Case | None:
    return next((c for c in weekly_cases() if c.id == case_id), None)


WEEKEND_OPEN_HOUR = 9  # when a new weekend case opens (Thursday), see weekly files with open_hour


def weekly_closes_at(c: Case) -> datetime:
    hours = c.data.get("closes_hours")
    if isinstance(hours, int) and hours > 0:
        return opens_at(c) + timedelta(hours=hours)
    return opens_at(c) + timedelta(days=WEEKLY_DAYS) - timedelta(hours=get_settings().new_case_hour)


def current_weekly(now: datetime | None = None) -> Case | None:
    now = now or now_local()
    return next((c for c in weekly_cases() if opens_at(c) <= now < weekly_closes_at(c)), None)


def next_weekly(now: datetime | None = None) -> Case | None:
    """The next weekend case that is written but not open yet."""
    now = now or now_local()
    return next((c for c in weekly_cases() if opens_at(c) > now), None)


def next_thursday_at(now: datetime | None = None) -> datetime:
    """Next Thursday at NEW_CASE_HOUR (when a weekend case would open if none is written yet)."""
    now = now or now_local()
    d = now.date() + timedelta(days=(3 - now.weekday()) % 7)
    t = datetime.combine(d, time(WEEKEND_OPEN_HOUR), tzinfo=_tz())
    return t if t > now else t + timedelta(days=7)


# ---------------------------------------------------------------- story mode (coming soon)
# Shown as a countdown in the app until it opens. The run that builds story mode updates this.
STORY_SEASON = {
    "season": 1,
    "title": "کبریت سوخته",
    "tagline": "هر جا یه کبریت سوخته پیدا شد، یه نفر چیزی رو از دست داده. سرگرد ناصری سه ساله دنبالشه، "
               "و حالا تو همکارشی.",
    "partner": "سرگرد ناصری",
    "opens_at": "2026-10-12T00:00:00",  # Tehran time
}


def story_upcoming(now: datetime | None = None) -> dict:
    now = now or now_local()
    at = datetime.fromisoformat(STORY_SEASON["opens_at"]).replace(tzinfo=_tz())
    return {**{k: v for k, v in STORY_SEASON.items() if k != "opens_at"},
            "opens_at": int(at.timestamp()), "open": at <= now}


def weekend_upcoming(now: datetime | None = None) -> dict:
    now = now or now_local()
    cur = current_weekly(now)
    if cur:
        return {"open": True, "title": cur.data["title"], "scene": cur.data.get("scene"),
                "closes_at": int(weekly_closes_at(cur).timestamp())}
    nxt = next_weekly(now)
    at = opens_at(nxt) if nxt else next_thursday_at(now)
    return {"open": False, "opens_at": int(at.timestamp()),
            "title": nxt.data["title"] if nxt else None, "scene": nxt.data.get("scene") if nxt else None,
            "location": nxt.data.get("location") if nxt else None}


def weekly_all_open_at(c: Case) -> datetime:
    """When the last chapter of a weekend case opens (accusing is allowed from then on)."""
    last = max((ch.get("at_hours", 0) for ch in c.data.get("chapters") or [{}]), default=0)
    return opens_at(c) + timedelta(hours=last)


def weekly_public(c: Case, now: datetime | None = None) -> dict:
    """What players may see right now: evidence of chapters not open yet is left out."""
    now = now or now_local()
    start = opens_at(c)
    chapters, hidden, next_at = [], set(), None
    for ch in c.data["chapters"]:
        at = start + timedelta(hours=ch.get("at_hours", 0))
        if at <= now:
            chapters.append({"title": ch["title"], "text": ch.get("text", "")})
        else:
            hidden |= set(ch.get("evidence", []))
            next_at = next_at or at
    data = c.public()
    data["evidence"] = [e for e in data["evidence"] if e["id"] not in hidden]
    data["chapters"] = chapters
    data["chapters_total"] = len(c.data["chapters"])
    data["next_chapter_at"] = int(next_at.timestamp()) if next_at else None
    data["closes_at"] = int(weekly_closes_at(c).timestamp())
    return data
