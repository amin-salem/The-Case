# Operations

Notes for the operator (Amin). Other documents: `health-watch.md` (the GitHub watch workflows), `CLAUDE.md` (deploy budget).

## Admin app

A small Android app, `admin_app/`, that shows the admin web panel (`/admin/ui`) full-screen on your phone. It is a thin
wrapper: it shows exactly what `/admin/ui` shows, so **new panel features and the Health page appear without a new APK**.
It is only sideloaded (never published in a store). **Do not share the APK or the admin key.**

- **Install:** open the repository's Releases on GitHub on your phone, download `parvandeh-admin.apk` from the release
  `admin-latest`, open it and allow installing from this source (the browser or file manager) when Android asks.
  Updating = download and install again (same signing key, so it updates in place).
- **First start:** the app asks for the lock (fingerprint or phone lock, if the phone has one), then for the admin key
  (`ADMIN_API_KEY`) once. The key is stored with the Android Keystore (flutter_secure_storage), never in the APK or repo.
  On every page load the app opens `https://gaamly.ir/admin/ui#k=<key>`; the page reads the fragment once, signs in and
  removes it from the address bar (a fragment is never sent to the server).
- **Settings (gear icon):** server (`https://gaamly.ir`, or the old `https://thecase.liara.run` as a fallback), lock on open
  (default on if the phone supports it), hide the screen from screenshots and recent apps (Android FLAG_SECURE, default on),
  and log out (erases the key and the web storage from the phone).
- **Safety:** HTTPS only; the app refuses to navigate to any host except the chosen server; no JavaScript channel from the
  page into the app.
- **Rotate the admin key:** change `ADMIN_API_KEY` on Liara (and redeploy), open the app → gear → log out, enter the new key.
  If the stored key is refused, the app asks for a new one by itself.
- **Rebuild the APK:** `git push -f origin <branch>:release-admin` (or run «Release admin APK» in the Actions tab). The workflow
  `.github/workflows/release-admin.yml` creates the Android project, patches it (`admin_app/tools/patch_android.py`: application id
  `app.parvandeh.admin` at the top of that file, permissions, label, icon, signing), runs analyze and tests, builds and replaces
  the asset of the release `admin-latest`. It signs with the same `ANDROID_KEYSTORE_*` secrets as the main app (debug key if
  absent). It never touches `main`, so it does not deploy the server and does not count against the Liara deploy budget.

### Health page

Panel → «سلامت» (works in a browser too). Each card has a green / amber / red dot; «بررسی دوباره» reloads everything.

- **سرور:** version, how long this worker has been up, number of workers (`WEB_CONCURRENCY`), database reachable + query time
  (amber > 300 ms, red > 1 s), database size (Postgres) and row counts of the main tables.
- **آدرس‌ها:** days left on the TLS certificate of `gaamly.ir` and `thecase.liara.run`, checked from the server (cached 10 min).
  Amber under 30 days, red under 14. The old address only turns amber when it fails.
- **محتوا:** how many days of nightly cases are written ahead (amber < 7, red < 3), the last nightly case that opened, the next
  weekend case and when it opens, story season / chapters written / next missing chapter, and whether all content files load.
- **بازیکن‌ها:** total, active today, solves today (Tehran day) and the app-versions table. 5xx counts are not collected yet.
- **امنیت و محدودیت‌ها:** whether `ADMIN_API_KEY` and `JWT_SECRET` are real values (never shown), rate limiter on/off,
  rewarded ads switch, `BAZAAR_MODE`, `ENV`. «Blocked in the last hour» is not counted yet.
- **موجودی لیارا:** the server calls `https://api.liara.ir/v1/billing` with `LIARA_API_TOKEN` and shows the balance in toman.
  The alert limit is `LIARA_MIN_BALANCE` (default 300000): amber up to 1.5× the limit, red at or below it. Cached 5 minutes; the
  button makes at most one real call per 30 seconds. **You must add `LIARA_API_TOKEN` (the same token as the GitHub secret) to
  the Liara app's environment**; until then the card says «LIARA_API_TOKEN روی لیارا تنظیم نشده». The token never leaves the server.
