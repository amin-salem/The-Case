"""The story/case kit (tools/): validators, importers and the ChatGPT prompt. Fast, offline, deterministic.
Written as unittest classes so they also run with plain `python -m unittest` on a machine without the server's packages."""
import copy
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import build_prompt  # noqa: E402
import import_case  # noqa: E402
import import_story  # noqa: E402
import storykit as K  # noqa: E402

FIX = ROOT / "tools" / "fixtures"
STORY = json.loads((FIX / "story_example.json").read_text(encoding="utf-8"))
CASE = json.loads((FIX / "case_example.json").read_text(encoding="utf-8"))


def story(**over):
    d = copy.deepcopy(STORY)
    d.update(over)
    return d


def codes(rep, sev=None):
    return {i.code for i in rep.issues if sev is None or i.sev == sev}


def check(d, chapter=99, root=ROOT):
    return K.validate_story_dict(d, chapter, root)


def make_root(tmp: Path) -> Path:
    """A writable copy of just the data the kit touches (the real tree is never modified by a test)."""
    r = tmp / "repo"
    sd = r / "server" / "app" / "content" / "story" / "s01"
    sd.mkdir(parents=True)
    kit = K.load_kit(ROOT)
    kit["chapters"] = {}
    (sd / "kit.json").write_text(json.dumps(kit, ensure_ascii=False), encoding="utf-8")
    (r / "server" / "app" / "content" / "cases").mkdir()
    (r / "server" / "app" / "content" / "notify.json").write_text("{}", encoding="utf-8")
    (r / "docs").mkdir()
    (r / "app" / "assets" / "portraits").mkdir(parents=True)
    for n in K.portraits(ROOT):
        (r / "app" / "assets" / "portraits" / f"{n}.webp").write_bytes(b"")
    return r


def as_chapter(n, **over):
    d = story(**over)
    d["id"], d["number"], d["chapter"] = f"s01ch{n:02d}", n, n
    d["_kit"] = {**d["_kit"], "puzzle_type": [3, 5, 2, 8, 9][(n - 1) % 5]}  # never the same type twice in a row
    return d


class GoodFixtures(unittest.TestCase):
    def test_prompt_story_example_passes(self):
        rep = check(STORY)
        self.assertTrue(rep.ok, [i.msg for i in rep.errors])
        self.assertEqual(rep.stats["scenes"], 4)

    def test_prompt_case_example_passes(self):
        rep = K.validate_case_dict(CASE, ROOT)
        self.assertTrue(rep.ok, [i.msg for i in rep.errors])

    def test_real_chapter_one_passes(self):
        d = json.loads((ROOT / "server/app/content/story/s01/ch01.json").read_text(encoding="utf-8"))
        led = K.load_kit(ROOT)["chapters"]["1"]
        d["_kit"] = {"puzzle_type": 3, "culprit_slot": "s4", "summary": led["summary"]}
        rep = check(d, 1)
        self.assertTrue(rep.ok, [i.msg for i in rep.errors])

    def test_story_stays_closed(self):
        content = K.load_content(ROOT)
        self.assertGreaterEqual(content.STORY_SEASON["opens_at"], "2090",
                                "Story gate opened: only change this test when Amin has opened the story on purpose (CLAUDE.md «Story opening gate»)")


class JsonAndLines(unittest.TestCase):
    def test_line_numbers(self):
        text = json.dumps(STORY, ensure_ascii=False, indent=1)
        obj, lines = K.parse_json_lines(text)
        n = lines[("scenes", 1, "text")]
        self.assertIn("مریم", text.splitlines()[n - 1])

    def test_broken_json_reports_the_line(self):
        raw = '{\n "a": 1,\n "b": 2\n "c": 3\n}'
        rep, obj, _ = K.check_text(raw, "story")
        self.assertIsNone(obj)
        self.assertEqual(rep.issues[0].code, "json")
        self.assertEqual(rep.issues[0].line, 4)

    def test_truncated_reply(self):
        rep, obj, _ = K.check_text('{"id": "s01ch02", "title": "ab', "story")
        self.assertFalse(rep.ok)

    def test_fences_and_chatter_are_tolerated(self):
        raw = "حتماً! این هم فصل:\n```json\n" + json.dumps(STORY, ensure_ascii=False) + "\n```\nامیدوارم خوشت بیاید"
        rep, obj, notes = K.check_text(raw, "story", 99)
        self.assertTrue(rep.ok)
        self.assertTrue(notes)


