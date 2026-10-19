# Working rules for this repo

## Liara deploy budget (important)
Every push to `main` starts a Liara deployment, and Liara refuses deployments after a daily maximum
(error «Max deployment count in day», 11 Oct 2026, after about 20 pushes in a day). A refused deployment leaves
the server on the OLD version, so the newest code is not live.

- Work on a branch (CI runs on branches too). Push to `main` ONCE per task, when CI on the branch is green.
- Never push to `main` for docs, CHANGELOG, workflow-only or test-only changes alone: put them in the same push as
  real work, or leave them for the next one.
- Do not push repeatedly to fix CI on `main`; fix on the branch first.
- `git push -f origin main:release` builds the APK and does NOT deploy the server; it does not count.
- If a run sees the deployment error, stop pushing to `main` for that day and tell Amin.

## Three builds, one deploy (Amin, 12 Oct 2026)
There are three separate things: the **game APK** (`app/`, built by pushing a branch to `release`), the **admin APK**
(`admin_app/`, built by pushing a branch to `release-admin`) and the **server** (`server/`, deployed by Liara on every
push to `main`). Only server changes may use a Liara deployment.

- If a task changes ONLY `app/`, `admin_app/`, docs, workflows or tests (nothing under `server/`), do NOT push to `main`.
  Check CI on the branch, then build with `git push -f origin <branch>:release` (game) or `:release-admin` (admin).
  The change reaches `main` later, inside the next push that really changes `server/` (content, endpoints, admin panel).
- If a task changes both, do one push to `main` for the server part and build the APK from the same commit.
- Content (cases, story chapters, weekend cases) lives under `server/`, so it counts as a server change.
- Before pushing to `main`, run `git diff --stat origin/main` and confirm something under `server/` changed.

## Owner's workflow rules (Amin, 11 Oct 2026)
- When Amin asks for a new feature or change during the day, first ask its priority:
  **Urgent** (do it now), **Important** (next scheduled run today/tonight), **Normal** (the next suitable scheduled slot),
  **Low** (batch it with other work later). Anything that is not Urgent or Important is scheduled, not done immediately.
- Use the cheaper model (Sonnet) for every task that does not need deep writing or reasoning. Opus is only for writing
  cases and story chapters (and other work Amin names). Never change a scheduled task's model unless Amin asks.

## Backend engineering principles (senior-level; apply to all server work)
- **Think about production first.** Liara runs 2 worker processes (`WEB_CONCURRENCY`) in a small container with Postgres.
  Anything kept in process memory is per worker; anything shared must go through the database (atomic upserts) or an
  optional Redis. Never assume one process, one request at a time, or a clean restart.
- **Correctness under concurrency.** Money, coins, rewards and one-time grants must be idempotent and atomic
  (unique constraints, `INSERT ... ON CONFLICT`, single transaction). Two simultaneous requests must not pay twice.
- **Trust nothing from the client.** Validate and bound every input (length, range, count). The server is the boss of
  coins, stars, time and answers. Secrets only from environment variables, never in the repo, logs or responses.
- **Fail safely.** Decide per feature: fail open (a broken rate-limit store must not take the game down) or fail
  closed (admin login, payments). Errors return a stable JSON shape with a Persian-friendly code the app can map.
- **Bounded resources.** Every cache, counter and list has a size or time limit (TTL/eviction) so a flood cannot
  exhaust memory or the database. Paginate lists. Add indexes for every new query that filters or sorts.
- **Rate limiting is a layered system, not one number.** Per-route policies (strict on register/login/accuse/purchase,
  relaxed on reads), keyed by player id when known else client IP (trust the proxy header only from the last hop),
  a global per-IP ceiling, burst vs sustained limits, `429` with `Retry-After`, a kill switch, and a counter of blocks
  visible in the admin panel. Anti-cheat limits reuse this limiter; do not build a second one.
- **Migrations are additive and safe.** Only add tables/columns, with defaults, written to run on both SQLite (CI)
  and Postgres (Liara); list them in `.github/workflows/ci.yml`.
- **Observable.** Log one structured line for important decisions (blocked, banned, paid, failed), without personal
  data. Anything an operator must watch belongs in the admin panel health screen or the GitHub watch workflows.
