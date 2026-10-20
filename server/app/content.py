"""Case files: loaded from app/content/cases/*.json when the server starts.

Each case opens on its "publish" day at NEW_CASE_HOUR (Tehran time). The
newest opened case is "today's case"; older ones go to the archive.
The phone never gets the solution or the hints: they stay on the server.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from functools import lru_cache
from pathlib import Path
from zoneinfo import ZoneInfo

from . import gameclock
from .config import get_settings
from .content_paths import CONTENT_ROOT

CASES_DIR = CONTENT_ROOT / "cases"
WEEKLY_DIR = CONTENT_ROOT / "weekly"
# `night1` (weekend format 3) holds the answer of the night-1 question; weekly_public() adds a safe copy back
SECRET_KEYS = ("hints", "solution", "night1")
# the scenes the app can draw and play sound for (app/lib/widgets/scene.dart, app/assets/sounds)
SCENES = frozenset({
    "bazaar_night", "office", "train", "museum", "villa_rain", "warehouse", "harbor", "hospital", "library",
    "theater", "hotel", "kitchen", "snow_lodge", "desert", "subway", "lab", "wedding", "school", "airport", "tower",
})

# Topic category of a case (docs/case-writing-rules.md §9): key -> (Persian name, icon name the app draws).
# `category` is optional in the JSON for old files, but every case written from 18 Oct 2026 sets it.
CATEGORIES = {
    "medical": ("پزشکی", "medical_services"),
    "art": ("هنر و صحنه", "palette"),
    "family": ("خانواده و ارث", "family_restroom"),
    "business": ("تجارت و پول", "storefront"),
    "science": ("علم و پژوهش", "science"),
    "travel": ("سفر و مهمانی", "luggage"),
    "crime": ("جرم و قانون", "gavel"),
}


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
        # story chapters may word the hints in the partner's voice (`partner_hints`, same count)
        return self.data.get("partner_hints") or self.data["hints"]

    def public(self) -> dict:
        """Everything except the hints and the solution."""
        return {k: v for k, v in self.data.items() if k not in SECRET_KEYS}

    def summary(self) -> dict:
        d = self.data
        return {"id": self.id, "number": self.number, "title": d["title"], "location": d["location"],
                "scene": d["scene"], "category": d.get("category", ""), "difficulty": d["difficulty"],
                "publish": self.publish.isoformat()}


INTRO_MIN, INTRO_MAX = 20, 90  # every suspect has a short neutral intro (docs/case-writing-rules.md)


def validate(d: dict, max_suspects: int = 6) -> None:
    for key in ("id", "number", "publish", "title", "location", "scene", "difficulty", "intro",
                "suspects", "evidence", "hints", "solution"):
        if key not in d:
            raise CaseError(f"{d.get('id', '?')}: missing {key}")
    if d["scene"] not in SCENES:
        raise CaseError(f"{d['id']}: unknown scene {d['scene']!r}")
    if d["difficulty"] not in (1, 2, 3, 4, 5):
        raise CaseError(f"{d['id']}: difficulty must be 1-5")
    if d.get("category", "") != "" and d["category"] not in CATEGORIES:
        raise CaseError(f"{d['id']}: unknown category {d['category']!r} (known: {sorted(CATEGORIES)})")
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
        intro = s.get("intro")
        if not isinstance(intro, str) or not INTRO_MIN <= len(intro.strip()) <= INTRO_MAX:
            raise CaseError(f"{d['id']}/{s['id']}: intro must be {INTRO_MIN}-{INTRO_MAX} characters")
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
    return gameclock.tz()


def now_local() -> datetime:
    """Now (Tehran). The one entry point tests patch; the rules themselves live in app/gameclock.py."""
    return gameclock.now()


def today_str() -> str:
    """The CALENDAR day (midnight to midnight, Tehran): login reward, ad limit, riddles. Not for cases or weeks."""
    return gameclock.calendar_day(now_local()).isoformat()


def mission_day_str(now: datetime | None = None) -> str:
    """The daily-missions day runs from the new case's hour (21:00) to the same hour next evening and is named by the
    NEXT date (after 21:00 it is already tomorrow's date), so missions change together with the new case.
    Same labels as before the game clock existed: stored MissionDay rows stay valid."""
    now = now or now_local()
    return (gameclock.game_day(now) + timedelta(days=1)).isoformat()


def mission_next_at(now: datetime | None = None) -> datetime:
    """When the missions change next: the next time the clock shows the new case's hour."""
    return gameclock.next_rollover(now or now_local())


@lru_cache(maxsize=1024)
def _open_moment(publish: date, hour: int, tzname: str) -> datetime:
    """A pure function of its arguments (datetimes are immutable), so it is memoised: opened()/todays_case() ask for the
    opening moment of every case several times per request and the case list used to do it once per row."""
    return datetime.combine(publish, time(hour), tzinfo=ZoneInfo(tzname))


def opens_at(c: Case) -> datetime:
    # a weekend case may set its own `open_hour` (new ones open at 09:00, away from the 21:00 nightly case)
    s = get_settings()
    hour = c.data.get("open_hour") if isinstance(c.data, dict) else None
    if not isinstance(hour, int) or not 0 <= hour <= 23:
        hour = s.new_case_hour
    return _open_moment(c.publish, hour, s.timezone)


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
    return gameclock.next_rollover(now)


def next_boundary(now: datetime | None = None) -> datetime:
    """The next moment anything that depends on the clock can change for everybody: a case or chapter opens, a weekend
    case closes, the story opens, the date changes, the mission day changes. Caches of clock-dependent data that is
    the same for all players are dropped at this moment (app/cache.py)."""
    now = now or now_local()
    times = [now.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1), mission_next_at(now), next_case_at(now),
             gameclock.next_week_start(now), gameclock.settle_at(gameclock.week_of(now) - timedelta(days=7))]
    for c in weekly_cases():
        start = opens_at(c)
        times += [start + timedelta(hours=ch.get("at_hours", 0)) for ch in c.data.get("chapters") or []]
        times.append(weekly_closes_at(c))
    times += [story_opens_at(), next_thursday_at(now)]
    return min(t for t in times if t > now)