- **GitHub watch:** results are not visible to the server; the card only names the workflows (Server watch every 30 min,
  Liara balance daily 08:00 Tehran).

Also set on Liara (the Health page shows red/amber until then): a long random `ADMIN_API_KEY` (24+ characters) and `JWT_SECRET` (32+).

## Rate limits

One limiter protects the whole API (`server/app/services/ratelimit.py`). The Tuesday anti-cheat task must **reuse it**
(named policies `accuse`, `register`, `register_device`, … and `enforce(name, key)`), not build another.

### How it works

- **Policy table** (`DEFAULTS` in `ratelimit.py`): each policy has one or more *tiers* `limit/seconds`, a burst tier first and a
  sustained tier after it (`accuse` = 1 per 3 s **and** 20 per hour). Tiers with limit ≥ 10 use a sliding-window estimate;
  smaller tiers use exact fixed windows.
- **Routes** (`ROUTES`) map a method + path to a policy. Every request also passes `global_ip`. Not limited at all:
  `/health`, `/privacy`, `/terms`, `/delete-account`, `/admin/ui`, `/docs`, `/openapi.json`, `/static/*`.
- **Identity**: the player id from a *valid* login token, otherwise the client IP. A forged or expired token counts as "no token".
  Stored keys are salted hashes (never raw IPs or ids). `register_device` / `login_target` also look at client-sent values
  (device id, account, email) but only **in addition** to the IP limit, so changing them never helps an attacker.
- **Client IP**: `X-Forwarded-For` is read only if the socket peer is a private/loopback address (the proxy) and then only the
  entry added by the last trusted hop (`RATE_TRUSTED_HOPS`, default 1 = the last entry). Entries a client wrote itself sit to the
  left and are ignored; a malformed value falls back to the socket address. `start.sh` runs uvicorn with `--no-proxy-headers`
  because uvicorn's own handling with `*` would trust the left (client-written) end.
- **Storage**: *memory* (per worker, bounded to 20 000 keys, expired entries dropped then least-recently-used) for the generous
  limits — with N workers the effective limit is up to N× the number below; the *strict* limits are shared by all workers:
  the `rate_hits` table (atomic `INSERT … ON CONFLICT DO UPDATE … RETURNING`, Postgres and SQLite) or Redis when `REDIS_URL` is
  set (used automatically; if it fails the database is not used as a silent fallback — the failure policy below applies).
  Rows are deleted by an hourly cleanup in every worker.
- **Failure policy**: if the store errors, generic and strict game limits fail **open** (one log line per policy per 5 minutes:
  `ratelimit store_error …`). `register`, `register_device` and the admin lockout counter fail **closed** — only those routes answer
  `503 {"error":"try_later"}`; the rest of the API keeps working.
- **Kill switch**: `RATE_LIMIT=false` turns the whole limiter off (no checks, no headers).

### Responses

`429 {"error":"rate_limited","message":"<Persian>","retry_after":<seconds>}` with `Retry-After`, `X-RateLimit-Limit`,
`X-RateLimit-Remaining`, `X-RateLimit-Reset`. Allowed requests carry the three `X-RateLimit-*` headers too.

### Policies (defaults)

