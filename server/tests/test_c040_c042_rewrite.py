"""Public clue invariants; these do not replace a blind narrative solve."""
import re
from datetime import date

import pytest

from app import content


def clue(case_id, eid):
    return next(e["text"] for e in content.by_id(case_id).data["evidence"] if e["id"] == eid)


@pytest.mark.parametrize("number,publish,scene,category,count", [
    (40, date(2026, 11, 7), "tower", "crime", 6),
    (41, date(2026, 11, 8), "bazaar_night", "business", 5),
    (42, date(2026, 11, 9), "office", "business", 5),
])
def test_rewrite_retains_opening_and_supported_contract(number, publish, scene, category, count):
    c = content.by_id(f"c{number:03}")
    content.validate(c.data)
    assert (c.number, c.publish, c.data["scene"], c.data["category"]) == (number, publish, scene, category)
    assert content.opens_at(c).isoformat() == f"{publish}T21:00:00+03:30"
    assert len(c.data["suspects"]) == count
    assert len(c.proof) <= len(c.data["evidence"]) // 2
    assert "ناصری" not in str(c.data)
    assert "solution" not in c.public() and "hints" not in c.public()
    # The new narrative must not leave old decisive observations in paid tools.
    for suspect in c.data["suspects"]:
        for tool in ("camera", "print"):
            assert 20 <= len(suspect[tool]) <= 160


def test_c042_disk_to_chassis_to_borrower_mapping_uses_post_repair_state():
    repair = clue("c042", "e3")
    pairs = re.findall(r"دیسک د(\d+) داخل بدنهٔ (\d+)", repair)
    disk_to_body = {int(disk): int(body) for disk, body in pairs}
    assert len(disk_to_body) == 2
    receipt = clue("c042", "e4")
    recipients = {int(body): name for body, name in re.findall(r"بدنهٔ (\d+) به (محسن|ساناز)", receipt)}
    disk = int(re.search(r"روی دیسک «د(\d+)»", clue("c042", "e2")).group(1))
    culprit = next(s for s in content.by_id("c042").data["suspects"] if s["id"] == content.by_id("c042").culprit)
    assert recipients[disk_to_body[disk]] in culprit["name"]
    # The pre-repair label points to someone else: omitting the swap is wrong.
    before = int(re.search(r"بدنهٔ (\d+)، برچسبِ روی در «محسن»، پیش از تعمیر دیسک د۴۱", repair).group(1))
    assert recipients[before] not in culprit["name"]


def test_c042_final_attachment_exists_before_mutation_but_after_initial_draft():
    events = re.findall(r"(\d{2}):(\d{2})", clue("c042", "e2"))
    created, delivered, modified = [60 * int(h) + int(m) for h, m in events]
    release = re.search(r"نغمه در (\d{2}):(\d{2})", clue("c042", "e6"))
    released = 60 * int(release[1]) + int(release[2])
    assert created < released < modified < delivered
    assert "R4-71" in clue("c042", "e1") and "R4-71" in clue("c042", "e6")