def case_week(c: Case) -> date:
    """The week (its first game day) a case belongs to: from when the CASE opens, never from when it is solved."""
    return gameclock.case_week(opens_at(c))


def week_cases(ws: date) -> list[Case]:
    """The nightly cases and the weekend case that belong to week `ws` (what the weekly board counts)."""
    return [c for c in (*all_cases(), *weekly_cases()) if case_week(c) == ws]


# ---------------------------------------------------------------- weekly big case
# Opens on its publish day (a Thursday) at NEW_CASE_HOUR and stays "this weekend's case" until
# WEEKLY_DAYS later. It comes in chapters: evidence listed in a later chapter is hidden until
# that chapter opens (at_hours after the start). Solving it also asks for the motive.
WEEKLY_DAYS = 3  # old cases (w001) without closes_hours; kept for reference
WEEKLY_HOURS = 36  # new weekend cases: Thursday 09:00 to Friday 21:00 unless the file says closes_hours (w001: its file says 48)


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
    if d.get("format") in (2, 3):
        for s in d["suspects"]:
            r = s.get("reactions")
            if not isinstance(r, dict) or not r or not set(r) <= eids or not all(isinstance(v, str) and v.strip() for v in r.values()):
                raise CaseError(f"{d['id']}/{s['id']}: format {d['format']} needs `reactions` (evidence id -> what the suspect says)")
        culprit_r = next(s for s in d["suspects"] if s["id"] == d["solution"]["culprit"])["reactions"]
        if not set(culprit_r) & set(d["solution"]["proof"]):
            raise CaseError(f"{d['id']}: the culprit must react to at least one proof card")
    if d.get("format") == 3:
        validate_format3(d, eids)
    motives = {m["id"] for m in d.get("motives", [])}
    if len(motives) < 2 or d["solution"].get("motive") not in motives:
        raise CaseError(f"{d['id']}: needs motives and the right one in the solution")


