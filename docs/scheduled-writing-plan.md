# Standing content-writing plan (Amin, 23 Oct 2026)

Amin's internet may be down for days, so content is written by scheduled sessions: **18 nightly sessions** (Sat, Sun, Mon, Tue,
Thu, Fri for three weeks from Sat 24 Oct 2026; two cases each = 12 per week) and **3 weekend sessions** (Wednesdays 28 Oct,
4 Nov, 11 Nov; one weekend case each, released Thursday 09:00). Stock when this was written: c001-c050 (last publish 17 Nov
2026) and w001-w006 (last publish Thu 12 Nov 2026).

## Idea bank (Amin, 27 Oct 2026) — overrides "pick puzzle types and settings" below
Since 27 Oct every session writes from `docs/case-ideas-batch1.md` (read it from this branch:
`git show origin/docs/writing-plan:docs/case-ideas-batch1.md`; the brief that produced it is `docs/case-ideas-brief.md`).
- Nightly: idea k → c(52+k) (ideas 1-30 → c053-c082). A session writes the two lowest-numbered ideas whose case file does not
  exist yet. Publish dates stay contiguous after the highest existing case.
- Weekend: idea 31 → w007, 32 → w008 … 36 → w012, the lowest idea whose file does not exist; **always format 3** (day-1 liar,
  one newcomer, two days: chapter 1 at_hours 0, **chapter 2 at_hours 24 = Friday 09:00** (Amin, 30 Oct 2026; the validator refuses
  anything else for publish >= 2026-11-05), open_hour 9, closes_hours 36), publish = highest weekend publish + 7 days.
  Wording: «روز اول / روز دوم» (never «شب اول / شب دوم»). A night passes between the two parts: the chapter-2 `text` starts from
  «صبح جمعه», and no story text or card may say «امشب», «همین شب», «ساعت ۲۱» or «همان شب» about chapter 2.
- Hand the Opus writer the idea text verbatim plus the style definition from the brief (S1-S7). Keep premise, style, puzzle type,
  scene, category and culprit; fix every weakness against docs/case-writing-rules.md (the ideas are outlines, not checked cases).
  Vary how false trails are cleared: at most two receipts/forms clear people in one case; use people, objects and answers for the rest.
- Log in docs/case-log.md: «idea #k, style Sx, puzzle type N».

## Roles (cheap model rule from CLAUDE.md)
The scheduled session itself is a Sonnet COORDINATOR: it reads the rules, picks the slots, runs the checks, CI, git and the push.
The WRITING (logic plan + JSON + camera/print lines + fixes) is done by an **Opus subagent** (Agent tool, model opus), because
case writing is the one job CLAUDE.md reserves for Opus. The blind test is a **Sonnet subagent** that never sees the solution.

## Nightly session (two cases)
1. Read CLAUDE.md, docs/case-writing-rules.md (§9, §10), docs/case-log.md, docs/chatgpt-case-prompt.md if present.
2. Slots come from the repo: highest nightly number N in server/app/content/cases and its `publish` date D. Write c(N+1) and
   c(N+2) with publish D+1 and D+2 (contiguous; if a file already exists, continue after it; never touch published cases).
3. Brief for the Opus writer: difficulty 4 and 5; puzzle types and settings different from the last 10 cases and from each other;
   `category`/`scene` like the others; 5-6 suspects, 8-12 cards; LOGIC PLAN first (culprit, trick, clue chain with card ids, two
   false trails each cleared by a card, alibis with exact times, motive, every object/bag/phone accounted for), then the JSON in
   the house voice (c020-c024), then for EVERY suspect `camera` and `print` lines (rules §10b, Amin 25 Oct 2026, REPLACES the old «neutral» rule: each line is a
   useful, TRUE, checkable fact placed on the true timeline: camera = a sighting with time and place, print = which named object he touched;
   equal weight and length for every suspect incl. the culprit, never decisive alone, never naming the culprit, 20-160 chars, spoken Persian,
   print != camera, no repeat of a card/answer; see c001-c028 for style). The blind-test reader gets these lines and reports whether any single
   line decides the case and whether each told him something useful; rewrite and retest if either answer is bad).
4. Checks by the coordinator: validator / `server/tools/import_case.py` (CI is the final judge), the story errors Amin hates
   (culprit named by one card, impossible timeline, alibi never checked, leftover names, contradicting clue, unaccounted object),
   wording «کارآگاه»/«مظنون». Blind test with a Sonnet helper on the public case: solvable in ~6-10 steps, no single giveaway card,
   not guessable from the first 3 cards. One fix round (Opus), then retest; a second failure means rewriting the weak chain.
5. Log in docs/case-log.md. Branch `content/nightly-<yyyymmdd>`, push, wait for CI green (check-runs by FULL SHA, gh REST),
   merge newest origin/main, `git diff --stat origin/main` must show server/app/content, then ONE push to main (bump
   server/app/version.py, CHANGELOG line, docs in the same push). No app change, no APK, nothing to `release`.

## Weekend session (one case, Wednesdays)
Same roles and steps, with docs/weekend-format.md and the last weekend files as the model. Slot: highest `w` number M, publish
date P (a Thursday) -> w(M+1) with publish P+7 days, open_hour 9, closes_hours like w006. Format: **always format 3** since
27 Oct 2026 (see Idea bank; the old alternation 2/3 is dropped, w004 was rewritten in format 3). VERY hard (difficulty 5 on the 1-5 scale, as Amin wants
weekend cases to be: deep, several false trails, chapter-2 cards that change the picture, the motive asked at the end), chapter
cards so a player always knows what is new (`chapters[].evidence`, format 3 `appears_chapter`), `camera`/`print` for every
suspect (the tools work on weekend cases once per night). Blind test must show: night 1 leaves a leaning but no certainty;
the full case is solvable only with chapter-2 cards. Validator `validate_weekly`.

## Always
If the Liara error «Max deployment count in day» shows, do not push to main again that day; leave the branch pushed and say so.
If the internet or CI is unavailable, leave the branch and report. Never leave a known issue in a case.
Report to Amin in Persian: ids, titles, difficulty, publish dates, blind-test result, server version to deploy from Liara.
