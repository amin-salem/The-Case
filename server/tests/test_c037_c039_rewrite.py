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


def test_c037_rounded_weights_do_not_uniquely_pick_a_destination():
    gifts, empty_box = numbers(clue("c037", "e1"))[:2]
    rounding_step, error, *readings = numbers(clue("c037", "e2"))
    assert rounding_step == 2 * error
    # Room numbers appear before each pair of readings in the actual card.
    flower_gross, flower_base, room_a, a_gross, a_base, room_b, b_gross, b_base = readings
    assert (room_a, room_b) == (12, 18)
    assert flower_gross == flower_base
    device = numbers(clue("c037", "e8"))[0]
    for excess in (a_gross - a_base, b_gross - b_base):
        assert excess - 2 * error <= gifts + empty_box <= excess + 2 * error
        assert excess - 2 * error <= device <= excess + 2 * error
    assert gifts + empty_box != device
    # The recovered return bags do not identify a room: the load capacity must.
    # Even the maximum possible gross room-18 load cannot contain both items.
    assert device + gifts + empty_box > b_gross + error
    assert gifts + empty_box > flower_gross + error
    assert "در سبد دیگر قابل تشخیص از هم نبوده‌اند" in clue("c037", "e3")
    assert "برچسبِ اتاق نخورده" in clue("c037", "e3")
    # Amount equality is not serial-number provenance; the public cards must
    # agree on the specifically traceable subset, not pretend to trace all cash.
    serial_in = numbers(clue("c037", "e1"))[-3:]
    serial_out = numbers(clue("c037", "e9"))[-3:]
    assert serial_in == serial_out
    assert serial_in[2] - serial_in[1] + 1 == 50
    assert 50 * 100_000 < 260_000_000


def test_c038_actual_submission_stack_maps_all_three_requests():
    text = clue("c038", "e2")
    window = re.search(r"میزِ پنجره به ترتیب (.*?)؛", text).group(1).split("، ")
    door = re.search(r"میزِ در به ترتیب (.*?)\.", text).group(1).split("، ")
    first, second, last = numbers(clue("c038", "e3"))
    assert second == first + 1 and last - first + 1 == len(window) + len(door)
    order = []
    while window or door:
        if window:
            order.append(window.pop())
        if door:
            order.append(door.pop())
    papers = dict(enumerate(order, first))
    assert papers[43] == "آرمین"
    assert papers[45] == "یاسمن" and papers[46] == "کسری"
    # Each registered adjustment is exactly its authenticated request; the
    # request, not the shared login, is the source of the fabricated six points.
    # Equal increases deliberately avoid revealing Armin's code from the
    # opening's 12->18 alone. Stack reconstruction is required.
    assert numbers(clue("c038", "e5")) == [20, 15, 43, 6, 45, 6, 46, 6]
    assert numbers(clue("c038", "e6")) == [10, 16, 9, 15]
    assert 12 + 6 == 18 and 10 + 6 == 16 and 9 + 6 == 15


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
