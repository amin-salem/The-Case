#!/usr/bin/env python3
"""Builds docs/story-chatgpt-prompt.md (the copy-paste kit for ChatGPT) from its single sources of truth:

  * limits               -> tools/storykit.py LIMITS
  * season bible         -> docs/story-season1-bible.md
  * filled examples      -> tools/fixtures/story_example.json, case_example.json (both are tested to pass the validators)
  * scene ids / portraits -> server/app/content.py SCENES, app/assets/portraits

    python tools/build_prompt.py            # rewrite the doc
    python tools/build_prompt.py --check    # exit 1 if the doc is out of date (a test runs this)
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storykit as K  # noqa: E402

OUT = K.ROOT / "docs" / "story-chatgpt-prompt.md"
FENCE = "````"  # four backticks: the prompts contain no fences of their own

HEADER = """# بسته‌ی ChatGPT برای نوشتن فصل‌های داستان و پرونده‌های شبانه

> این فایل را **دست نزن**؛ با `python tools/build_prompt.py` از روی منبع‌هایش ساخته می‌شود
> (محدودیت‌ها از `tools/storykit.py`، بایبل از `docs/story-season1-bible.md`، نمونه‌ها از `tools/fixtures/`).
> یک تست مطمئن می‌شود فایل با منبع‌ها هم‌خوان است. گردش کار کامل: `docs/story-workflow.md`.

## ۳ خط برای استفاده
1. یک چت **تازه** در ChatGPT باز کن و «پرامپت ۱» را (از اولین خط تا آخرین خط داخل کادر) یک‌بار بچسبان. جوابش فقط باید «OK» باشد.
2. هر فصل را با یک پیام جدا بخواه: `WRITE CHAPTER 2` + بلوک `CONTEXT` (خلاصه‌ی فصل‌های قبل؛ خروجی «خلاصه برای پیام فصل بعد» اعتبارسنج). جواب را در `content_inbox/story/` ذخیره کن (مثلاً `ch02.json`).
3. `python tools/validate_story.py content_inbox/story/ch02.json --chapter 2` را اجرا کن؛ اگر رد شد، «پیام اصلاحیه» را در همان چت بچسبان. وقتی قبول شد، فایل در صندوق می‌ماند تا اجرای شبانه بررسی و ایمپورتش کند.

پرونده‌ی شبانه همین‌طور است ولی با «پرامپت ۲» و `python tools/validate_case.py`.

**چرا کوچک می‌ماند:** ChatGPT هیچ‌وقت فصل‌های قبل را کامل نمی‌بیند، فقط خلاصه‌ی چند خطی از `_kit` هر فصل را؛ هر پیام فقط یک فصل می‌نویسد.

---
"""

PART_ROLE = """You are the head writer of «پرونده» (“The Case”), a Persian-language mobile detective game for players in Iran.
Players are called «کارآگاه»; the people they investigate are «مظنون». Everything the player reads is Persian."""

PART_HOW = """## 0. HOW WE WORK (read first)
- I send ONE request per message. You answer with ONE raw JSON object and nothing else: no Markdown, no ``` fences, no comments, no trailing commas, no text before or after the JSON, no explanation, no “here is your chapter”.
- Request types:
  1. `WRITE CHAPTER N` followed by an optional `CONTEXT` block (a few lines per earlier chapter). Write that chapter, in the choices format below.
  2. `WRITE CASE cNNN publish YYYY-MM-DD type T` (second prompt only): write one nightly case.
  3. `FIX:` followed by a numbered list of problems found by my validator. Return the WHOLE corrected JSON; change only what the list says, keep every other id, order and text untouched. Run the SELF-CHECK again.
- You never get earlier chapters in full. Use the bible and the CONTEXT lines only; do not ask me for more, never ask questions, never write two chapters in one reply.
- The first time I paste this prompt, reply with exactly `OK`."""

PART_HOW_CASE = """## 0. HOW WE WORK (read first)
- I send ONE request per message. You answer with ONE raw JSON object and nothing else: no Markdown, no ``` fences, no comments, no trailing commas, no text before or after the JSON, no explanation.
- Request types:
  1. `WRITE CASE cNNN publish YYYY-MM-DD type T`: write that nightly case.
  2. `FIX:` followed by a numbered list of problems found by my validator. Return the WHOLE corrected JSON; change only what the list says, keep every other id, order and text untouched. Run the SELF-CHECK again.