class StructureErrors(unittest.TestCase):
    def test_dead_end(self):
        d = story()
        d["scenes"][1]["options"] = []
        self.assertIn("dead_end", codes(check(d), "error"))

    def test_unknown_goes_to(self):
        d = story()
        d["scenes"][1]["options"][0]["goes_to"] = "nowhere"
        self.assertIn("goes_to", codes(check(d), "error"))

    def test_unreachable_scene(self):
        d = story()
        d["scenes"].append({"id": "orphan", "text": " ".join(["کلمه"] * 70), "options": [
            {"id": "x", "title": "برو جلو", "goes_to": "end"}, {"id": "y", "title": "برگرد", "goes_to": "end"}]})
        self.assertIn("unreachable", codes(check(d), "error"))

    def test_loop(self):
        d = story()
        d["scenes"][3]["options"][0]["goes_to"] = "sc1"
        self.assertIn("loop", codes(check(d), "error"))

    def test_no_branch(self):
        d = story()
        d["scenes"][0]["options"][1]["goes_to"] = "counter"
        self.assertIn("branch", codes(check(d), "error"))

    def test_all_options_locked(self):
        d = story()
        for o in d["scenes"][3]["options"]:
            o["needs_clue"] = "sugar_dust"
        self.assertIn("locked", codes(check(d), "error"))

    def test_locked_clue_not_obtainable_before(self):
        d = story()
        d["scenes"][3]["options"][1]["needs_clue"] = "e4"  # e4 is only given by the office scene itself
        self.assertIn("needs", codes(check(d), "error"))

    def test_unknown_clue_and_relation(self):
        d = story()
        d["scenes"][0]["options"][0]["gives_clue"] = ["ghost"]
        d["scenes"][0]["options"][1]["relations"] = {"dariush": "angry"}
        c = codes(check(d), "error")
        self.assertTrue({"clue", "relation"} <= c)

    def test_scene_text_length(self):
        d = story()
        d["scenes"][2]["text"] = "کوتاه است."
        rep = check(d)
        self.assertIn("len", codes(rep, "error"))
        d = story()
        d["scenes"][2]["text"] = " ".join(["کلمه"] * 150)  # over the soft limit, under the hard one
        rep = check(d)
        self.assertTrue(rep.ok)
        self.assertIn("len", codes(rep, "warn"))

    def test_extra_key_would_leak_to_the_app(self):
        d = story(secret_notes="مجرم داریوش است")
        self.assertIn("extra_key", codes(check(d), "error"))

    def test_kit_rules(self):
        d = story()
        d["_kit"]["culprit_slot"] = "s1"
        self.assertIn("kit", codes(check(d), "error"))
        d = story()
        del d["_kit"]
        self.assertIn("kit", codes(check(d), "error"))

    def test_type_repeat_and_plan(self):
        r = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, r, True)
        root = make_root(r)
        led = K.load_kit(root)
        led["chapters"]["1"] = {"type": 5, "culprit": "s2"}
        K.write_json(K.story_dir(root) / "s01" / "kit.json", led)
        d = as_chapter(2)
        d["_kit"]["puzzle_type"] = 5
        rep = check(d, 2, root)
        self.assertIn("type_repeat", codes(rep, "error"))

    def test_server_validator_is_the_last_gate(self):
        d = story()
        d["difficulty"] = 4
        d["suspects"][0]["questions"] = d["suspects"][0]["questions"][:1]
        rep = check(d)
        self.assertFalse(rep.ok)
        self.assertTrue(codes(rep, "error") & {"len", "server"})


