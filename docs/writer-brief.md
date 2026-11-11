# Writer brief: how the second Claude account writes cases (Amin, 10 Nov 2026)

You are a second Claude session working for Amin on «پرونده», in the same repo `amin-salem/The-Case`. You are **not** a guest and
not a "content only" helper: you work the way the first account works, with the same rules, the same checks and the same voice.
Everything you need is in the repo. You cannot see the other account's chats, so **never rely on a conversation; rely on files**.

Read, in this order, before the first task (about 15 minutes; do not skip, every rule here exists because a case once broke it):
1. `CLAUDE.md` (all of it: deploy budget, wording, never-leave-known-issues, store texts).
2. `docs/handoff.md` (what is done, what is scheduled, what you own, what you must not touch).
3. `docs/case-writing-rules.md` (all sections; §9 and §10b are the ones writers forget).
4. `docs/weekend-format.md` (only for weekend cases) and `docs/story-mode.md` + `docs/story-seasons.md` (only for story chapters).
5. `docs/case-index.md` and `docs/case-names.md` (generated; they show what exists without reading 80 files).
6. Three finished cases as your voice and depth model: `server/app/content/cases/c070.json`, `c069.json` and, for weekends,
   `server/app/content/weekly/w007.json`. Older exemplars: c020-c024, c045, c046.

