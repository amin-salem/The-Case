# Handoff: shared status for the two Claude accounts (started 10 Nov 2026)

Two Claude accounts work on this repo for Amin. They cannot see each other's chats, so this file and `CLAUDE.md` are the shared memory.
Whoever finishes a task updates "Status" below in the same push as the task (never a docs-only push to `main`, see CLAUDE.md).

## Who does what
| Area | Account A (first, long-running) | Account B (writer, from 10 Nov 2026) |
|---|---|---|
| Server, app, admin panel, admin app, workflows, CI | yes | **no**, unless Amin names it in the task |
| UX pack (`app/ux-pack`, sessions 1-8, APK build 87) | yes | never touch the branch |
| Nightly cases c071-c082 (idea bank batch 1, ideas 19-30) | scheduled sessions (Sonnet coordinator + Opus writer) until done | do not write them |
| Weekend cases w008-w011 (ideas 32-35) | scheduled sessions on Wednesdays | do not write them |
| Idea bank batch 2 (new ideas) | no | **yes**, first job (`docs/writer-brief.md` §5) |
| Nightly cases from c083 on, weekend cases from w012 on | only if Amin says so | **yes** |
| Audit / rewrite of old cases (Amin decides) | no | yes, when named |
| Story season 1 (s01ch02-s01ch10) | not now (Amin: later) | only when Amin names it |
| `main` pushes | one per task | one per task, content only, guarded by the daily count (brief §3 step 11) |
| `release` / `release-admin` (APK builds) | yes | **never** |
| ChatGPT avatar branches | do not touch | do not touch |

Why this split: the content writing is the heaviest use of the expensive model, so it moves to the second account; the first account keeps the
work that needs the app and server in one head. If a slot is unclear, **the file on `origin/main` decides**: a case exists when its json is on `main`.

## Claiming a slot (avoid two accounts writing the same case)
Before you write c083 (or any id): `git fetch origin`, then `git branch -r --list 'origin/content/*'` and `git log origin/main --oneline -15`.
If a branch or commit already names the id, take the next one. Then push your branch right away with a first commit `claim c083-c084`
(empty commit is fine: `git commit --allow-empty -m "claim c083-c084"`), and only then start writing.

## Rules that are easy to forget (all in CLAUDE.md, repeated because they cost us before)
- One push to `main` per task, only if `git diff --stat origin/main` shows `server/` files (content counts). Docs/tools/tests alone never go to `main`.
- «Max deployment count in day» from Liara means stop pushing to `main` that day and tell Amin. A failed `/health` check from a workflow is not proof the
  server is down (the check runs outside Iran); never redeploy to "fix" it.
- Amin deploys the server himself from the Liara panel. Every report says which server version to deploy.
- Never reuse a culprit portrait; only portraits listed as usable by the case's publish date (`docs/portrait-release.json`).
- Tests hard-code the number of cases (`test_content.py`, `test_all_cases_flow.py`, `app/test/cases_contract_test.dart`): update them with the case.
- Store and release texts never mention AI, Claude or prompts.

## Status (newest first; keep each entry to a few lines)
- **10 Nov 2026 (account A):** server 1.58.0 on `main`: c069, c070 (ideas 17, 18), w007 rewritten, c067/c068, admin panel in Tehran time with promo impact. Not yet
  deployed by Amin at the time of writing. Idea bank batch 1: ideas 1-20 written (c053-c072; 19, 20 on 15 Nov, server 1.63.0); 21-30 → c073-c082 are scheduled (nightly sessions 10, 12, 13, 14, 15, 16 Nov,
  two cases each); weekend ideas 32-35 → w008-w011 scheduled (Wednesdays 11, 18, 25 Nov, 2 Dec); idea 36 → w012 has no session. Last nightly publish date after c082 is
  2026-12-19; last weekend after w012 would be Thu 2026-12-24. **The bank is therefore empty from c083 (2026-12-20): batch 2 of ideas is the first job of account B.**
- **10 Nov 2026 (account A):** UX pack (8 scheduled sessions, 10-19 Nov, branch `app/ux-pack`) ends in ONE Bazaar release, build 87. Do not publish build 86.
- **Open decisions for Amin:** an extra weekend session for w012; whether the writing sessions move to Fable; a one-off audit of the 73 cases; the "اتاق بازجویی"
  mini-game (not built); story season 1 (not now).
- **Amin's own to-dos:** deploy the server from Liara (before Thu 19 Nov 09:00, when w007 opens); after UX pack session 8, deploy the server first, publish APK 87 once,
  then set «آخرین نسخه» = 87 in the panel («⚙ اقدام‌ها» → «📲 بروزرسانی اپ»); set the real `BAZAAR_URL` after publication; portraits `usable_from` 2026-11-26.
