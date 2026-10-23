# Standing content-writing plan (Amin, 23 Oct 2026)

Amin's internet may be down for days, so content is written by scheduled sessions: **18 nightly sessions** (Sat, Sun, Mon, Tue,
Thu, Fri for three weeks from Sat 24 Oct 2026; two cases each = 12 per week) and **3 weekend sessions** (Wednesdays 28 Oct,
4 Nov, 11 Nov; one weekend case each, released Thursday 09:00). Stock when this was written: c001-c050 (last publish 17 Nov
2026) and w001-w006 (last publish Thu 12 Nov 2026).

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
   the house voice (c020-c024), then for EVERY suspect `camera` and `print` lines (§10: neutral, equal tone, culprit as harmless
   as the others, 20-160 chars, no clue material, print != camera).
4. Checks by the coordinator: validator / `server/tools/import_case.py` (CI is the final judge), the story errors Amin hates
   (culprit named by one card, impossible timeline, alibi never checked, leftover names, contradicting clue, unaccounted object),
   wording «کارآگاه»/«مظنون». Blind test with a Sonnet helper on the public case: solvable in ~6-10 steps, no single giveaway card,
   not guessable from the first 3 cards. One fix round (Opus), then retest; a second failure means rewriting the weak chain.
5. Log in docs/case-log.md. Branch `content/nightly-<yyyymmdd>`, push, wait for CI green (check-runs by FULL SHA, gh REST),
   merge newest origin/main, `git diff --stat origin/main` must show server/app/content, then ONE push to main (bump
   server/app/version.py, CHANGELOG line, docs in the same push). No app change, no APK, nothing to `release`.

## Weekend session (one case, Wednesdays)
Same roles and steps, with docs/weekend-format.md and the last weekend files as the model. Slot: highest `w` number M, publish
date P (a Thursday) -> w(M+1) with publish P+7 days, open_hour 9, closes_hours like w006. Format: alternate with the previous
case (w006 is format 2 -> w007 format 3 -> w008 format 2 -> w009 format 3). VERY hard (difficulty 5 on the 1-5 scale, as Amin wants
weekend cases to be: deep, several false trails, chapter-2 cards that change the picture, the motive asked at the end), chapter
cards so a player always knows what is new (`chapters[].evidence`, format 3 `appears_chapter`), `camera`/`print` for every
suspect (the tools work on weekend cases once per night). Blind test must show: night 1 leaves a leaning but no certainty;
the full case is solvable only with chapter-2 cards. Validator `validate_weekly`.

## Always
If the Liara error «Max deployment count in day» shows, do not push to main again that day; leave the branch pushed and say so.
If the internet or CI is unavailable, leave the branch and report. Never leave a known issue in a case.
Report to Amin in Persian: ids, titles, difficulty, publish dates, blind-test result, server version to deploy from Liara.