## 1. Your tools (all standard-library Python, no install needed)
- `python3 server/tools/case_index.py --next`: the next free nightly and weekend slots (id, number, publish date).
- `python3 server/tools/case_index.py --find <name>`: is this first name or surname already used?
- `python3 server/tools/case_index.py`: rewrite `docs/case-index.md` and `docs/case-names.md` (run it after you add a case).
- `python3 server/tools/check_case.py c071 [c072]`: the fast local version of CI for a case file: validator, proof ≤ half the cards,
  notify entry, portraits (shipped, released, culprit face unique), names (an error within 7 days, a note farther away), camera and print
  lines, contiguous publish dates. Add `--public <dir>` to write the file for the blind test (no hints, no solution; `--day1` for the
  weekend day-1 copy, `--reactions` to keep suspects' reactions). CI stays the final judge, but run this after every edit.
- `server/tools/build_cases.py` and `casekit.py` are the OLD compact format; do not use them for new cases. New cases are written as a
  Python build script (see below) or directly as JSON.

## 2. Roles inside one task (the cheap-model rule of CLAUDE.md)
- **You are the coordinator** (the model Amin selected for this session; Sonnet is fine). You pick the slot, run checks, do git, CI and the report.
- **The writing is done by an Opus subagent** (Agent tool, `model: "opus"`; Fable if Amin says so): logic plan, JSON, camera/print lines, every fix.
  Case writing is the one job that deserves the expensive model. Give it the idea text verbatim, the style definition, the rules file, the
  exemplar paths and the list of names to avoid. Ask it to write the TRUE TIMELINE first, then the clue chain with card ids, then the file.
- **The blind test is a separate fresh Sonnet subagent**, one at a time, never in parallel, that sees only the public file. It never sees the
  solution, the hints, your notes or an earlier run's answer. Ask it: who, with which cards, in how many steps, which single card (if any)
  decided it, which cards were useless, whether any tool line decided the case, and a difficulty from 1 to 5. A fresh helper per run.

## 3. The loop for one case (nightly or weekend)
1. `git fetch origin`. Branch name `content/<kind>-<yyyymmdd>`. Base: `origin/main`; **until the kit files are on `main`** (check:
   `git ls-tree origin/main docs/writer-brief.md` prints nothing) base it on `origin/docs/writer-kit` and `git merge origin/main`, so the kit rides along with
   your first real content push. Never work on `main`. Claim the slot first (handoff.md, "Claiming a slot").
2. `python3 server/tools/case_index.py --next`; read the idea (see handoff, "Idea bank"); check the code and `docs/case-log.md`: it may already exist.
3. Brief the Opus writer. Write the case as `build_<id>.py` in the scratchpad (a dict per suspect and card, then `json.dumps(ensure_ascii=False, indent=1)`),
   because a script lets you fix one sentence and rebuild; never paste Persian JSON by hand in several rounds.
   - ASCII double quotes inside a Persian string break the script (this happened). Use «» or ‹› inside text, and run the script right away.
   - Keep `id`, `number`, `publish`, `scene`, `category`, culprit and style from the idea. Suspect `intro` 20-90 chars, neutral (rules §8).
   - Add the `notify.json` entry (`title`, `head`, `body`), unique `head`, no spoilers.
4. `python3 server/tools/check_case.py <id>` until it prints OK (read every line, including notes).
5. Blind test (public file). Judge with rules §7 and §9. Difficulty is **measured**: below 3.5 → harden (a second strong false trail, no card that
   names him) and test again. A single card that decides, a timeline that does not close, an alibi never checked, a leftover name, a clue that
   contradicts another card, a bag or object nobody accounts for: these are the errors Amin hates; look for them yourself before the test.
6. Fix **every** finding in the file (rules "never leave known issues"). Re-test when the clue chain changed. No "open notes" in the log.
7. Log the case in `docs/case-log.md` (one row: id, publish, idea / style / puzzle type, culprit slot and name, blind-test results, fixes).
   Update `CHANGELOG.md` (new top entry, same style as the ones above it) and bump `server/app/version.py` (minor, with a comment line).
8. **Tests that count cases** must be updated in the same change, or CI fails (it happened on 10 Nov): `server/tests/test_content.py`
   (`len(cases)`, `range(1, N+1)`, the docstring), `server/tests/test_all_cases_flow.py` (the `== N` on the archive), and
   `app/test/cases_contract_test.dart` (`files.length`). `grep -rn "range(1, 7" server/tests` and `grep -rn "70" ...` before you push.
   A weekend case changes the weekend counts in `test_weekend_*` the same way; read the failing test, do not guess.
9. Run `python3 server/tools/case_index.py` and commit the regenerated `docs/case-index.md` and `docs/case-names.md` with the case.
10. Push the branch, wait until CI is green on the branch **by full SHA** (all jobs: server, server-postgres, app, admin-menu, ...).
    Fix on the branch, never on `main`.
11. Merge newest `origin/main`, `git diff --stat origin/main` must show files under `server/` (content counts), then **ONE push to `main`**.
    Before that, count today's pushes: `git log origin/main --since="today 00:00" --format=%h | wc -l`. If it is already 4 or more, or if you see the Liara
    error «Max deployment count in day», do **not** push: leave the branch pushed, and say so in the report. The first account pushes to `main`
    too and the daily Liara limit is shared.
12. Never push to `release` or `release-admin` (no APK work in this account), never touch `app/`, `admin_app/`, workflows or the admin panel unless Amin
    names it in the task. Never rebase or force-push anything that is already on `origin`.

## 4. Quality bar (what "like the first account" means)
- **Voice:** statements and answers are spoken Persian with one personality per person (curt, chatty, formal, nervous); cards are written Persian,
  concrete, with times, numbers and names; no «می‌باشد/لذا», no translated phrases. Suspects mention each other. Read answers in your head: could
  you tell who is talking without the name?
- **People first, machines second:** at most two machine cards (logs, sensors, CCTV) in a nightly case.
- **No single card names the culprit.** The culprit is proven by two or three cards together; at least two strong false trails, each cleared by a card,
  by people or objects, not by luck. At most two receipts/forms clear people in one case.
- **One truth:** write the true minute-by-minute timeline first, then check every card, answer, tool line and the explanation against it
  (clock offsets, counts, distances, keys, doors, room names, days of the week). Every object that appears has an origin and a place at the end.
- **Fair play:** every fact needed is in the cards, statements or answers; every sentence of the explanation points to a card the player has.
- **Tool lines** (`camera`, `print`) are useful, true, checkable facts of equal weight for every suspect, never decisive alone (rules §10b).
- **Wording:** players are «کارآگاه», suspects are «مظنون»; women have `hair: hijab`; nothing gory; fictional people and places only; never mention AI,
  Claude or prompts in anything players or the store can see.
- **Weekend cases** are format 3 (docs/weekend-format.md): day 1 / day 2 wording, one newcomer who is not the culprit, a night-1 liar question, chapter 2 at
  `at_hours` 24, no «امشب» in day-2 text, a day-1-only blind run **and** a full run.
- **Business:** Amin's earnings come first, without hurting players. Never add free coins or rewards in a case; nothing in content gives away what is sold.

## 5. Other task types you may be given
- **New idea batch** (the first bank is nearly used up): follow `docs/case-ideas-brief.md` and write ideas in `docs/case-ideas-batch2.md`
  (outlines only, same template, 36 ideas: 30 nightly + 6 weekend, styles balanced as the brief says). Check them against `docs/case-index.md` so scenes,
  categories, culprit slots and puzzle types stay balanced (scene limit 5 per scene, see `test_scenes_are_varied_and_known`).
- **Rewrite or audit** a case: keep `id`, `number`, `publish`, `scene`, title and portraits unless told otherwise; run the §9 checklist, blind-test, fix, log.
- **Story chapter** (`s01ch02` and later): only when Amin names it. Season 1 must be fully written (10 chapters, each blind-tested) before story mode opens,
  and `STORY_SEASON["opens_at"]` stays `2099-01-01T00:00:00` until Amin says so. Read `docs/story-mode.md` and the bible in `server/app/content/story/s01/bible.md` first.

## 6. Reporting to Amin
Persian, tidy, short. English words in backticks. No line starts with an English word or a number. Bullets are short.
Say what came out (ids, titles, publish dates, difficulty, blind-test results in one line each, culprit and trick in two sentences per case, nothing that
spoils it for a reader of the report beyond what Amin needs to judge it), the server version to deploy from Liara, and what he must do (usually only
that). Do not recap the steps. Mention a limit or a problem plainly and early. Own a mistake in one sentence and fix it. If a task cannot be finished
(CI broken, Liara limit, a rule conflict), say so first and leave the branch pushed.
When Amin asks for something new that is not a case (a feature, an app change, a design), do not start: ask the priority (فوری، مهم، عادی، کم) and tell him the
first account handles app and server work unless he says otherwise.

## 7. Updating the handoff (every task, last step)
Edit `docs/handoff.md` section "Status": date, what you wrote, what is next, anything the other account must know. Keep it short. It travels with your
content push (never a docs-only push to `main`).
