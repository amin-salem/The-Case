"""The case files themselves: 50 cases, one new case a night, mostly difficulty 4."""
from collections import Counter
from datetime import timedelta

from app import content


def test_fifty_cases_with_unique_ids_and_a_nightly_schedule():
    cases = content.all_cases()
    assert len(cases) == 50
    assert [c.number for c in cases] == list(range(1, 51))
    assert len({c.id for c in cases}) == 50
    for a, b in zip(cases, cases[1:]):
        assert b.publish - a.publish == timedelta(days=1), f"{a.id} -> {b.id}: one case per night, no gaps"


def test_mostly_difficulty_four():
    levels = Counter(c.data["difficulty"] for c in content.all_cases())
    assert levels[4] >= 30
    assert levels[4] > sum(v for k, v in levels.items() if k != 4)


def test_scenes_are_varied_and_known():
    scenes = Counter(c.data["scene"] for c in content.all_cases())
    assert set(scenes) <= content.SCENES
    assert len(scenes) == 20          # every theme is used
    assert max(scenes.values()) <= 4  # and none is repeated too often


def test_every_case_is_well_formed():
    for c in content.all_cases():
        d = c.data
        sids = {s["id"] for s in d["suspects"]}
        eids = {e["id"] for e in d["evidence"]}
        assert c.culprit in sids
        assert c.proof <= eids and c.proof
        assert len(d["hints"]) == 3
        assert len({s["name"] for s in d["suspects"]}) == len(sids), f"{c.id}: two suspects with the same name"
        # the culprit must not be the only suspect whose motive is blank
        assert all(s["motive"] and s["statement"] for s in d["suspects"])
        assert len(d["explanation"] if "explanation" in d else d["solution"]["explanation"]) > 80
        # the public copy never leaks the answer
        pub = str(c.public())
        assert "explanation" not in pub and '"culprit"' not in pub


def test_proof_is_not_everything():
    """A player must have to choose: at most half of the evidence may count as proof."""
    for c in content.all_cases():
        assert len(c.proof) <= max(1, len(c.data["evidence"]) // 2), c.id