def validate_format3(d: dict, eids: set[str]) -> None:
    """Weekend format 3 (docs/weekend-format.md): two nights. Night 1 has its own small question («کی دروغ می‌گه؟») and
    its own suspects/cards; chapter 2 brings ONE new suspect and new cards."""
    cid = d["id"]
    chapters = d["chapters"]
    if len(chapters) != 2 or chapters[1].get("at_hours", 0) <= 0 or not str(chapters[1].get("text", "")).strip():
        raise CaseError(f"{cid}: format 3 has exactly two chapters; the second has at_hours > 0 and a `text`")
    later = set(chapters[1].get("evidence", []))
    if len(later) < 2:
        raise CaseError(f"{cid}: format 3 chapter 2 needs at least two new evidence cards")
    if len(eids - later) < 4:
        raise CaseError(f"{cid}: format 3 night 1 needs at least four cards of its own")
    new = []
    for s in d["suspects"]:
        a = s.get("appears_chapter", 0)
        if a not in (0, 1) or isinstance(a, bool):
            raise CaseError(f"{cid}/{s['id']}: appears_chapter must be 0 or 1")
        if a == 1:
            new.append(s["id"])
    if len(new) != 1:
        raise CaseError(f"{cid}: format 3 has exactly ONE suspect with appears_chapter 1 (the newcomer of chapter 2)")
    if d["solution"]["culprit"] in new:
        raise CaseError(f"{cid}: the culprit must be there from night 1 (a newcomer would make the early answer impossible)")
    n1 = d.get("night1")
    if not isinstance(n1, dict):
        raise CaseError(f"{cid}: format 3 needs `night1` {{liar, card, explanation}}")
    visible = {s["id"] for s in d["suspects"]} - set(new)
    if n1.get("liar") not in visible or n1.get("liar") == d["solution"]["culprit"]:
        raise CaseError(f"{cid}: night1.liar must be a night-1 suspect and not the culprit")
    if n1.get("card") not in eids or n1.get("card") in later:
        raise CaseError(f"{cid}: night1.card must be a night-1 evidence card")
    if not isinstance(n1.get("explanation"), str) or not n1["explanation"].strip():
        raise CaseError(f"{cid}: night1.explanation is required")
    q = n1.get("question", "")
    if not isinstance(q, str) or len(q) > 80:
        raise CaseError(f"{cid}: night1.question must be text up to 80 characters")


def suspect_chapter(s: dict) -> int:
    """The chapter index (0-based) a suspect appears in; old files have no `appears_chapter` (= there from the start)."""
    a = s.get("appears_chapter", 0)
    return a if isinstance(a, int) and a >= 0 else 0


def chapters_open(c: Case, now: datetime | None = None) -> int:
    now = now or now_local()
    start = opens_at(c)
    return sum(1 for ch in c.data["chapters"] if start + timedelta(hours=ch.get("at_hours", 0)) <= now)


def visible_suspect_ids(c: Case, now: datetime | None = None) -> set[str]:
    """Suspects a player may see (and accuse, question, show cards to) right now. Format 3 hides the newcomer until chapter 2."""
    n = chapters_open(c, now)
    return {s["id"] for s in c.data["suspects"] if suspect_chapter(s) < max(1, n)}


def night1_open(c: Case, now: datetime | None = None) -> bool:
    """The night-1 question can be answered while chapter 2 has not opened yet (and the case is open)."""
    now = now or now_local()
    return c.data.get("format") == 3 and opens_at(c) <= now < weekly_closes_at(c) and chapters_open(c, now) < 2


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


WEEKEND_OPEN_HOUR = 9  # when a new weekend case opens (Thursday 09:00, away from the 21:00 nightly case); a file may set open_hour
WEEKEND_OPEN_WEEKDAY = 3  # Monday = 0 ... Thursday = 3