- **Test the behaviour, not the code.** Deterministic clocks, no sleeps; cover the failure and the abuse path, not only
  the happy path. CI is the only test runner, so keep tests fast and independent.
- **Small, reversible steps.** Feature flags/kill switches for risky behaviour, one push to `main` per task
  (see the deploy budget above), and a short note in `CHANGELOG.md` and `docs/operations.md` for anything an operator
  must know or set.

## Server unreachable from GitHub (Amin, 12 Oct 2026)
The server watch, the live check in the release notes and the smoke tests run from GitHub's servers OUTSIDE Iran, and
`gaamly.ir` is often unreachable from abroad while it works fine inside Iran (Amin sees the same with a VPN on).
So a failed health check from a workflow is NOT proof that the server is down.
- When you see "did not answer /health" / `(health failed)`: do not try to fix it by pushing or redeploying.
  Tell Amin to open `https://gaamly.ir/health` WITHOUT a VPN (and the Liara Deployments tab). If it works there,
  the problem is only the route from abroad and he redeploys by hand from the Liara panel if he wants the newest version.
- Amin deploys the server manually from the Liara panel when needed. Pushing to `main` still starts a Liara build
  (see the deploy budget above), so keep to one push per task.

## Wording (Amin, 12 Oct 2026)
Players are «کارآگاه», never «نفر»: «۱۰ کارآگاه حلش کردن», «۱۰ کارآگاه اول». Suspects are counted as «مظنون» («۸ مظنون»).
This is about app/UI texts. People inside a case's story text may still be «نفر».

## Business priority (Amin, 13 Oct 2026)
Amin's livelihood depends on this game: when you decide or build anything, weigh **his earnings** first, without hurting
players (no dark patterns, the daily case is never blocked by coins, every offer closes in one tap).
- Prefer the option that increases coin-pack purchases, first purchases, starter-pack conversion, retention and invites,
  as long as it is fair to players. Say in one line what a choice does for revenue when it matters.
- Never give away what could be sold: coins, warrants, avatars, archive cases. Keep the free economy scarce (see the
  coin rebalance), and keep coin sinks attractive (archive, story warrants/skips, avatars, frames, streak freeze).
- Before adding free rewards, ask: does this reduce the reason to buy coins?

## Story opening gate (Amin, 13 Oct 2026)
Story mode opens for players only when BOTH are true (AND, not OR):
1. **Season 1 is completely written**: all 10 chapters (s01ch01-s01ch10) exist in the choices format and passed the blind test.
2. **The game app has been published on Cafe Bazaar** (Amin confirms it himself).
Until then `STORY_SEASON["opens_at"]` stays `2099-01-01T00:00:00`. Only Amin (or Claude after he says so) sets the real date.
Reason: a story that gets one chapter a night would never make players buy warrants/skips; a finished season does
(chapters 1-3 free, later ones need a warrant, the 12 h wait or coins).

## One slot, one build (Amin, 17 Oct 2026)
When Amin asks for several changes for the same time slot (or the same night), they are ONE scheduled task, ONE branch, ONE
server version and ONE APK. Never schedule them as separate tasks that each build their own APK: a later build overwrites
`release` and silently drops the earlier work (17 Oct: the difficulty bar and the stars fix were lost from build 57).
- Before building an APK: `git fetch origin`, merge the newest `origin/main` AND `origin/release`, and check that the
  earlier features are still in the code (grep) before pushing to `release`.
- If you find two tasks scheduled at the same time, merge them into one before they run.
- Docs/tools-only work (prompt kits, triage) stays on its own branch and does not build anything.

## Never leave known issues (Amin, 18 Oct 2026)
Every "minor issue" or "open note" you find in a case (Gemini output, blind test, your own review) is FIXED before the case
is reported done: edit the file, re-validate, re-run the blind test if the clue chain changed, and only then log it as resolved.
Do not write soft spots into `docs/case-log.md` as "notes" and move on. Story-type errors Amin has reported (culprit named by one
card, impossible timelines, an alibi never checked, leftover names, a clue that contradicts another card, a bag/object left
unaccounted for) must never reach him again: check for them yourself on every case.
Cases written by Gemini are rewritten into the house voice and reviewed with the checklist in `docs/case-writing-rules.md` section 9
(Amin, 19 Oct 2026) before the blind test; Amin wants them to read like c020-c024, not like Gemini's flat prose.
