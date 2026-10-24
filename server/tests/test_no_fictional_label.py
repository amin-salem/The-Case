"""Amin, 24 Oct 2026: a place is never labelled «خیالی» (fictional) in what players read first (title, location, intro)."""
from app import content


def test_no_fictional_label_in_title_location_intro():
    for c in (*content.all_cases(), *content.weekly_cases()):
        for key in ("title", "location", "intro"):
            assert "خیالی" not in str(c.data.get(key, "")), (c.id, key)