_FA_DAYS = ["دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه", "شنبه", "یکشنبه"]


def _fa_num(n: int) -> str:
    return str(n).translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def weekend_schedule() -> dict:
    """The weekend case's regular schedule, from the same constants the clock uses, so the app text can never
    drift: opens WEEKEND_OPEN_WEEKDAY at WEEKEND_OPEN_HOUR, stays open WEEKLY_HOURS. `text` is the sentence the
    app shows (e.g. «هر هفته چهارشنبه شب ساعت ۲۱ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.»)."""
    total = WEEKEND_OPEN_HOUR + WEEKLY_HOURS
    close_day = (WEEKEND_OPEN_WEEKDAY + total // 24) % 7
    close_hour = total % 24
    part = "شب " if WEEKEND_OPEN_HOUR >= 18 else ("صبح " if WEEKEND_OPEN_HOUR < 12 else "")
    text = (f"هر هفته {_FA_DAYS[WEEKEND_OPEN_WEEKDAY]} {part}ساعت {_fa_num(WEEKEND_OPEN_HOUR)} باز می‌شه و "
            f"تا {_FA_DAYS[close_day]} ساعت {_fa_num(close_hour)} وقت داری.")
    return {"open_weekday": WEEKEND_OPEN_WEEKDAY, "open_hour": WEEKEND_OPEN_HOUR, "hours": WEEKLY_HOURS, "text": text}


def weekly_closes_at(c: Case) -> datetime:
    hours = c.data.get("closes_hours")
    if isinstance(hours, int) and hours > 0:
        return opens_at(c) + timedelta(hours=hours)
    return opens_at(c) + timedelta(hours=WEEKLY_HOURS)


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
    d = now.date() + timedelta(days=(WEEKEND_OPEN_WEEKDAY - now.weekday()) % 7)
    t = datetime.combine(d, time(WEEKEND_OPEN_HOUR), tzinfo=_tz())
    return t if t > now else t + timedelta(days=7)


# ---------------------------------------------------------------- story mode
# Chapters live in content/story/sNN/chNN.json: the same case JSON as nightly cases plus the partner's
# lines (see validate_story). A missing or empty folder means "coming soon": the app shows the banner.
STORY_DIR = CONTENT_ROOT / "story"
STORY_FIELDS = ("partner_intro", "partner_outro_win", "partner_outro_lose", "thread")
STORY_ID = re.compile(r"^s(\d{2})ch(\d{2})$")
STORY_SEASON = {
    "season": 1,
    "title": "کبریت سوخته",
    "tagline": "هر جا یه کبریت سوخته پیدا شد، یه نفر چیزی رو از دست داده. سرگرد ناصری سه ساله دنبالشه، "
               "و حالا تو همکارشی.",
    "partner": "سرگرد ناصری",
    "opens_at": "2099-01-01T00:00:00",  # Tehran time. PAUSED 12 Oct 2026 (Amin): story is being rebuilt with choices; set the real date when it is ready
}


def story_case_id(season: int, chapter: int) -> str:
    return f"s{season:02d}ch{chapter:02d}"


def is_story(case_id: str) -> bool:
    return bool(STORY_ID.match(case_id))


def validate_story(d: dict, season: int, chapter: int) -> None:
    d.setdefault("publish", "2026-10-12")  # story chapters have no publish day; the field is for the case schema
    if d.get("id") != story_case_id(season, chapter):
        raise CaseError(f"{d.get('id', '?')}: id must be {story_case_id(season, chapter)}")
    validate(d)
    if d.get("season") != season or d.get("chapter") != chapter or d.get("number") != chapter:
        raise CaseError(f"{d['id']}: season/chapter/number must match the file name")
    for key in STORY_FIELDS:
        if not isinstance(d.get(key), str) or not d[key].strip():
            raise CaseError(f"{d['id']}: missing {key}")
    ph = d.get("partner_hints")
    if ph is not None and (not isinstance(ph, list) or len(ph) != 3 or not all(isinstance(x, str) and x for x in ph)):
        raise CaseError(f"{d['id']}: partner_hints must be 3 texts")
    if "scenes" in d:
        validate_scenes(d)


# ---- choices format (docs/story-mode.md): `scenes` + `ending` + `board`. A chapter without `scenes` (the old
# format) plays as one scene with a single «شروع» option, see story_scenes().
RELATION_STATES = ("unmet", "neutral", "friendly", "suspicious")
MAX_SCENES, MAX_OPTIONS, MAX_SCENE_CHARS, MAX_TITLE_CHARS = 8, 3, 1400, 120
MAX_CHOICES = 40  # hard cap on the choices one player can store for one chapter
_ID = re.compile(r"^[A-Za-z0-9_]{1,24}$")


def _text(x, limit: int) -> bool:
    return isinstance(x, str) and 0 < len(x.strip()) <= limit


def story_scenes(d: dict) -> dict:
    """{"scenes": [...], "ending": {...}, "board": {...}} of a chapter, old or new format. The first scene starts."""
    if "scenes" in d:
        return {"scenes": d["scenes"], "ending": d["ending"], "board": d.get("board") or {"people": [], "clues": []}}
    return {
        "scenes": [{"id": "start", "text": d["partner_intro"], "speaker": "partner",
                    "options": [{"id": "go", "title": "شروع", "sub": "", "goes_to": "ending"}]}],
        "ending": {"id": "ending", "text": "پرونده را بخوان، با مظنون‌ها حرف بزن و متهم را مشخص کن.", "speaker": "partner"},
        "board": {"people": [], "clues": []},
    }


def validate_scenes(d: dict) -> None:
    cid = d["id"]
    scenes, ending = d["scenes"], d.get("ending")
    board = d.get("board") or {}
    if not isinstance(scenes, list) or not 1 <= len(scenes) <= MAX_SCENES:
        raise CaseError(f"{cid}: scenes must be a list of 1-{MAX_SCENES}")
    if not isinstance(ending, dict) or not _text(ending.get("text"), MAX_SCENE_CHARS) or not _ID.match(str(ending.get("id", ""))):
        raise CaseError(f"{cid}: ending needs id and text")
    people = board.get("people", [])
    clues = board.get("clues", [])
    pids = [p.get("id") for p in people]
    if len(set(pids)) != len(pids) or not all(isinstance(i, str) and _ID.match(i) and _text(p.get("name"), 40)
                                              for i, p in zip(pids, people)):
        raise CaseError(f"{cid}: board people need unique ids and names")
    cl_ids = [c.get("id") for c in clues]
    eids = {e["id"] for e in d["evidence"]}
    if len(set(cl_ids)) != len(cl_ids) or not all(isinstance(i, str) and _ID.match(i) and _text(c.get("title"), MAX_TITLE_CHARS)
                                                  for i, c in zip(cl_ids, clues)):
        raise CaseError(f"{cid}: board clues need unique ids and titles")
    valid_clues = set(cl_ids) | eids
    ids = [s.get("id") for s in scenes]
    if len(set(ids)) != len(ids) or ending["id"] in ids or not all(isinstance(i, str) and _ID.match(i) for i in ids):
        raise CaseError(f"{cid}: scene ids must be unique ([A-Za-z0-9_])")
    by_id = {s["id"]: s for s in scenes}
    for s in scenes:
        if not _text(s.get("text"), MAX_SCENE_CHARS):
            raise CaseError(f"{cid}/{s['id']}: scene text is empty or longer than {MAX_SCENE_CHARS} characters")
        opts = s.get("options")
        if not isinstance(opts, list) or not 1 <= len(opts) <= MAX_OPTIONS:
            raise CaseError(f"{cid}/{s['id']}: needs 1-{MAX_OPTIONS} options (dead end)")
        oids = [o.get("id") for o in opts]
        if len(set(oids)) != len(oids) or not all(isinstance(i, str) and _ID.match(i) for i in oids):
            raise CaseError(f"{cid}/{s['id']}: option ids must be unique")
        for o in opts:
            if not _text(o.get("title"), MAX_TITLE_CHARS) or not isinstance(o.get("sub", ""), str) or len(o.get("sub", "")) > MAX_TITLE_CHARS * 2:
                raise CaseError(f"{cid}/{s['id']}/{o['id']}: option needs a title (and a short sub)")
            if o.get("goes_to") not in by_id and o.get("goes_to") != ending["id"]:
                raise CaseError(f"{cid}/{s['id']}/{o['id']}: goes_to is not a scene")
            for key in ("gives_clue", "needs_clue"):
                v = o.get(key, [] if key == "gives_clue" else None)
                for c in ([v] if isinstance(v, str) else (v or [])):
                    if c not in valid_clues:
                        raise CaseError(f"{cid}/{s['id']}/{o['id']}: unknown clue {c!r}")
            for p, st in (o.get("relations") or {}).items():
                if p not in pids or st not in RELATION_STATES:
                    raise CaseError(f"{cid}/{s['id']}/{o['id']}: bad relation {p!r}: {st!r}")
        if not any(not o.get("needs_clue") for o in opts):
            raise CaseError(f"{cid}/{s['id']}: needs at least one option that is never locked")
    # graph: acyclic, everything reachable from the first scene, every scene reaches the ending
    nxt = {s["id"]: {o["goes_to"] for o in s["options"]} for s in scenes}
    reach: dict[str, set[str]] = {}
    state: dict[str, int] = {}

    def walk(n: str) -> set[str]:
        if n == ending["id"]:
            return set()
        if state.get(n) == 1:
            raise CaseError(f"{cid}: scenes loop back at {n!r}")
        if n in reach:
            return reach[n]
        state[n] = 1
        out: set[str] = set()
        for m in nxt[n]:
            out.add(m)
            out |= walk(m)
        state[n] = 2
        reach[n] = out
        return out

    first = scenes[0]["id"]
    below = walk(first)
    missing = set(by_id) - below - {first}
    if missing:
        raise CaseError(f"{cid}: scenes never reached: {sorted(missing)}")
    for sid in by_id:
        if ending["id"] not in reach[sid] | nxt[sid]:
            raise CaseError(f"{cid}: scene {sid!r} cannot reach the ending")
    # a locked option's clue must be obtainable on a path that reaches the option's scene
    for s in scenes:
        for o in s["options"]:
            need = o.get("needs_clue")
            if not need:
                continue
            need = [need] if isinstance(need, str) else list(need)
            for c in need:
                ok = False
                for t in scenes:
                    if t["id"] == s["id"] or s["id"] not in reach[t["id"]]:
                        continue  # only scenes that come before this one
                    for o2 in t["options"]:
                        if c in _as_list(o2.get("gives_clue")) and (o2["goes_to"] == s["id"] or s["id"] in reach.get(o2["goes_to"], set())):
                            ok = True
                if not ok:
                    raise CaseError(f"{cid}/{s['id']}/{o['id']}: clue {c!r} cannot be obtained before this option")


def _as_list(v) -> list:
    return [v] if isinstance(v, str) else list(v or [])


@lru_cache
def _story_load(folder: str) -> dict[int, tuple[Case, ...]]:
    out: dict[int, list[Case]] = {}
    root = Path(folder)
    if not root.is_dir():
        return {}
    for sdir in sorted(root.glob("s[0-9][0-9]")):
        season = int(sdir.name[1:])
        cases = []
        for path in sorted(sdir.glob("ch[0-9][0-9].json")):
            chapter = int(path.stem[2:])
            d = json.loads(path.read_text(encoding="utf-8"))
            validate_story(d, season, chapter)
            cases.append(Case(id=d["id"], number=chapter, publish=date.fromisoformat(d["publish"]), data=d))
        if cases:
            if [c.number for c in cases] != list(range(1, len(cases) + 1)):
                raise CaseError(f"season {season}: chapters must be numbered 1..N without gaps")
            out[season] = tuple(cases)
    return {k: tuple(v) for k, v in out.items()}


def story_chapters(season: int | None = None) -> tuple[Case, ...]:
    """The written chapters of a season (default: the current one), in order."""
    return _story_load(str(STORY_DIR)).get(season or STORY_SEASON["season"], ())


def story_by_id(case_id: str) -> Case | None:
    m = STORY_ID.match(case_id)
    if not m:
        return None
    chapters = story_chapters(int(m.group(1)))
    n = int(m.group(2))
    return chapters[n - 1] if 1 <= n <= len(chapters) else None


def story_opens_at() -> datetime:
    return datetime.fromisoformat(STORY_SEASON["opens_at"]).replace(tzinfo=_tz())


def story_open_for(player, now: datetime | None = None) -> bool:
    """Story mode for one player: open for everybody on the opening date, and any time for a tester."""
    if getattr(player, "tester", False):
        return bool(story_chapters())
    return story_open(now)


def story_open(now: datetime | None = None) -> bool:
    """Story mode is playable: its opening time has passed AND chapters are written."""
    return story_opens_at() <= (now or now_local()) and bool(story_chapters())


def story_upcoming(now: datetime | None = None) -> dict:
    now = now or now_local()
    return {**{k: v for k, v in STORY_SEASON.items() if k != "opens_at"},
            "opens_at": int(story_opens_at().timestamp()), "open": story_open(now),
            "chapters": len(story_chapters())}


def weekend_upcoming(now: datetime | None = None) -> dict:
    now = now or now_local()
    cur = current_weekly(now)
    if cur:
        return {"open": True, "title": cur.data["title"], "scene": cur.data.get("scene"),
                "closes_at": int(weekly_closes_at(cur).timestamp()), "schedule": weekend_schedule()}
    nxt = next_weekly(now)
    at = opens_at(nxt) if nxt else next_thursday_at(now)
    return {"open": False, "opens_at": int(at.timestamp()),
            "title": nxt.data["title"] if nxt else None, "scene": nxt.data.get("scene") if nxt else None,
            "location": nxt.data.get("location") if nxt else None, "schedule": weekend_schedule()}


@lru_cache
def _notify_texts() -> dict:
    try:
        return json.loads((CONTENT_ROOT / "notify.json").read_text(encoding="utf-8"))
    except Exception:  # a missing or broken teaser file must never break the app's config
        return {}


_FA_COUNT = {2: "دو", 3: "سه", 4: "چهار"}


def notify_plan(now: datetime | None = None, days: int = 10) -> list[dict]:
    """What the phone should announce in the next days: each night's case, the weekend case and its
    chapters, and the story opening. Texts come from content/notify.json (one hand-written teaser per
    case, used only while the case title still matches), otherwise they are made from the case itself."""
    now = now or now_local()
    end = now + timedelta(days=days)
    out: list[dict] = []
    texts = _notify_texts()
    for c in all_cases():
        at = opens_at(c)
        if not (now < at <= end):
            continue
        t = texts.get(c.id) or {}
        title = c.data.get("title", "")
        if t.get("title") == title and t.get("head"):
            head, body = t["head"], t.get("body", "")
        else:
            head = f"«{title}» باز شد 🕵️"
            body = f"{c.data.get('location') or 'یه صحنه‌ی تازه'}؛ یه جنایت تازه منتظرته."
        out.append({"kind": "nightly", "at": int(at.timestamp()), "head": head, "body": body,
                    "late": f"«{title}» هنوز حل نشده؛ زنجیره‌ات منتظره."})
    for c in weekly_cases():
        title = c.data.get("title", "")
        for n, ch in enumerate(c.data.get("chapters") or [], start=1):
            at = opens_at(c) + timedelta(hours=ch.get("at_hours", 0))
            if not (now < at <= end):
                continue
            if n == 1:
                t = texts.get(c.id) or {}
                ok = t.get("title") == title and t.get("head")
                head = t["head"] if ok else f"پرونده‌ی آخر هفته باز شد: «{title}» 🌙"
                body = t.get("body", "") if ok else f"{c.data.get('location') or ''} · {_FA_COUNT.get(len(c.data['chapters']), len(c.data['chapters']))} فصل، {len(c.data['suspects'])} مظنون؛ از همین فصل اول می‌تونی متهم کنی.".strip(" ·")
            else:
                total = len(c.data["chapters"])
                head = f"فصل {n} از {total} باز شد: «{title}»"
                body = ("یه مظنون تازه و مدارک جدید رسید؛ شب دوم شروع شد." if c.data.get("format") == 3 else
                        "مدارک تازه رسید؛ فصل آخره. اگه هنوز متهم نکردی، وقتشه." if n == total
                        else "مدارک تازه رسید؛ شاید دروغ مقصر لای همین‌هاست.")
            out.append({"kind": "weekend", "at": int(at.timestamp()), "head": head, "body": body})
    for back in (0, 1, 2):  # the weekly prizes are paid when the week has closed (Friday 21:00 + a few minutes)
        at = gameclock.settle_at(gameclock.week_of(now) - timedelta(days=7 * back))
        if now < at <= end:
            out.append({"kind": "weekresult", "at": int(at.timestamp()), "head": "نتیجه‌ی هفته اعلام شد 🏆",
                        "body": "جدول برترهای هفته بسته شد. شاید جایزه گرفته باشی؛ صندوق هدیه‌ها رو ببین!"})
    at = story_opens_at()
    if now < at <= end:
        out.append({"kind": "story", "at": int(at.timestamp()),
                    "head": f"داستان «{STORY_SEASON['title']}» شروع شد 🔥", "body": STORY_SEASON["tagline"]})
    out.sort(key=lambda x: x["at"])
    return out


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
    # what a suspect says about a card is only given by the "show" call (it is limited), never in the case file
    shown = {sid for sid in visible_suspect_ids(c, now)}
    data["suspects"] = [{k: v for k, v in s.items() if k != "reactions"} for s in data["suspects"] if s["id"] in shown]
    # which night each card belongs to (1 = from the start), so the app can split «شب اول / شب دوم»
    night_of = {e: i + 1 for i, ch in enumerate(c.data["chapters"]) for e in ch.get("evidence", [])}
    data["evidence"] = [{**e, "chapter": night_of.get(e["id"], 1)} for e in data["evidence"] if e["id"] not in hidden]
    data["chapters_open"] = len(chapters)
    from . import economy as eco
    data["shows_per_chapter"] = eco.WEEKEND_SHOWS_PER_CHAPTER
    data["chapters"] = chapters
    data["chapters_total"] = len(c.data["chapters"])
    data["next_chapter_at"] = int(next_at.timestamp()) if next_at else None
    n1 = c.data.get("night1")
    if c.data.get("format") == 3 and isinstance(n1, dict):
        # the question only; liar, card and explanation are given by the answer call
        data["night1"] = {"question": n1.get("question") or "کی دروغ می‌گه؟", "open": night1_open(c, now),
                          "reward": eco.WEEKEND_LIAR_REWARD}
        late = [e for ch in c.data["chapters"][1:] for e in ch.get("evidence", [])]
        newcomers = [s for s in c.data["suspects"] if suspect_chapter(s) >= 1]
        # a teaser before chapter 2 (counts only, no names); the newcomer and cards show up in the lists afterwards
        data["night2"] = {"opens_at": int((start + timedelta(hours=c.data["chapters"][1].get("at_hours", 0))).timestamp()),
                          "new_suspects": len(newcomers), "new_cards": len(late), "open": len(chapters) >= 2}
    data["closes_at"] = int(weekly_closes_at(c).timestamp())
    return data