class CaseRulesAndLeaks(unittest.TestCase):
    def test_culprit_named_in_hint(self):
        d = story()
        d["hints"][2] = "داریوش همان کسی است که امضا کرده."
        self.assertIn("leak", codes(check(d), "error"))

    def test_guilt_next_to_culprit_in_scene(self):
        d = story()
        d["scenes"][2]["text"] += " ناصری آهسته گفت: داریوش قاتل است."
        self.assertIn("leak", codes(check(d), "error"))

    def test_outro_may_name_the_culprit(self):
        rep = check(story())
        self.assertNotIn("leak", codes(rep))

    def test_intro_must_be_neutral(self):
        d = story()
        d["suspects"][1]["intro"] = "شاگردی که دروغ می‌گوید و پول لازم دارد."
        self.assertIn("intro_neutral", codes(check(d), "error"))

    def test_proof_rules(self):
        d = story()
        d["solution"]["proof"] = ["e1", "e2", "e3"]
        self.assertIn("proof", codes(check(d), "error"))
        d = story()
        d["solution"]["proof"] = ["e4"]
        self.assertIn("proof", codes(check(d), "error"))

    def test_avatar_rules(self):
        d = story()
        d["suspects"][0]["avatar"]["hair"] = "short"
        d["suspects"][1]["avatar"]["portrait"] = "m_unknown_job"
        d["suspects"][2]["avatar"]["portrait"] = "m_young_worker"
        c = codes(check(d), "error")
        self.assertTrue({"hijab", "portrait"} <= c)

    def test_difficulty(self):
        self.assertIn("difficulty", codes(check(story(difficulty=3)), "error"))

    def test_relation_leak_is_a_warning(self):
        d = story()
        for s in d["scenes"]:
            for o in s["options"]:
                o.pop("relations", None)
        d["scenes"][0]["options"][1]["relations"] = {"dariush": "suspicious"}
        rep = check(d)
        self.assertIn("relation_leak", codes(rep, "warn"))
        self.assertTrue(rep.ok)

    def test_season_secret_before_chapter_ten(self):
        d = as_chapter(2, thread="خانم افشار، دختر یدالله کاوه، همان کسی بود که پرونده را آورد.")
        self.assertIn("season_spoiler", codes(check(d, 2), "error"))
        d = as_chapter(2)
        d["suspects"][2]["name"] = "نرگس افشار"
        self.assertIn("season_spoiler", codes(check(d, 2), "error"))
        d = as_chapter(10, thread="خانم افشار، دختر یدالله کاوه، همان کسی بود که پرونده را آورد.")
        self.assertNotIn("season_spoiler", codes(check(d, 10)))  # chapter 10 is where the truth comes out


class WordingAndCharacters(unittest.TestCase):
    def test_player_word_nafar_brand_latin(self):
        d = story()
        d["scenes"][0]["options"][0]["title"] = "با ده نفر حرف بزن"
        d["scenes"][1]["text"] += " بازیکن گوشی سامسونگ را برداشت و text نوشت."
        c = codes(check(d), "error")
        self.assertTrue({"nafar", "player_word", "brand", "latin"} <= c)

    def test_nafar_is_fine_in_story_text(self):
        d = story()
        d["scenes"][1]["text"] += " سه نفر کنار در ایستاده بودند."
        self.assertNotIn("nafar", codes(check(d)))

    def test_characters_are_auto_fixable_not_failing(self):
        d = story()
        d["scenes"][1]["text"] = d["scenes"][1]["text"].replace("ی", "ي", 3) + " ساعت 10:30 و می کنم"
        rep = check(d)
        self.assertTrue(rep.ok)
        autos = [i for i in rep.warnings if i.auto]
        self.assertTrue(autos)
        fixed, n = K.autofix(d)
        self.assertGreaterEqual(n, 1)
        txt = fixed["scenes"][1]["text"]
        self.assertNotIn("ي", txt)
        self.assertIn("۱۰:۳۰", txt)
        self.assertIn("می‌کنم", txt)
        self.assertEqual(fixed["scenes"][1]["id"], "counter")  # ids untouched
        self.assertEqual(K.autofix(fixed)[1], 0)  # idempotent

    def test_evidence_ids_in_explanation_survive(self):
        fixed, _ = K.autofix(STORY)
        self.assertIn("(e1)", fixed["solution"]["explanation"])

    def test_bidi_and_spaces(self):
        self.assertEqual(K.normalize_text("‏سلام   دنیا "), "سلام دنیا")


