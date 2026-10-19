#!/usr/bin/env python3
"""Read-only publication inventory. Output is an allowlist; no prose, suspects or answer material."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import content  # noqa: E402

TEHRAN = ZoneInfo("Asia/Tehran")


def unpublished(now: datetime) -> list[dict]:
    if now.tzinfo is None:
        raise ValueError("inventory time must include a timezone")
    now = now.astimezone(TEHRAN)
    rows = []

    def add(kind, ident, at, chapter=None):
        if at is not None and at <= now:
            return
        row = {"kind": kind, "id": ident, "opens_at": at.astimezone(TEHRAN).isoformat() if at else None}
        if chapter is not None:
            row["chapter"] = chapter
        if at is None:
            row["reason"] = "season_not_scheduled"
        rows.append(row)

    for c in content.all_cases():
        add("nightly", c.id, content.opens_at(c))
    for c in content.weekly_cases():
        start = content.opens_at(c)
        add("weekend", c.id, start)
        for n, chapter in enumerate(c.data.get("chapters") or [], 1):
            add("weekend_chapter", c.id, start + timedelta(hours=chapter.get("at_hours", 0)), n)
    # Story publication follows the season gate, NOT the case-schema placeholder `publish`.
    # Per-player chapter waits/warrants are progression rules, not publication dates.
    for season, chapters in content._story_load(str(content.STORY_DIR)).items():
        at = content.story_opens_at() if season == content.STORY_SEASON["season"] else None
        for c in chapters:
            add("story_chapter", c.id, at, c.number)
    return sorted(rows, key=lambda r: (r["opens_at"] or "9999", r["kind"], r["id"], r.get("chapter", 0)))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--at", help="ISO 8601 time with offset; defaults to the game's clock")
    args = parser.parse_args()
    try:
        now = datetime.fromisoformat(args.at) if args.at else content.now_local()
        rows = unpublished(now)
    except ValueError:
        parser.error("--at must be an ISO 8601 datetime with a timezone offset")
    print(json.dumps({"timezone": "Asia/Tehran", "as_of": now.astimezone(TEHRAN).isoformat(), "unpublished": rows},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
