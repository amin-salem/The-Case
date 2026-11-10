"""The writer's case index (server/tools/case_index.py): it must cover every case, leak nothing, and find the next slot."""
import importlib.util
import json
from datetime import date, timedelta
from pathlib import Path

from app import content

TOOL = Path(__file__).resolve().parents[1] / "tools" / "case_index.py"


def _tool():
    spec = importlib.util.spec_from_file_location("case_index", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_index_lists_every_case_and_carries_no_clue_text():
    mod = _tool()
    text = mod.build_index()
    for c in [*content.all_cases(), *content.weekly_cases()]:
        assert f"\n{c.id} | " in text, f"{c.id} is missing from the index"
    # the index is metadata only: no solution, hint, clue or statement text may leak into it
    for c in content.all_cases()[-10:]:
        assert c.data["solution"]["explanation"][:40] not in text
        assert c.data["hints"][0][:40] not in text
        assert c.data["evidence"][0]["text"][:40] not in text
        assert c.data["suspects"][0]["statement"][:40] not in text


def test_names_file_and_find_know_every_suspect():
    mod = _tool()
    names = mod.name_map()
    for c in content.all_cases():
        for s in c.data["suspects"]:
            first = mod._name_parts(s["name"])[0]
            assert c.id in names["first"][first]


def test_next_slots_follow_the_last_files():
    mod = _tool()
    slots = mod.next_slots()
    last = content.all_cases()[-1]
    assert slots["nightly"][0]["number"] == last.number + 1
    assert slots["nightly"][0]["publish"] == (last.publish + timedelta(days=1)).isoformat()
    assert slots["nightly"][1]["publish"] == (last.publish + timedelta(days=2)).isoformat()
    w = content.weekly_cases()[-1]
    assert slots["weekend"]["publish"] == (w.publish + timedelta(days=7)).isoformat()
    assert date.fromisoformat(slots["weekend"]["publish"]).weekday() == 3, "a weekend case publishes on a Thursday"
    json.dumps(slots, ensure_ascii=False)


def test_check_case_passes_for_the_recent_cases_and_catches_a_broken_one(tmp_path):
    """The writer's fast check agrees with CI on the newest files, and reports (not raises) a missing file."""
    spec = importlib.util.spec_from_file_location("check_case", TOOL.with_name("check_case.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for cid in ("c068", "c069", "c070", "w007"):
        problems, _notes = mod.check(cid)
        assert problems == [], (cid, problems)
    problems, _ = mod.check("c999")
    assert problems and "does not exist" in problems[0]
    d = mod.public_copy("w007", day1=True, reactions=False)
    assert "solution" not in d and "hints" not in d and "night1" not in d
    assert all(s.get("appears_chapter", 0) == 0 for s in d["suspects"]) and len(d["chapters"]) == 1
