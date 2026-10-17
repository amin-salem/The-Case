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
- **Routes** (`ROUTES`) map a method + path to a policy. Every request also passes a global limit: `global_player` (per player) plus the high flood guard `global_ip_auth` when it carries a valid token, `global_ip` when it does not. Not limited at all:
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
| `global_ip` | requests WITHOUT a valid token | IP | 100/5 s, 600/60 s | memory | open |
| `global_player` | every request WITH a valid token | player | 150/5 s, 1200/60 s | memory | open |
| `global_ip_auth` | same, per IP: flood guard only (CGNAT) | IP | 3000/5 s, 20000/60 s | memory | open |
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
  the `global_ip` and `global_ip_auth` limits (`RL_GLOBAL_IP`, `RL_GLOBAL_IP_AUTH`).
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
- **No oracle for hasty guesses.** The «right person, wrong proof» answer (`wrong_proof` / `wrong_motive`, free the first 2 times) is given only after the same investigation bar as 3 stars; before it, accusing the culprit with wrong proof answers `wrong_suspect` and costs a try, so a throwaway cannot find the culprit by probing.
- **Shuffle.** Suspects and evidence come in a per-player order (same ids), so "pick the third one" does not work between friends.
- **Scripts.** `accuse` 1 request / 3 s and 20 / h per player (the shared rate limiter), `register` as above. Store purchases are verified with Myket/Bazaar from the server and the purchase token is unique, so a token can be redeemed once.
- **Cheat report.** `GET /admin/cheat-report?days=7` with the admin key (curl, or the admin panel's API): devices with 3+ accounts, solves under 60 s of active time, 4+ new accounts giving the same first answer within 10 minutes. A short weekly summary is also written to the admin log (action `cheat_report`; `POST /admin/cheat-report/weekly` writes it now). To ban someone: `POST /admin/players/{id}/ban` or the Players tab (`Player.banned`). The report only reports; you decide.

**Reminder for Amin:** turn on **daily database backups** in the Liara panel (the database page → Backups) if it is not on yet.



## Phone-secured accounts, SMS (13 Oct 2026)

Provider: Ghasedak (OTP template). Liara environment (never in the repo, chat or logs):

- `SMS_MODE=ghasedak`, `SMS_API_KEY=<key from the Ghasedak panel>`, `SMS_TEMPLATE=<approved OTP template name; one parameter, the code>`.
- Optional: `SMS_ENABLED=false` (kill switch, every code request answers 503 `sms_unavailable`), `PHONE_PEPPER=<random 32+ chars>` (secret for hashing phone numbers; if empty it is derived from `JWT_SECRET`; do not change it later or old numbers stop matching), `SMS_URL` (the OTP endpoint if Ghasedak changes it), `RL_SMS_DAILY=5000/86400` (daily ceiling for all codes).
- The health screen shows `sms_mode` and `sms_ready`. `SMS_MODE=fake` never sends and is refused in production.
- Watch the cost: the admin rate-limit blocks counter shows SMS-pumping attempts (`sms_*` policies).
- Privacy: the privacy page and the store listing must say the phone number is used only to secure the account (stored as a hash).


## Messages hub feed and suspect intros (13 Oct 2026)

- `GET /v1/feed` (auth, the normal `read` rate policy) returns the merged feed for the app's «پیام‌ها و نشان‌ها» screen: at most 40 items from the last 14 days, newest first (gifts, badges, nightly/weekend openings after the player joined, `news` announcements from the remote config as `{title, body, at?}`; story openings only once `STORY_SEASON.opens_at` has passed). `POST /v1/feed/seen` sets `players.feed_seen_at` (idempotent); an item is unread when newer than that. `GET /v1/me` also returns `unread` (the bell number). Gifts are still claimed with `POST /v1/inbox/{id}/claim` (pays once). Migration 0018 adds `feed_seen_at`.
- **Intro rule:** every suspect (nightly, weekend, story) must have `intro` (20–90 characters, neutral: who they are, never motive/alibi/lie/secret). The server refuses to start content without it (`content.validate`); the writing rules are in `docs/case-writing-rules.md`.

## Coins and mission day (13 Oct 2026, server 1.25.0)

- All reward numbers live in `server/app/economy.py` and `server/app/achievements.py`; the app reads prices from `/v1/meta`. Existing balances are never changed.
- The daily-missions day runs from `NEW_CASE_HOUR` (21:00 Tehran) to the same hour next evening: use `content.mission_day_str()` for anything stored per mission day (not `today_str()`, which is the calendar date and still drives riddles, the weekly leaderboard and cases).

## Test players (14 Oct 2026)
The smoke test creates one player with device id `smoke-xxxx` and deletes it again itself. To clear the ones made before this
version: `curl -X POST -H "X-Admin-Key: $ADMIN_API_KEY" https://gaamly.ir/admin/players/purge-smoke` (repeat while it answers `"more": true`).

## Weekend case, new format (14 Oct 2026)
New weekend cases follow `docs/weekend-format.md`. Numbers (all in `server/app/economy.py`): early bonus `WEEKLY_EARLY_BONUS` 50,
shows `WEEKEND_SHOWS_PER_CHAPTER` 3 per opened chapter, archive price `WEEKEND_ARCHIVE_COST` 250 (a normal archive case is 150,
the weekend price is higher on purpose). The new column `case_progress.shows` is additive (migration 0021, listed in the CI check).

## What's new («چی تازه شده؟», 14 Oct 2026)
The list is data in `app/lib/data/whats_new.dart` (`kWhatsNew`, newest first). To announce a release: add one `WhatsNewRelease(<build number>, '<version>', '<yyyy-mm-dd>', [WhatsNewItem(id, title, target, tags: [...])])` at the TOP of the list, in the same commit that bumps the build number in `pubspec.yaml`.
- Titles only, in the players' voice («کارآگاه», never «نفر»). `target` is one of weekend, avatars, comments, caseToday, missions (add a case in `whatsNewGo` for a new place).
- The banner shows once per build (prefs `wn_seen`); a fresh install (no saved player) shows nothing. Settings «چه خبر؟» lists the last 5 releases.
- Red «تازه» tags: put `NewTag('<tag id>')` next to the place and list the id in the item's `tags`; call `WhatsNew.i.tagOpened('<id>')` when the player opens that place. A tag disappears when opened or 7 days after the first start of the new build.

## Invite codes, ratings, archive (15 Oct 2026, server 1.26.0, app 1.26.0+54)

- **How an invite pays (server rules, unchanged):** the NEW player gets `INVITE_NEW_PLAYER` (100) coins at once when the code is redeemed (`POST /v1/referrals/redeem`, only for accounts at most 7 days old, never the same phone as the inviter). The INVITER gets `INVITE_INVITER` (150) as an inbox gift after the invited player solved cases on `INVITE_MIN_DAYS` (3) different days; the gift must be claimed in the messages. Tests: `server/tests/test_invites_ratings.py`.
- **Why testers saw no coins:** the code field was only in the profile, the first run never asked, accounts older than 7 days are refused (`only_for_new_players`), and the inviter's coins arrive late. The app now asks once on the first run («کد دعوت داری؟», one-tap «بعداً») and the profile card states the rule and shows the progress.
- **New call `GET /v1/referrals/status`:** can_redeem, rewards, `need_days`, my days (as an invited player), friends invited/paid, the closest friend's days. Bounded to the 50 newest friends; migration 0023 (additive) adds `ix_players_referred_by`.
- **Ratings on case rows:** `GET /v1/cases` rows carry `rating_avg`, `rating_count`, `comment_count`, `my_rating`. The shared part is one aggregate cached 30 s per worker (`app/ratings.py`, cleared when a comment is written or moderated); `my_rating` is one query on `player_id`. A stars-only rating counts at once; a written comment counts after the admin approves it. A player with stars only may add words once (they wait for the admin); the stars never change.
- **App:** the rating step (`RateCard`) after a solve and on every finished case (also archive cases), the rating chip on the home and archive cards, and the new archive screen (progress header, sort, filters, price button, coin chip to the shop). «چی تازه شده؟» release 54.
- Deploy: this is a server change (new call + migration), so it needs the normal Liara deploy; the game APK is built from the same commit.

## Capacity (14 Oct 2026, server 1.25.5)

**Plan (Liara):** app 0.5 CPU / 0.5 GB RAM, Postgres 0.5 CPU / 0.5 GB RAM. `start.sh` runs `WEB_CONCURRENCY` uvicorn workers (default 2).
**Nothing has been measured on the real server yet**: the numbers come from running `tools/load_test.py` (below). Until you have run it,
any "N players" claim is a guess.

### What was changed
- **Database pool per worker** (`app/db.py`): `DB_POOL_SIZE` 5 + `DB_MAX_OVERFLOW` 5 per worker (so 20 connections for 2 workers, far under
  the roughly 100 a small Postgres allows), `DB_POOL_TIMEOUT` 10 s (a request that cannot get a connection fails fast with a 5xx instead
  of queuing for ever), `DB_POOL_RECYCLE` 1800 s. All four are environment variables; change them only if the load test says so.
- **Shared data is cached per worker** (`app/cache.py`, bounded, short TTL, one loader at a time so 200 simultaneous app starts cause one query):
  the config rows read by `/v1/config` and the bell on `/v1/me` (10 s; an admin change clears the cache of the worker that handled it,
  the other worker follows within 10 s); the "how many detectives solved it" counts on `/v1/cases` (30 s; this was an aggregate over the
  whole `case_progress` table on every app start); the public pieces of `/v1/config` (economy, notify plan, upcoming weekend/story, next case
  time: 30 s, and dropped at once when the clock passes a case or chapter opening, midnight or the mission change, so a new case shows up
  exactly on time). Never cached: anything per player, case solutions, hints.
- **Rate limits and shared mobile IPs** (CGNAT): a request with a valid token is now limited by its player (`global_player`), and the per-IP
  ceiling for such requests is a high flood guard (`global_ip_auth`). Requests without a valid token (registration, forged tokens, scanners) keep
  the strict `global_ip`. Registration is unchanged: `register` is 3/min and 10/day per IP, `register_device` 3/day.
  **Watch this at launch:** if many new players come through one carrier IP, `register` (10 a day per IP) will refuse some of them with
  the «امروز از این دستگاه یا شبکه چند حساب ساخته شده» message. If Health shows many `register` blocks, raise it in the Liara environment, e.g.
  `RL_REGISTER=30/60,500/86400` (this trades some abuse protection for not losing real installs).
- **Indexes** (migration 0022, additive, skipped if present): `ix_progress_case_solved (case_id, solved)` and `ix_progress_rank (case_id, stars, seconds)`
  (the rank count after a solve reads only the better players instead of every solver of the case).
- **Admin helper for tests:** `POST /admin/players/smoke-bulk {"n": 200}` makes throw-away «smoke-load-…» players and returns their tokens;
  `POST /admin/players/purge-smoke` removes them.
- Known heavy spots left as they are (measure first): `/v1/me` runs about 8 small queries per call (player, achievements, avatar goals, the bell:
  gifts, broadcasts, badges); `GET /v1/feed` runs the same bell queries. They are indexed per player and cheap one by one.

### CPU per request (server 1.25.7, 15 Oct 2026)
**What was observed:** the 500-player load test from Iran stopped at about 40-50 requests per second whatever `DB_POOL_SIZE` or
`WEB_CONCURRENCY`. The runtime meter (1.25.6) logged cpu=50 % for each of the two workers (one core in total on the 1 CPU plan), pool 19-20/20
in use, 33-88 requests in flight, no 5xx: CPU bound, about 24 ms of CPU per request on average.
**What was NOT measured:** profiling needs the server dependencies and PyPI was unreachable from the workspace, so there is no profile and no
per-endpoint share. The changes below come from reading the code, they are not tuned to numbers, and SQLite (CI) would not be Postgres anyway.
**What was changed** (details in the CHANGELOG): the opening moment of a case is memoised (the case list used to recompute all of them for every
row); the three biggest answers (`/v1/cases`, `/v1/cases/<id>`, `/v1/feed`) skip a second validation; the case/weekend part of the bell/feed is
shared per worker for 60 s; the proxy list of the rate limiter is parsed once. **Still heavy and left alone on purpose:** `/v1/me` runs about 8
queries (achievements, avatar goals and the bell are per player and cannot be cached), `pool_pre_ping` (one extra round trip per connection
checkout, kept for safety), and the JWT check that runs twice per request (rate limiter and `current_player`).
**How to re-test:** deploy 1.25.7, check `https://gaamly.ir/health` (without a VPN) shows the version, set `WEB_CONCURRENCY` to the number of CPUs
of the plan, run `python .\tools\load_test.py https://gaamly.ir -n 500` from Iran, and compare requests/second and p95 with the 15 Oct run
(40-50 req/s). During the run watch the Liara log for `runtime busy pid=... cpu=...%` lines and, afterwards, `GET /admin/api/runtime`
(ask a few times; `cpu_avg_percent` per worker, `requests_per_second`). If CPU is still near 100 % per core at the same rate, the next step is a
real profile (run the app locally with `pip install pyinstrument` and the load test against `http://127.0.0.1:8000`) and then
fewer queries in `/v1/me`.

### Workers: 1 or 2?
Each worker is a separate process with its own pool, its own caches and its own memory rate-limit counters. On **0.5 CPU** two workers
share half a core, so they mostly wait for each other, and each needs its own RAM (the case files are loaded in every worker).
Recommendation: set `WEB_CONCURRENCY=1` on the 0.5 CPU / 0.5 GB plan (the work is waiting for the database, one event loop copes with that,
and the cache takes the repeated queries away), and keep 2 once the app has 1 CPU or more. Do not change it blindly: run the load test with
the current value, change it, run it again and keep the better one. Watch in the Liara panel: app CPU (steadily near 100 % = too small),
app memory (near the 0.5 GB limit = the container restarts), and Postgres CPU/memory/connections. Watch in the admin Health screen: blocked
requests per policy (many `register` or `global_*` blocks = a limit is too tight) and the answer time.

### Runtime meter (server 1.25.6): why is it slow?
Every worker measures itself once a second. Use it during a load test to tell the causes apart:
- **Log line** (Liara logs, only while the worker is busy, at most one per 10 s per worker):
  `runtime busy pid=12 cpu=96% lag_ms=340 pool=10/10 inflight=62 requests=8120 errors_5xx=0`.
- **Admin call** `GET /admin/api/runtime` with `X-Admin-Key`: the last minute of the worker that answered. Ask several times (the
  `pid` shows which worker). Fields: `cpu_avg_percent` / `cpu_max_percent` (share of ONE core), `lag_max_ms` (how late the event
  loop woke up), `pool_out_max` of `pool_limit` (database connections in use), `inflight_max`, `requests_per_second`, `errors_5xx_window`.
- **Reading it:** `cpu` near 100 % and `lag` high = the worker is CPU bound (more CPU, or less work per request). `pool_out_max`
  equal to `pool_limit` with low CPU = requests wait for the database (a bigger pool, or slow queries). Low CPU, low lag, low pool
  use and still slow = the limit is outside the app (the network, the proxy, the database itself).

### Running the load test (from Iran, not from the cloud)
It needs Python 3.11+ and `pip install httpx`. Get `server/tools/load_test.py` from the repository. Use the admin key (the accounts are made
by the admin call, because registering 200 accounts from one IP is correctly refused). Keep the key out of shell history if you can
(`export ADMIN_API_KEY=...` first).

    export ADMIN_API_KEY=your-admin-key
    python load_test.py https://gaamly.ir -n 200                  # 200 players over 60 s
    python load_test.py https://gaamly.ir -n 200 --burst           # 200 players within 20 s (the 21:00 rush)
    python load_test.py https://gaamly.ir -n 1000 --burst          # only after the 200 run was clean
    python load_test.py https://gaamly.ir -n 1000 --ramp 300       # a gentler 5-minute arrival

Run it when few real players are online (not at 21:00): it shares the server with them. The test players are deleted at the end
(`DELETE /v1/me/smoke`); if a run is cut off, `curl -X POST -H "X-Admin-Key: $ADMIN_API_KEY" https://gaamly.ir/admin/players/purge-smoke`.
A test from one computer also tests that computer's connection: if "lost connections" appear but the server is fine, lower `--concurrency`.

### Reading the result
- **Requests/second** is what the server really served; compare it with the arrival you expect (a player makes about 15 requests when the app opens).
- **Answers by status**: `200` good; `4xx` normal answers (409/402 are game rules); **`429`** = a rate limit refused real-looking traffic;
  **`5xx`** = the server failed. `ERR:...` = the connection was lost or timed out.
- **p50/p95/p99** = half / 95 % / 99 % of requests were faster than this (milliseconds). The per-endpoint table shows which call is slow.
- **OK:** p95 under 1000 ms, no 5xx, no lost connections, no 429. The tool prints `VERDICT: OK` or what to look at; its exit code is 1 for 5xx or lost connections.
- If p95 rises sharply between the 200 and 1000 runs, or any 5xx appears, that is the number of simultaneous players the current plan carries.

### When to upgrade
Before a big launch (a store feature, an ad, a Telegram post), move **both the app and Postgres to 1 CPU / 1 GB**, then use 2 workers.
Do it a day before, run the 1000-player burst once, and leave the bigger plan on until the first week's numbers are known. If the load test
shows 5xx or p95 over 1 s at 200 players on the current plan, upgrade even without a launch. This is cheap next to the cost of a first
evening where new players see errors.

## Story kit (ChatGPT writes, Claude validates) - added 17 Oct 2026
Operator-facing summary; the full loop is `docs/story-workflow.md`. Offline tools (Python 3, no packages, no network, no paid API):
`python tools/validate_story.py FILE --chapter N`, `python tools/import_story.py FILE | --inbox content_inbox/story`,
`python tools/validate_case.py FILE`, `python tools/import_case.py FILE`, `python tools/build_prompt.py` (rebuilds `docs/story-chatgpt-prompt.md`).
Imported chapters are drafts under `server/app/content/story/s01/`; the story gate (`STORY_SEASON.opens_at` = 2099) is not touched and
`test_story_kit.py` fails if it is. Importing a chapter is a `server/` change: batch chapters on branch `story-inbox` and let them ride in the next real server push.