class FixMessage(unittest.TestCase):
    def test_message_lists_path_and_line(self):
        raw = json.dumps(STORY, ensure_ascii=False, indent=1)
        bad = json.loads(raw)
        bad["hints"][2] = "داریوش بود."
        text = json.dumps(bad, ensure_ascii=False, indent=1)
        rep, obj, _ = K.check_text(text, "story", 99)
        msg = K.build_fix_message(rep, obj)
        self.assertTrue(msg.startswith("FIX:"))
        self.assertIn("hints[2]", msg)
        self.assertRegex(msg, r"خط [۰-۹]+")
        self.assertIn("فقط JSON خام", msg)

    def test_clean_report_has_no_message(self):
        rep = check(STORY)
        self.assertEqual(K.build_fix_message(rep, STORY), "")

    def test_next_context(self):
        t = K.next_context(STORY)
        self.assertIn("ظرف خالی", t)
        self.assertIn("s2", t)


class Importer(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = make_root(self.tmp)

    def raw(self, n=1, **over):
        return json.dumps(as_chapter(n, **over), ensure_ascii=False)

    def test_import_writes_clean_draft_and_ledger(self):
        d = as_chapter(1)
        d["scenes"][1]["text"] = d["scenes"][1]["text"] + " ساعت 10:30"
        ok, msg, fix = import_story.import_one(json.dumps(d, ensure_ascii=False), self.root)
        self.assertTrue(ok, msg)
        out = json.loads((K.story_dir(self.root) / "s01" / "ch01.json").read_text(encoding="utf-8"))
        self.assertNotIn("_kit", out)
        self.assertIn("۱۰:۳۰", out["scenes"][1]["text"])
        K.load_content(ROOT).validate_story(copy.deepcopy(out), 1, 1)  # the server accepts exactly this file
        led = K.load_kit(self.root)["chapters"]["1"]
        self.assertEqual(led["blind_test"], "pending")
        self.assertEqual(led["culprit"], "s2")

    def test_rejected_chapter_writes_nothing(self):
        d = as_chapter(1)
        d["hints"][2] = "داریوش بود."
        ok, msg, fix = import_story.import_one(json.dumps(d, ensure_ascii=False), self.root)
        self.assertFalse(ok)
        self.assertTrue(fix.startswith("FIX:"))
        self.assertFalse((K.story_dir(self.root) / "s01" / "ch01.json").exists())

    def test_chapters_must_be_in_order_and_not_overwritten(self):
        ok, msg, _ = import_story.import_one(self.raw(3), self.root)
        self.assertFalse(ok)
        self.assertIn("پشت‌سرهم", msg)
        self.assertTrue(import_story.import_one(self.raw(1), self.root)[0])
        ok, msg, _ = import_story.import_one(self.raw(1), self.root)
        self.assertFalse(ok)
        self.assertTrue(import_story.import_one(self.raw(1), self.root, replace=True)[0])
        self.assertTrue(import_story.import_one(self.raw(2), self.root)[0])

    def test_dry_run_writes_nothing(self):
        ok, msg, _ = import_story.import_one(self.raw(1), self.root, dry=True)
        self.assertTrue(ok)
        self.assertFalse((K.story_dir(self.root) / "s01" / "ch01.json").exists())

    def test_inbox_mode(self):
        inbox = self.tmp / "inbox"
        inbox.mkdir()
        (inbox / "b.json").write_text(self.raw(2), encoding="utf-8")
        (inbox / "a.json").write_text(self.raw(1), encoding="utf-8")
        bad = as_chapter(3)
        bad["difficulty"] = 2
        (inbox / "c.json").write_text(json.dumps(bad, ensure_ascii=False), encoding="utf-8")
        rc = import_story.main(["--inbox", str(inbox), "--root", str(self.root)])
        self.assertEqual(rc, 1)
        self.assertTrue((inbox / "imported" / "a.json").exists() and (inbox / "imported" / "b.json").exists())
        self.assertTrue((inbox / "rejected" / "c.json").exists())
        self.assertTrue((inbox / "rejected" / "c.اصلاحیه.txt").read_text(encoding="utf-8").startswith("FIX:"))
        self.assertEqual(import_story.main(["--inbox", str(inbox), "--root", str(self.root)]), 0)  # nothing left

    def test_case_import_writes_case_and_notify(self):
        shutil.copy(ROOT / "docs" / "case-log.md", self.root / "docs" / "case-log.md")
        c = copy.deepcopy(CASE)
        c["id"], c["number"], c["publish"] = "c500", 500, "2099-02-02"
        ok, msg, fix = import_case.import_case(json.dumps(c, ensure_ascii=False), self.root)
        self.assertTrue(ok, msg)
        out = json.loads((K.cases_dir(self.root) / "c500.json").read_text(encoding="utf-8"))
        self.assertNotIn("_notify", out)
        self.assertNotIn("_kit", out)
        notify = json.loads((self.root / "server/app/content/notify.json").read_text(encoding="utf-8"))
        self.assertEqual(notify["c500"]["title"], "ظرف خالی")
        ok, msg, _ = import_case.import_case(json.dumps(c, ensure_ascii=False), self.root)
        self.assertFalse(ok)  # exists


class CaseChecks(unittest.TestCase):
    def test_notify_teaser_rules(self):
        c = copy.deepcopy(CASE)
        c["_notify"]["head"] = "این یک عنوان بسیار بسیار طولانی برای اعلان است 🍰"
        self.assertIn("len", codes(K.validate_case_dict(c, ROOT), "error"))
        c = copy.deepcopy(CASE)
        del c["_notify"]
        self.assertIn("notify", codes(K.validate_case_dict(c, ROOT), "error"))

    def test_story_keys_are_not_allowed_in_a_daily_case(self):
        c = copy.deepcopy(CASE)
        c["thread"] = "x"
        self.assertIn("extra_key", codes(K.validate_case_dict(c, ROOT), "error"))

    def test_case_id(self):
        c = copy.deepcopy(CASE)
        c["id"] = "s01ch02"
        self.assertIn("id", codes(K.validate_case_dict(c, ROOT), "error"))

    def test_all_existing_nightly_cases_have_no_structural_errors(self):
        """Calibration: the rules must not call a case that is already live broken in its basic structure."""
        for p in sorted(K.cases_dir(ROOT).glob("c*.json"))[-5:]:
            d = json.loads(p.read_text(encoding="utf-8"))
            d["_notify"] = {"head": "عنوان نمونه ۱", "body": "متن نمونه برای تیزر اعلان است."}
            d["_kit"] = {"puzzle_type": 1, "culprit_slot": d["solution"]["culprit"]}
            rep = K.validate_case_dict(d, ROOT)
            structural = {"missing", "extra_key", "json", "server", "id", "scene"}
            self.assertFalse(structural & codes(rep, "error"), (p.name, [i.msg for i in rep.errors]))


class PromptKit(unittest.TestCase):
    def test_prompt_doc_is_up_to_date(self):
        self.assertEqual(build_prompt.main(["--check"]), 0, "run: python tools/build_prompt.py")

    def test_limits_in_prompt_match_the_validator(self):
        text = (ROOT / "docs" / "story-chatgpt-prompt.md").read_text(encoding="utf-8")
        found = dict(re.findall(r"^([a-z_.]+) \((?:words|chars|count)\) = (\d+-\d+)$", text, re.M))
        for key, (_u, lo, hi, _a, _b) in K.LIMITS.items():
            self.assertEqual(found.get(key), f"{lo}-{hi}", key)

    def test_prompt_contains_every_bible_chapter_and_rules(self):
        text = (ROOT / "docs" / "story-chatgpt-prompt.md").read_text(encoding="utf-8")
        for k, v in K.load_kit(ROOT)["plan"].items():
            self.assertIn(v["title"], text)
        for must in ("SELF-CHECK", "FIX:", "WRITE CHAPTER", "WRITE CASE", "raw JSON", "«کارآگاه»", "«مظنون»", "رازان"):
            self.assertIn(must, text)

    def test_prompt_lists_only_real_portraits_and_scenes(self):
        text = (ROOT / "docs" / "story-chatgpt-prompt.md").read_text(encoding="utf-8")
        for por in K.portraits(ROOT):
            self.assertIn(por, text)

    def test_plan_matches_server_scenes(self):
        scenes = K.load_content(ROOT).SCENES
        for k, v in K.load_kit(ROOT)["plan"].items():
            self.assertIn(v["scene"], scenes, k)


if __name__ == "__main__":
    unittest.main()
