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


def test_portraits_exist_in_the_app():
    """A suspect may name a painted portrait; the file must be shipped in the app."""
    from pathlib import Path

    folder = Path(__file__).resolve().parents[2] / "app" / "assets" / "portraits"
    for c in content.all_cases():
        for s in c.data["suspects"]:
            name = s["avatar"].get("portrait")
            if name:
                assert (folder / f"{name}.webp").exists(), f"{c.id}/{s['id']}: no portrait {name}"


def test_notify_plan_and_texts():
    import json
    from datetime import timedelta

    from app import content

    texts = json.loads((content.Path(content.__file__).parent / "content" / "notify.json").read_text(encoding="utf-8"))
    ids = {c.id for c in content.all_cases()}
    assert ids <= set(texts), "every nightly case needs a notification teaser in content/notify.json"
    heads = [t["head"] for t in texts.values()]
    assert len(set(heads)) == len(heads), "teaser titles must all be different"
    c = content.all_cases()[20]
    now = content.opens_at(c) - timedelta(hours=2)
    plan = content.notify_plan(now, days=3)
    first = next(x for x in plan if x["kind"] == "nightly")
    assert first["at"] == int(content.opens_at(c).timestamp()) and first["head"] and first["body"] and first["late"]
    assert [x["at"] for x in plan] == sorted(x["at"] for x in plan)


def test_every_suspect_has_a_valid_neutral_intro():
    banned = ("انگیزه", "دروغ", "بدهی", "قاتل", "مجرم", "مشکوک", "راز ")
    groups = [content.all_cases(), content.weekly_cases(), content.story_chapters()]
    n = 0
    for cases in groups:
        for c in cases:
            for s in c.data["suspects"]:
                intro = s["intro"]
                assert content.INTRO_MIN <= len(intro) <= content.INTRO_MAX, f"{c.id}/{s['id']}: {len(intro)}"
                assert not any(w in intro for w in banned), f"{c.id}/{s['id']}: {intro}"
                assert "intro" in c.public()["suspects"][0]
                n += 1
    assert n >= 260


def test_a_suspect_without_intro_is_refused():
    import copy

    import pytest
    d = copy.deepcopy(content.all_cases()[0].data)
    del d["suspects"][0]["intro"]
    with pytest.raises(content.CaseError):
        content.validate(d)
    d["suspects"][0]["intro"] = "کوتاه"
    with pytest.raises(content.CaseError):
        content.validate(d)


def test_every_case_has_a_known_category_and_all_are_used():
    from app.content import CATEGORIES
    cats = Counter(c.data.get("category") for c in [*content.all_cases(), *content.weekly_cases()])
    assert None not in cats, "every case sets a category (docs/case-writing-rules.md §9)"
    assert set(cats) <= set(CATEGORIES)
    assert set(cats) == set(CATEGORIES), "all seven categories have at least one case"
    assert all(name and icon for name, icon in CATEGORIES.values())


def test_unknown_category_is_refused_and_empty_is_allowed_for_old_files():
    import copy

    import pytest
    d = copy.deepcopy(content.all_cases()[0].data)
    d["category"] = "nope"
    with pytest.raises(content.CaseError):
        content.validate(d)
    del d["category"]
    content.validate(d)  # optional: old files and old clients keep working
    assert content.Case(id="x", number=1, publish=content.all_cases()[0].publish, data=d).summary()["category"] == ""


async def test_category_in_the_case_list_and_detail(client, monkeypatch):
    from .conftest import new_player
    when = content.opens_at(content.by_id("c040")) + timedelta(hours=1)
    monkeypatch.setattr(content, "now_local", lambda: when)
    p = await new_player(client, "category-1")
    cs = (await client.get("/v1/cases", headers=p["headers"])).json()
    assert cs["today"]["category"] in content.CATEGORIES
    detail = (await client.get(f"/v1/cases/{cs['today']['id']}", headers=p["headers"])).json()
    assert detail["case"]["category"] == cs["today"]["category"]
