"""The case files themselves: 94 cases, one new case a night, mostly difficulty 4."""
from collections import Counter
from datetime import timedelta

from app import content


def test_fifty_cases_with_unique_ids_and_a_nightly_schedule():
    cases = content.all_cases()
    assert len(cases) == 94
    assert [c.number for c in cases] == list(range(1, 95))
    assert len({c.id for c in cases}) == 94
    for a, b in zip(cases, cases[1:]):
        assert b.publish - a.publish == timedelta(days=1), f"{a.id} -> {b.id}: one case per night, no gaps"


def test_mostly_difficulty_four():
    levels = Counter(c.data["difficulty"] for c in content.all_cases())
    assert levels[4] >= 30
    assert levels[4] > sum(v for k, v in levels.items() if k != 4)


def test_nightly_from_95_is_never_very_hard():
    # Amin, 26 Nov 2026: very hard (5) stays for weekend cases; nightly c095+ is hard (4) or medium (3)
    for c in content.all_cases():
        if int(c.data["number"]) >= 95:
            assert c.data["difficulty"] in (3, 4), c.data["id"]


def test_scenes_are_varied_and_known():
    scenes = Counter(c.data["scene"] for c in content.all_cases())
    assert set(scenes) <= content.SCENES
    assert len(scenes) == 20          # every theme is used
    # and none is repeated too often (5 since c063/c064: the idea bank fixes each case's scene, docs/case-ideas-batch1.md)
    assert max(scenes.values()) <= 6


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


def test_age_must_be_a_number_in_every_case_and_weekend_case():
    """29 Oct 2026: w004 stored ages as text and the app showed every suspect as «۰ ساله»."""
    import copy

    import pytest
    for c in (*content.all_cases(), *content.weekly_cases()):
        for s in c.data["suspects"]:
            assert isinstance(s["age"], int) and not isinstance(s["age"], bool) and 10 <= s["age"] <= 99, (c.id, s["id"])
    d = copy.deepcopy(content.all_cases()[0].data)
    for bad in ("49", None, 0, 150, True, 49.5):
        d["suspects"][0]["age"] = bad
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


def test_culprit_portraits_are_unique():
    """The culprit album must not show a face twice while an unused face of that gender is still in the app (docs/case-writing-rules.md §8)."""
    from pathlib import Path
    root = Path(__file__).resolve().parents[2] / "app" / "assets" / "portraits"
    if not root.is_dir():
        return
    pool = {p.stem for p in root.glob("*.webp")}
    count: Counter = Counter()
    for c in (*content.all_cases(), *content.weekly_cases()):
        s = next(x for x in c.data["suspects"] if x["id"] == c.culprit)
        p = s["avatar"].get("portrait")
        if p in pool:  # a portrait drawn by code is unique by construction
            count[p] += 1
    for g in ("m", "f"):
        reused = sorted(p for p, n in count.items() if p[0] == g and n > 1)
        unused = sorted(p for p in pool if p[0] == g and p not in count)
        assert not (reused and unused), f"culprit faces reused ({reused}) while unused {g} faces exist ({unused}); spread them"


def test_portrait_age_matches_the_character():
    """A face must look the age of the character (Amin, 26 Oct 2026: a 59-year-old had a 30-year-old face).
    docs/portrait-ages.json holds the apparent age of every face; young = up to 35, mid = 32-54, old = 50 and up.
    The male old faces are still too few (see docs/case-writing-rules.md §8), so a handful of near misses is allowed;
    the number may only go down."""
    import json
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    ages = json.loads((root / "docs" / "portrait-ages.json").read_text(encoding="utf-8"))
    shipped = {p.stem for p in (root / "app" / "assets" / "portraits").glob("*.webp")}
    assert shipped == set(ages), f"portrait-ages.json out of date: {sorted(shipped ^ set(ages))}"
    lo_hi = {"young": (0, 35), "mid": (32, 54), "old": (50, 99)}
    misses = []
    for c in (*content.all_cases(), *content.weekly_cases()):
        for s in c.data["suspects"]:
            p = s["avatar"].get("portrait")
            if p in ages:
                lo, hi = lo_hi[s["avatar"]["age"]]
                if not lo <= ages[p] <= hi:
                    misses.append((c.id, s["id"], s["avatar"]["age"], p))
    assert len(misses) <= 8, misses


def test_case_uses_only_portraits_players_have():
    """A new portrait lives in the APK; a player who has not updated sees a drawn fallback face (w005, Nov 2026). So a case
    may use a portrait only once the build that ships it is recorded in docs/portrait-release.json (first_build and usable_from set).
    Since 18 Nov 2026 the date itself no longer matters: the minimum app version is raised to that build."""
    import json
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    rel = json.loads((root / "docs" / "portrait-release.json").read_text(encoding="utf-8"))
    shipped = {p.stem for p in (root / "app" / "assets" / "portraits").glob("*.webp")}
    assert set(rel["portraits"]) <= shipped, "portrait-release.json lists a portrait that is not shipped"
    early = []
    for c in (*content.all_cases(), *content.weekly_cases()):
        day = c.publish.isoformat()
        if day < rel["check_from"]:
            continue
        for s in c.data["suspects"]:
            p = s["avatar"].get("portrait")
            if p in rel["portraits"] and (
                rel["portraits"][p].get("first_build") is None
                or not rel["portraits"][p].get("usable_from")
            ):
                early.append((c.id, day, s["id"], p, rel["portraits"][p]["usable_from"]))
    assert not early, f"these cases use a portrait most players do not have yet: {early}"
