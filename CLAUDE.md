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
