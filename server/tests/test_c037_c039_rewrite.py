"""Authoring checks against the actual Persian clues, not a second fact fixture.

These check arithmetic/numbering and publication compatibility. They cannot
establish narrative difficulty or replace a public-only human/agent solve.
"""
import re
from math import prod
from datetime import date

import pytest

from app import content


def clue(case_id, evidence_id):
    return next(e["text"] for e in content.by_id(case_id).data["evidence"] if e["id"] == evidence_id)


def numbers(text):
    # Python int accepts Persian digits; no English-only parallel fact sheet.
    return [int(n) for n in re.findall(r"\d+", text)]


@pytest.mark.parametrize("number,publish,scene,category", [
    (37, date(2026, 11, 4), "wedding", "travel"),
    (38, date(2026, 11, 5), "school", "crime"),
    (39, date(2026, 11, 6), "airport", "travel"),
])
def test_rewrite_keeps_publication_and_supported_nightly_contract(number, publish, scene, category):
    c = content.by_id(f"c{number:03}")
    d = c.data
    assert c.number == number and c.publish == publish
    assert (d["scene"], d["category"], d["difficulty"]) == (scene, category, 4)
    assert content.opens_at(c).isoformat() == f"{publish}T21:00:00+03:30"
    content.validate(d)
    assert len(d["suspects"]) == 5
    assert len(d["evidence"]) == 9
    assert len({s["avatar"]["portrait"] for s in d["suspects"]}) == 5
    assert "ناصری" not in str(d)
    assert "solution" not in c.public() and "hints" not in c.public()
    culprit = next(s for s in d["suspects"] if s["id"] == c.culprit)
    assert all(culprit["name"] not in h for h in d["hints"])
    assert {e["type"] for e in d["evidence"]} <= {"object", "document", "witness", "cctv"}


def _minutes(hhmm):
    h, m = hhmm.split(":")
    t = int(h) * 60 + int(m)
    return t + 24 * 60 if t < 6 * 60 else t  # after midnight belongs to the same wedding night


def _times(text):
    return [_minutes(x) for x in re.findall(r"\d+:\d+", text)]


def test_c037_glitter_window_and_room_log_agree():
    last_seen = _times(clue("c037", "e1"))[-2]          # 23:02, lights out
    shot = _times(clue("c037", "e2"))[0]                # 23:15 glitter
    assert last_seen < shot
    log = clue("c037", "e5")
    room12 = _times(log.split("اتاقِ ۱۲")[1].split("اتاقِ ۱۸")[0])
    room18 = _times(log.split("اتاقِ ۱۸")[1].split("خودِ درِ خدمات")[0])
    assert last_seen < room12[0] < shot                 # the culprit's room opens inside the true window
    assert all(t > shot for t in room18)                # the false trail is after the window
    film = _times(clue("c037", "e6"))
    assert film[0] <= last_seen and film[1] >= shot
    assert "یک‌دست آبی" in clue("c037", "e4") and "روبالشی" in clue("c037", "e4")
    assert "پنج مظنون" in content.by_id("c037").data["intro"]


def test_c038_stack_order_reverses_writing_order():
    written = re.findall(r"(\d+:\d+) (\S+) فرم داد", clue("c038", "e3"))
    writers = [w for _, w in sorted(written, key=lambda x: _minutes(x[0]))]
    assert writers == ["مرادی", "راستی", "رحیمی"]
    entered = [int(n) for n in re.findall(r"برگه‌ی (\d+)، ۶\+", clue("c038", "e5"))]
    assert entered == [45, 46, 43]
    # each new form went on top, the stack was entered from the top: last written = first entered
    owner = dict(zip(entered, reversed(writers)))
    assert owner[43] == "مرادی" and owner[45] == "رحیمی" and owner[46] == "راستی"
    assert "۴۳" in clue("c038", "e1") and "آرمین" in clue("c038", "e1")
    assert all(n in numbers(clue("c038", "e2")) for n in (10, 16, 9, 15))
    assert content.by_id("c038").culprit == "s1"


def test_c039_cash_impossible_at_entry_even_at_worst_scale_tolerances():
    gross, trolley, suitcase_a, suitcase_b, error, shell, contents, sample_count, sample_weight, sample_error = numbers(clue("c039", "e1"))
    # The raw measurement sheet and human manifest are distinct sources.
    assert '«الف» چمدان بزرگ، «ب» چمدان کوچک و «پ» کیف دستی' in clue("c039", "e2")
    assert 'با بارِ «پ»' in clue("c039", "e3")
    handbag = gross - trolley - suitcase_a - suitcase_b
    max_handbag = handbag + 4 * error
    claim = content.by_id("c039").data["suspects"][1]["statement"]
    assert "پنج‌هزار اسکناس صد‌هزارتومنی" in claim
    min_cash = 5000 // sample_count * (sample_weight - sample_error)
    assert min_cash > max_handbag
    assert contents + shell == handbag
    assert min_cash + shell - error > max_handbag
    # Equal mass does not establish equal contents. The case uses separate
    # custody before the scale to attribute the provable large cash deficit.
    assert "دوربینِ سالن زیپ کیف را پیوسته نشان نمی‌دهد" in clue("c039", "e5")
    assert "راه ورود به آن فقط همین زیپ" in clue("c039", "e3")
    # Five measured, wrapped bundles fit the helper's observed tote without
    # assuming an unseen exit or accomplice.
    dimensions = numbers(clue("c039", "e4"))[-3:]
    assert 5 * prod(dimensions) / 1000 == 10  # cm³ -> litres
    assert "دوازده لیتر" in clue("c039", "e5")