| Policy | Applies to | Key | Limits | Store | Broken store |
|---|---|---|---|---|---|
| `global_ip` | every request | IP | 100/5 s, 600/60 s | memory | open |
| `register` | POST /v1/auth/register | IP | 3/60 s, 10/day | shared | closed |
| `register_device` | same, by `device_id` | device_id | 3/day | shared | closed |
| `login` | /v1/auth/login, /login/email | IP | 20/60 s, 60/10 min | shared | open |
| `login_target` | same, by player id / email / code | target | 20/10 min | shared | open |
| `transfer` | POST /v1/auth/transfer | IP | 5/5 min | shared | open |
| `account` | /v1/auth/email, /transfer-code | player | 5/10 min | shared | open |
| `accuse` | POST …/accuse | player | 1/3 s, 20/h | shared | open |
| `hint` | POST …/hint | player | 2/5 s, 60/h | shared | open |
| `unlock` | case / riddle unlock | player | 3/10 s, 60/h | shared | open |
| `riddle_answer` | POST …/answer | player | 2/5 s, 60/10 min | shared | open |
| `wallet` | streak freeze, ad reward, mission claim | player | 5/10 s, 60/10 min | shared | open |
| `purchase` | POST /v1/purchases/verify | player | 3/30 s, 20/h | shared | open |
| `story` | story open / skip | player | 3/10 s, 60/h | shared | open |
| `claim` | inbox claim | player | 5/10 s, 60/10 min | shared | open |
| `referral` | redeem invite code | player | 3/60 s, 10/10 min | shared | open |
| `client_info` | POST /v1/me/client | player | 2/60 s, 10/h | memory | open |
| `read` | other GET /v1/* | player or IP | 60/10 s, 1500/10 min | memory | open |
| `write` | other POST/PATCH /v1/* | player or IP | 30/10 s, 900/10 min | memory | open |
| `admin` | /admin/* with a correct key | IP | 60/10 s, 2000/10 min | memory | open |
| `admin_fail` | wrong `X-Admin-Key` | IP | 5 failures → locked for 15 min | shared | closed (admin only) |

### Environment variables (set on Liara; none are required)

- `RL_<POLICY>` overrides one policy, e.g. `RL_ACCUSE=1/3,20/3600` (`limit/seconds`, comma-separated tiers, window ≤ 3600).
  `RL_HINT=off` disables a policy. A bad value is ignored (logged) and the default stays. Names are the upper-case table names:
  `RL_ADMIN_FAIL=5/900` changes the lockout (5 failures, locked for 900 s).
- `RATE_LIMIT=false` — kill switch.
- `REDIS_URL` — optional shared store for the strict limits.
- `RATE_TRUSTED_HOPS` (default 1) — proxies in front of the server. If *all* players look like one IP in the admin Health
  screen (one key with a huge blocked count), raise it; if Liara adds no proxy header, players share the proxy IP, so also raise
  the `global_ip` limit (`RL_GLOBAL_IP`).
- `RATE_TRUSTED_PROXIES` — optional CIDR list allowed to set `X-Forwarded-For` (default: private addresses).
- `RATE_ADMIN_ALLOW_IPS` — comma list of IPs that are never locked out of `/admin`.

### Admin lockout

5 wrong `X-Admin-Key` values from one IP lock that IP out of **all** `/admin` routes for 15 minutes (the right key does not
help while locked; correct keys never cause a lockout). Locks appear in the admin panel → **سلامت** (Health) under «قفل‌های فعال»
with a «برداشتن قفل» button; it is recorded in the admin log (`rl_clear`). If your own IP is locked, open the panel from another
network (mobile data) and clear it there, or wait 15 minutes. The same screen shows blocked requests in the last hour and the
top 5 blocked keys (hashed/shortened).

### For the anti-cheat task

```python
from app.services.ratelimit import enforce, limiter, RateLimited   # RateLimited is turned into the 429 JSON automatically
await enforce("accuse", f"{player.id}")                              # any named policy; key = anything you want limited
```
Add a new policy by adding one line to `DEFAULTS` (and a route to `ROUTES` if it is path-based). Log decisions with one line, no personal data.

## Cafe Bazaar billing (12 Oct 2026; Myket is off for now)

The app pays through Cafe Bazaar (Poolakey) and sends the purchase token to `POST /v1/purchases/verify` (`store: bazaar`); the server checks it with Bazaar and only then adds coins. To go live Amin must:

1. In the Bazaar developer panel create the in-app products with EXACTLY these ids: `coins_small`, `coins_medium`, `coins_large`, `starter_pack`, `vip_monthly` (prices as in the shop).
2. Add the GitHub secret `BAZAAR_RSA_KEY` (the RSA public key from the panel), then build the APK (`git push -f origin <branch>:release`).
3. On Liara set `BAZAAR_MODE` to `api_secret` (plus `BAZAAR_API_SECRET`) or `oauth` (plus `BAZAAR_CLIENT_ID`, `BAZAAR_CLIENT_SECRET`, `BAZAAR_REFRESH_TOKEN`). `fake` is refused in production (`store_not_configured`) and shown as bad on the Health page.
4. Test one real purchase on a test device before publishing.

## Case comments (12 Oct 2026)
- Players write comments + 1-5 stars after finishing a case; admin approves in the panel tab «💬 نظرها» (also in the admin app). Nothing is public before approval.
- Kill switch: `COMMENTS_ENABLED=false` (reads and writes answer 503 `comments_off`). Limit: `RL_COMMENT` (default `2/20,10/3600`).
- Table `case_comments` is created by migration 0014 (additive). Hidden or rejected comments stay in the table; delete removes the comment and its replies.

## Story choices (12 Oct 2026)
- New endpoints (all need login; they use the existing `read` / `write` rate-limit policies): `GET /v1/story/chapter/{id}/state`,
  `POST /v1/story/chapter/{id}/choose {scene, option}`, `GET /v1/story/board`. Table `story_state` (migration 0015, listed in CI).
  Refusals are 409 `wrong_scene` / `locked` / `too_many_choices`, 404 `no_option`, 409 `chapter_locked` (chapter not opened) and
  `story_not_open`. Log lines `story_choose` / `story_choose_refused` carry no personal data.
- **Story mode is still paused** (`STORY_SEASON.opens_at` = 2099 in `server/app/content.py`): the endpoints answer `story_not_open`
  until it is set to the real date. Reactivate only after the new app (1.22.0) is installed and tested. Format: `docs/story-mode.md`.

## Anti-cheat (13 Oct 2026)

Threat: every case has one answer, so a throwaway account can lose a case, read the answer and hand it to the main account; many accounts can also farm coins. The rules (numbers in `server/app/economy.py`, logic in `server/app/anticheat.py`):

- **Delayed answer.** A lost case hides culprit, proof and explanation until the case is closed: nightly case → the next case opening (21:00 Tehran), weekend case → its closing, story chapter → 24 h after the failure (`STORY_ANSWER_DELAY_HOURS`), archive case → at once. The time is stored in `case_progress.reveal_at`; the API gives `answer_at` and the app shows a countdown. People who solved the case see the explanation at once.
- **Proof of investigation.** 3 stars and a leaderboard place need `MIN_ACTIVE_SECONDS` (180) of active time and `MIN_SUSPECTS_SEEN` (2) interrogated suspects. Otherwise: solved, 1 star, normal 1-star coins, `ranked = false` (not in the daily/weekly boards or prizes). Active time is measured by the app's ticks and bounded by real elapsed time on the server. To tune, change the two numbers.
- **Throwaway accounts.** `START_COINS` is 100. The inviter's 300 coins arrive after the invited player solved cases on 3 different days (`INVITE_MIN_DAYS`), max 5 paid invites a week (`INVITE_PAID_PER_WEEK`) and 1 per device (`referral_payouts` unique rows). Registration: 3 per device and 10 per IP per day (`register` and `register_device` policies, override with `RL_REGISTER` / `RL_REGISTER_DEVICE`; many players share one mobile-network IP, so watch the blocks counter on the admin health screen and raise the IP number if real players are blocked). Accounts under 48 h without email are hidden from the leaderboards and the weekly prizes (`HIDE_NEW_ACCOUNT_HOURS`); they still play and earn.
- **Shuffle.** Suspects and evidence come in a per-player order (same ids), so "pick the third one" does not work between friends.
- **Scripts.** `accuse` 1 request / 3 s and 20 / h per player (the shared rate limiter), `register` as above. Store purchases are verified with Myket/Bazaar from the server and the purchase token is unique, so a token can be redeemed once.
- **Cheat report.** `GET /admin/cheat-report?days=7` with the admin key (curl, or the admin panel's API): devices with 3+ accounts, solves under 60 s of active time, 4+ new accounts giving the same first answer within 10 minutes. A short weekly summary is also written to the admin log (action `cheat_report`; `POST /admin/cheat-report/weekly` writes it now). To ban someone: `POST /admin/players/{id}/ban` or the Players tab (`Player.banned`). The report only reports; you decide.

**Reminder for Amin:** turn on **daily database backups** in the Liara panel (the database page → Backups) if it is not on yet.