- Never ask questions, never write two cases in one reply.
- The first time I paste this prompt, reply with exactly `OK`."""

PART_WORLD = """## 1. WORLD AND TONE
- Fictional city **رازان**: covered bazaar, harbour, old industrial quarter. All people, firms and places are invented. Contemporary Iran; nothing gory, no real brands, banks, apps, politicians, religious or political places.
- The player is a rookie detective. Partner: **سرگرد ناصری** — sharp, dry, a little sarcastic, spoken Persian (محاوره), few words, never explains the solution.
- Tone: warm noir, short sentences, concrete detail (smell, sound, hands), dry humour. Narration is clean written Persian; dialogue and suspects' statements are natural spoken Persian, every suspect sounds different (one curt, one talkative, one formal).
- Women always wear hijab (avatar hair = "hijab")."""

PART_CHOICES = """## 3. WHAT THE CHOICES DO (chapter = a case + 4–5 short scenes)
A chapter is a normal case (suspects, evidence, hints, solution) that the player reaches through **4–5 scenes**, each with 2–3 options. The scenes lead into the evidence; they never replace it.
- Choices CHANGE: which extra clues land on the case board (`gives_clue`), how people feel about the player (`relations`: unmet/neutral/friendly/suspicious — this carries over to later chapters), which locked options open (`needs_clue`), and the path through the scenes.
- Choices NEVER change: the culprit, the evidence cards, the solution, or whether the case can be solved. Every path keeps all evidence cards; the board only marks what the player noticed. No option is “right” or “wrong”.
- At least ONE scene must branch (two options with different `goes_to`). Scenes only move forward (no loops). The first scene starts the chapter. Every option path ends at the single `ending` scene (no options), after which the app opens interrogation and accusation. The `ending` text must NOT say how the case ends.
- Every scene keeps at least one option that is never locked. A locked option's clue must be obtainable in an earlier scene on some path.
- Scene text never reveals or hints at the culprit; option titles are short concrete actions («دفتر را بخوان»), never «درست/غلط»."""

PART_SCHEMA = """## 4. EXACT JSON FORMAT
Top-level keys (no others are allowed): id, number, season, chapter, difficulty, scene, title, location, intro, suspects, evidence, hints, solution, partner_intro, partner_outro_win, partner_outro_lose, thread, scenes, ending, board, _kit. (`partner_hints` = 3 hint texts in ناصری's voice is optional.)
- `id` "s01chNN", `number` = `chapter` = NN, `season` 1, `difficulty` 4 or 5, `scene` one of the SCENE IDS below (use the one the bible gives for this chapter).
- `suspects`: 5 suspects (6 at most), ids s1..s5; each: id, name, role, intro (20–90 chars, NEUTRAL: who they are, never motive/alibi/lie/secret/money trouble), age (number), avatar {gender "m"|"f", age young|mid|old, skin 0-3, hair, hairColor "#rrggbb", beard, glasses true|false, outfit "#rrggbb", accessory, portrait}, motive (only what EVERYONE believes — the real motive is found in the evidence), statement (spoken Persian), questions [{q, a}].
- `evidence`: ids e1..eN; each {id, type, title, text}.
- `hints`: exactly 3, increasingly strong; hint 3 nearly names the contradiction but never the culprit.
- `solution`: {culprit: "sX", proof: [evidence ids that DIRECTLY contradict the culprit's own statement or answers; 2 or more, never more than half of all evidence], explanation: step-by-step, ends by saying why each false trail was false}.
- `partner_intro`, `partner_outro_win`, `partner_outro_lose`: ناصری's spoken lines (before the chapter; after a correct / wrong accusation). The outros may name the culprit — they come after the answer.
- `thread`: the small season clue this chapter leaves, taken from the bible table for this chapter; shown after the chapter, so it may mention what was solved. It must open a question the player wants answered next, never answer it.
- `scenes`: [{id, speaker?: "partner", text, options: [{id, title, sub?, goes_to, gives_clue?: [ids], needs_clue?: id, relations?: {personId: state}}]}]; `ending`: {id, speaker?, text}; `board`: {people: [{id, name, role}], clues: [{id, title, text}]}. `gives_clue`/`needs_clue` may use ids from `board.clues` AND evidence ids. All ids: letters, digits, underscore, up to 24 chars. Board person ids are lowercase Latin words (maryam), not s1..s5.
- `_kit` (my tooling only; it is removed before the game sees it): {puzzle_type: 1-10 (see the list), culprit_slot: "sX" (same as solution.culprit), summary: 2–4 sentences saying who did it, how, and which cards prove it}. This summary is all you will remember of this chapter later.

Puzzle types (never the same type twice in a row, none more than twice in the season): 1 guilty knowledge · 2 hidden relationship · 3 not what it seemed · 4 wrong victim · 5 time trick · 6 staged scene · 7 two people one plan · 8 the witness is the liar · 9 object biography · 10 motive inversion.

EXAMPLE (an invented demo chapter; ids, names and plot are NOT to be reused; a real chapter has 5 suspects and 7–9 evidence cards):
=== EXAMPLE JSON START ===
{STORY_EXAMPLE}
=== EXAMPLE JSON END ==="""

PART_RULES = """## 5. HARD RULES (a chapter that breaks one is rejected by my validator)
1. Persian only in every string. Ids and enum values stay Latin. No English words, no emoji. Persian digits ۰-۹ (never 0-9; evidence references like `e3` inside `explanation` are the only exception). Persian letters ی ک (never ي ك), a ZWNJ (نیم‌فاصله) in «می‌کنم، نمی‌دانم، کتاب‌ها». Quotes are «», never straight " inside a string.
2. UI wording: the player is «کارآگاه», never «بازیکن/کاربر/گیمر»; suspects are counted «مظنون». The word «نفر» is forbidden in `option.title`, `option.sub`, `board.*.title`, `board.*.role` (story text may use it for characters).
3. Fictional everything: no real people, brands, banks, apps, cities (use رازان), religious/political places or figures. Nothing gory.
4. No spoilers anywhere before the ending: no field outside `solution`, `partner_outro_*` and `thread` may say or hint who is guilty — not scene text, option titles, `relations`, hints, evidence texts or suspect intros. Do not put every «suspicious» relation on the culprit. No evidence card states the answer or a confession.
5. Season secret: respect the bible's “never before chapter 10” rules.
6. Fair play: every fact needed to solve is on the cards, in statements or in answers. Check every timeline minute by minute, every count, every key and door twice.
7. Ids: suspects s1..sN, evidence e1..eN, no duplicates, every referenced id exists. Use only portraits and scene ids from the lists below; a portrait is used once per case and must match gender, age and job.
8. Output is the raw JSON object only."""

PART_FAIR = """## 6. DIFFICULTY AND FAIR-PLAY RULES
- No easy case. Difficulty is 4 or 5. The culprit is proven only by COMBINING at least two cards (usually three). No single card names the culprit.
- At least two strong false trails: every suspect looks guilty for a while until a later or combined clue clears them. The culprit's own statement is never the only thing that is “off” — innocent suspects lie too, but about their own small secret (an affair, a debt, a small theft, a lie about where they were for an unrelated reason), and a clue explains each such lie.
- Every suspect has a short past, ties to at least one other suspect, and talks about the others in answers; cross-checking statements is part of solving.
- At most TWO “machine” cards (cctv, phone, forensic, receipt) per case; the rest come from people: what they say, carry, wear, know, avoid.
- Evidence types: document, object, witness, cctv, receipt, forensic, phone.
- The explanation walks the combination step by step and says why each false trail was false (mention every innocent suspect by name).
- Vary the culprit's slot; the bible fixes it per chapter."""

PART_LIMITS_HEAD = """## 7. LENGTH LIMITS (stay inside; outside = rejected or sent back as FIX)
Format: `field (unit) = min-max`. Words are counted by spaces; characters include spaces."""

PART_LISTS = """## 8. LISTS
SCENE IDS (`scene`): {SCENES}
PORTRAITS (`avatar.portrait`; m_ = men, f_ = women; format gender_age_job): {PORTRAITS}
avatar.hair: bald, hijab, slick, short, cap, curly · avatar.beard: none, mustache, full, stubble · avatar.accessory: none, tie, scarf, badge, apron · avatar.skin: 0, 1, 2, 3 · avatar.age: young, mid, old"""

PART_CHECK = """## 9. SELF-CHECK (run silently before every reply; fix, then reply; never print it)
1. Is the reply ONE raw JSON object, valid JSON, no fences, no extra text?
2. Only allowed top-level keys; every required field present; counts and lengths inside section 7?
3. Persian only, Persian digits, ی/ک, ZWNJ, «» quotes; no «بازیکن/کاربر», no «نفر» in UI fields; no brands/real names?
4. Ids unique and consistent; every `goes_to`, `gives_clue`, `needs_clue`, relation person, `proof`, `culprit` exists?
5. (Chapter) Scenes: 4–5, 60–140 words each, 2–3 options each, at least one branching scene, no loops, every path reaches `ending`, every scene reachable, each scene has an unlocked option, every locked option's clue comes earlier?
6. Walk the story as a player who has NOT solved it: does anything outside the solution point at the culprit? Does any single card give the answer? Are there two real false trails and a secret for each innocent?
7. Re-check every timeline, key, door and count against the cards; does `solution.proof` contradict the culprit's own words, is it ≤ half of the evidence and ≥ 2 cards? Does the explanation cover every innocent suspect?
8. Do hints go 1 → 3 in strength without naming the culprit? Do `_kit.summary`, `culprit_slot` and puzzle type match the chapter and the bible?"""

PART_OUT = """## 10. OUTPUT
Only the JSON object. Start with `{` and end with `}`."""

CHAPTER_REQUEST = """## 2. SEASON BIBLE (the truth is for you; do not reveal it before the chapter the bible says)
{BIBLE}

REQUEST FORMAT YOU WILL RECEIVE:
WRITE CHAPTER N
CONTEXT:
(one block per earlier chapter, produced by my validator: title · puzzle type · culprit slot · summary · thread)
Use row N of the bible table (title, scene, puzzle type, culprit slot, thief's role, thread). Stay consistent with the CONTEXT: same recurring people keep the same board ids and names; ناصری's mood follows the bible's arc for chapter N."""

CASE_PART = """## 2. THIS PROMPT WRITES NIGHTLY CASES (one case per message)
A nightly case is the same as a chapter's case part but WITHOUT: season, chapter, partner_*, thread, scenes, ending, board. Top-level keys: id, number, publish, difficulty, scene, title, location, intro, suspects, evidence, hints, solution, _notify, _kit.
- `id` "cNNN", `number` = NNN, `publish` "YYYY-MM-DD" — all given in my request. Request: `WRITE CASE c041 publish 2026-11-02 type 7`. `type` is the main puzzle type (list below); the previous case used another one.
- Nightly cases are mostly difficulty 4, some 5. 5 suspects (6 at most), 7–9 evidence cards. Setting: contemporary Iran, any fictional city; no neighbour of the story world is needed.
- `_notify` is the push-notification teaser: {head: ≤35 chars, may end with ONE emoji, unlike any other case's head; body: 1–2 spoken sentences ≤90 chars}. It teases the situation from the intro (place, time, object, central question) without revealing the culprit, motive or any proof, and without inventing facts.
- `_kit`: {puzzle_type: 1-10, culprit_slot: "sX"}.
- The suspect/evidence/hints/solution rules are exactly those of sections 4–6.

Puzzle types: 1 guilty knowledge · 2 hidden relationship · 3 not what it seemed · 4 wrong victim · 5 time trick · 6 staged scene · 7 two people one plan · 8 the witness is the liar · 9 object biography · 10 motive inversion.

EXAMPLE (an invented demo case; do not reuse names or plot):
=== EXAMPLE JSON START ===
{CASE_EXAMPLE}
=== EXAMPLE JSON END ==="""


def limits_text() -> str:
    names = {"w": "words", "c": "chars", "n": "count"}
    lines = []
    for key, (unit, lo, hi, _hlo, _hhi) in K.LIMITS.items():
        lines.append(f"{key} ({names[unit]}) = {lo}-{hi}")
    return "\n".join(lines)


def bible_text() -> str:
    t = (K.ROOT / "docs" / "story-season1-bible.md").read_text(encoding="utf-8")
    a = t.index("## دنیا و لحن")
    t = re.sub(r"<!-- amin-only -->.*?<!-- /amin-only -->\n?", "", t, flags=re.S)
    b = t.index("## وضعیت فعلی")
    return t[a:b].strip().replace("\n## ", "\n### ").replace("## دنیا و لحن", "### دنیا و لحن", 1)


def build() -> str:
    content = K.load_content()
    ports = sorted(K.portraits())
    scenes = ", ".join(sorted(content.SCENES))
    story_ex = (K.ROOT / "tools" / "fixtures" / "story_example.json").read_text(encoding="utf-8").strip()
    case_ex = (K.ROOT / "tools" / "fixtures" / "case_example.json").read_text(encoding="utf-8").strip()
    lists = PART_LISTS.replace("{SCENES}", scenes).replace("{PORTRAITS}", ", ".join(ports))
    limits = f"{PART_LIMITS_HEAD}\n{limits_text()}"
    p1 = "\n\n".join([
        PART_ROLE, PART_HOW, PART_WORLD, CHAPTER_REQUEST.replace("{BIBLE}", bible_text()),
        PART_CHOICES, PART_SCHEMA.replace("{STORY_EXAMPLE}", story_ex), PART_RULES, PART_FAIR, limits, lists,
        PART_CHECK, PART_OUT])
    p2 = "\n\n".join([
        PART_ROLE, PART_HOW_CASE,
        CASE_PART.replace("{CASE_EXAMPLE}", case_ex), PART_RULES.replace("5. Season secret: respect the bible's “never before chapter 10” rules.\n", ""),
        PART_FAIR, limits, lists, PART_CHECK.replace("5. (Chapter) Scenes: 4–5, 60–140 words each, 2–3 options each, at least one branching scene, no loops, every path reaches `ending`, every scene reachable, each scene has an unlocked option, every locked option's clue comes earlier?\n", "5. Are `_notify` and `_kit` present and valid?\n"),
        PART_OUT])
    return (HEADER
            + "## پرامپت ۱ — فصل‌های داستان (یک‌بار در چت تازه بچسبان)\n\n" + FENCE + "\n" + p1 + "\n" + FENCE
            + "\n\n## پرامپت ۲ — پرونده‌ی شبانه (چت جدا؛ یک‌بار بچسبان)\n\n" + FENCE + "\n" + p2 + "\n" + FENCE
            + "\n\n## قالب پیام‌هایی که هر بار می‌فرستی\n\n" + FENCE + "\nWRITE CHAPTER 2\nCONTEXT:\n(بلوک «خلاصه برای پیام فصل بعد» فصل ۱، ۲، ... از اعتبارسنج؛ برای فصل ۱ خالی)\n" + FENCE
            + "\n\n" + FENCE + "\nWRITE CASE c041 publish 2026-11-02 type 7\n" + FENCE
            + "\n\nبرای FIX همان «پیام اصلاحیه» را که اعتبارسنج چاپ می‌کند، بدون تغییر بچسبان (با `FIX:` شروع می‌شود).\n")


def main(argv=None) -> int:
    text = build()
    if argv and "--check" in argv:
        return 0 if OUT.is_file() and OUT.read_text(encoding="utf-8") == text else 1
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT.relative_to(K.ROOT)} ({len(text.split())} words)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
