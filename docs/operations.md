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
| `tool_buy` | POST …/tools/{kind}/buy | player | 3/10 s, 30/h | shared | open |
| `tool_use` | POST …/tools/{kind}/use | player | 10/10 s, 120/h | per worker | open |
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

### Testing a purchase on a phone (Amin; 18 Oct 2026, after Bazaar rejected version code 55)
Bazaar rejected build 55 with «after starting an in-app purchase the message «برای خرید، اپ کافه‌بازار باید روی گوشی نصب و به‌روز باشه» is shown».
**Cause:** the vendored Poolakey plugin never answered the `connect` call, so `await FlutterPoolakey.connect(...)` in `Billing.init()` never
finished, `_ready` stayed false for ever and every purchase hit that toast, even with Bazaar installed and up to date. Since build 61 the
plugin answers, the connection is opened at start, again when the player buys (3 tries of 18 s), on app resume and after a disconnect, and
the shop says WHY it failed (not installed / too old / no answer / key missing / other) with a button to open Bazaar or retry.
How to test before resubmitting:
1. Phone: Cafe Bazaar installed, **logged in with a real account** (a test account of the Bazaar developer panel works for the in-app products),
   good internet, Android 11+ is fine. Install the APK from the GitHub release (`release` build 61 or newer).
2. Open the app, open the shop, tap the smallest coin pack. The Bazaar payment screen must open (Bazaar's own price). If you see
   «در حال اتصال به کافه‌بازار…» for a few seconds that is normal on a slow phone; a dialog with a reason means something is wrong.
3. Pay, come back: coins are added; the product is consumed so it can be bought again. Kill the app during a payment and reopen: «خریدت اضافه شد».
4. The release notes must say «Cafe Bazaar payments: on» (the `BAZAAR_RSA_KEY` secret is set), and Liara needs `BAZAAR_MODE` + credentials (step 3 above).
5. Logs: `adb logcat | grep -i billing` shows `billing: connect attempt N/3 -> notInstalled | tooOld | timeout | none`.

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
- **Proof of investigation.** 3 stars and a leaderboard place need active time that follows the case's difficulty (`MIN_ACTIVE_SECONDS` = 90 s for difficulty 3, scaled by `ACTIVE_TIME_FACTOR`: 60 / 75 / 90 / 110 / 130 s for difficulty 1-5; `eco.min_active_seconds`) and `MIN_SUSPECTS_SEEN` (2) interrogated suspects. Otherwise: solved, 1 star, normal 1-star coins, `ranked = false` (not in the daily/weekly boards or prizes). Active time is measured by the app's ticks and bounded by real elapsed time on the server. To tune, change `MIN_ACTIVE_SECONDS`, the factor table or `MIN_SUSPECTS_SEEN`.
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
- The daily-missions day runs from `NEW_CASE_HOUR` (21:00 Tehran) to the same hour next evening: use `content.mission_day_str()` for anything stored per mission day (not `today_str()`, which is the calendar date and still drives the login reward, the ad limit and riddles).

## Test players (14 Oct 2026)
The smoke test creates one player with device id `smoke-xxxx` and deletes it again itself. To clear the ones made before this
version: `curl -X POST -H "X-Admin-Key: $ADMIN_API_KEY" https://gaamly.ir/admin/players/purge-smoke` (repeat while it answers `"more": true`).

## Weekend case, new format (14 Oct 2026)
New weekend cases follow `docs/weekend-format.md`. Numbers (all in `server/app/economy.py`): early bonus `WEEKLY_EARLY_BONUS` 80 (was 50 until 18 Oct 2026),
shows `WEEKEND_SHOWS_PER_CHAPTER` 3 per opened chapter, archive price `WEEKEND_ARCHIVE_COST` 250 (a normal archive case is 150,
the weekend price is higher on purpose). The new column `case_progress.shows` is additive (migration 0021, listed in the CI check).

## What's new («چی تازه شده؟», 14 Oct 2026)
The list is data in `app/lib/data/whats_new.dart` (`kWhatsNew`, newest first). To announce a release: add one `WhatsNewRelease(<build number>, '<version>', '<yyyy-mm-dd>', [WhatsNewItem(id, title, target, tags: [...])])` at the TOP of the list, in the same commit that bumps the build number in `pubspec.yaml`.
- Titles only, in the players' voice («کارآگاه», never «نفر»). `target` is one of weekend, avatars, comments, caseToday, missions (add a case in `whatsNewGo` for a new place).
- The banner shows once per build (prefs `wn_seen`); a fresh install (no saved player) shows nothing. Settings «چه خبر؟» lists the last 5 releases.
- Red «تازه» tags: put `NewTag('<tag id>')` next to the place and list the id in the item's `tags`; call `WhatsNew.i.tagOpened('<id>')` when the player opens that place. A tag disappears when opened or 7 days after the first start of the new build.

## Warrants, rating sheet, rate nudge, weekend schedule (17 Oct 2026, server 1.29.0, app 1.28.0+57)

- **Free warrants «حکم بازرسی» are scarce** (`economy.warrants_for_solve`, one place for all rules): the player's FIRST solved case ever (onboarding, 1), a streak of 14 and 30 nights (`STREAK_WARRANTS`, 1 each), and every 2nd live weekend case (`WEEKEND_WARRANT_EVERY = 2`: the 1st, 3rd, 5th). CUT: tonight's case (was 1 a day), «all daily missions done» (was 1 a day), streak 3 and 7, every weekend case. Normal player: about one free warrant per two weeks (was about 14 a week). Warrants players already own are untouched; only future grants changed, no migration. Idempotent as before: the grant runs once inside the solve transaction. To change the pace, edit the constants in `economy.py`. The rest is bought with coins: skipping a chapter's 12 h wait costs `STORY_SKIP_COST` (120, falling to 10 as the wait runs down); story mode itself stays closed until Season 1 is done and the app is on Cafe Bazaar.
- **Rating sheet after solving:** a bottom sheet 7 s after the result appears (once per case, remembered on the phone as `flag_rate_sheet_<case>`; skipped if the player already rated, cannot rate, or chose «بعداً»). Uses the same rate call (`POST` comment with rating); the inline card stays as fallback.
- **Rate nudge in the archive:** computed on the phone from the case list (`solved` and `my_rating == 0`), at most once per 3 days (`pref_rate_nudge_at`), closes in one tap, the button opens the «امتیاز ندادم» filter. No new server call.
- **Weekend schedule text:** the server sends `schedule` (`open_weekday`, `open_hour`, `hours`, `text`) inside `upcoming.weekend` of `/v1/config`, built from `WEEKEND_OPEN_WEEKDAY` / `WEEKEND_OPEN_HOUR` / `WEEKLY_HOURS`; the weekend screen shows `text` and its fallback countdown uses the same weekday and hour. One-off cases with their own `open_hour` (w002) still show their own countdown.
- Deploy: server (new field, new grant rule) from Liara, then the game APK from the same commit.

## Funnel and retention (17 Oct 2026, server 1.27.0)

Panel tab **🧭 قیف و ماندگاری** (`/admin/ui`), data from `GET /admin/api/funnel?days=30` (1-90 days; cached 60 s per worker, so a number can be a minute old; «تازه‌سازی» asks again). «کپی به‌صورت متن» copies a plain-text summary to paste to Claude.

- **Where the numbers come from:** only existing tables. **Retention is derived from case activity**, not from app opens: a player «returned on day N» if one of his cases was opened or finished on the Tehran calendar day N days after his signup day. If a player opens the app and does nothing, he is not counted as returned (he is counted in DAU/WAU, which use `last_seen`). Days are Tehran calendar days.
- **Left out of every number:** test accounts (device id «smoke-…») and banned players.
- **Signups:** new accounts per day. **Funnel** (counts and % of registered; each step counts players, not cases): registered → opened a case → finished the FIRST case he opened (solved or failed) → solved the first case → solved cases on 3 different days (the rule that pays the inviter). Steps are independent counts, so «3 days» can include a player whose first case was lost.
- **D1/D3/D7:** share of the cohort active on that day. A cohort is counted only after day +N is over (so D7 of today's cohort is a dot, and the total ignores it). The row «cohorts» says how many signup days the total uses. **DAU/WAU:** players seen in the last 24 h / 7 days, % of all players, and DAU/WAU (stickiness; higher is better).
- **Where players stop:** players not seen for 48 h, by the last stage they reached (never opened; opened but did not finish; finished 1, 2, 3-4, 5+ cases). Under it, the top 10 cases that were opened more than 24 h ago and never finished: a case high here is too hard, too long or too boring.
- **Money:** payers = players with a `granted` purchase; conversion of registered and of D7-retained players; median hours from signup to the first purchase (nearest rank, the lower middle value); purchases per pack in the window with the coins they gave (from the product table; **no prices are shown, none are stored**); quartiles of coin balance of players seen in 7 days and the share with no coins (if the median is near 0, coins are scarce, which is the plan).
- **Gameplay quality:** plaque shares among solves (3 = no mistake), failed share of finished cases, median ACTIVE seconds to solve (cases with no active time recorded are skipped), average hints per finished case; the table lists cases opened in the last 14 days (at most 40): solved %, failed %, median time. Very high solved % with plaque 3 = too easy; low solved % or many failures = too hard.
- **Small numbers:** with a few dozen players a percentage jumps by several points for one player; read the counts next to it.
- **Failure:** if one section fails the page shows a red note for that section only and logs `funnel section failed name=... error=<ExceptionClass>` (no data). Nothing is cached while a section fails.
- **Cost:** a few aggregate queries over the players of the window and their case rows; indexes from migration 0024 (`players.created_at`, `players.last_seen`, `case_progress.opened_at`, `case_progress.finished_at`). Read it once or twice a day, not in a loop.

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


## The game clock, the fair weekly board and leagues (17 Oct 2026, server 1.28.0, app 1.27.0+56)

**One clock: `server/app/gameclock.py`.** Nothing else may compute a game day, a week or a rollover. Everything is
computed with zoneinfo `Asia/Tehran` (no hard-coded +3:30) and stored/compared in UTC. Tests set the time with
`content.now_local` (or `gameclock.set_clock`).

In plain words (قانون ساعت بازی):

- **روز بازی** از ساعت ۲۱:۰۰ تهران شروع می‌شه (لحظه‌ی باز شدن پرونده‌ی شب) و ۲۴ ساعت طول می‌کشه. اسمش تاریخ روزیه که توش شروع شده، یعنی
  همون `publish` پرونده. ساعت ۲۲ شنبه و ۰۲ صبح یکشنبه هر دو «روز بازی شنبه»ن؛ ۲۰:۵۹ یکشنبه هنوز شنبه‌ست و ۲۱:۰۰ یکشنبه شروع یکشنبه.
- **هفته** از **جمعه ۲۱:۰۰** (لحظه‌ی باز شدن پرونده‌ی اول هفته) تا **جمعه‌ی بعد ۲۱:۰۰** (لحظه‌ی باز شدن پرونده‌ی اول هفته‌ی بعد) است:
  دقیقاً ۷ روز بازی و ۷ پرونده‌ی شبانه (جمعه، شنبه، یکشنبه، دوشنبه، سه‌شنبه، چهارشنبه، پنجشنبه). پرونده‌ی جمعه‌شب مال هفته‌ی تازه‌ست و یک هفته‌ی کامل وقت داره.
- **هر پرونده مال هفته‌ای است که توش منتشر شده** (از لحظه‌ی باز شدنش حساب می‌شه، نه از لحظه‌ی حل شدنش). پرونده‌ی آخر هفته (چهارشنبه ۲۱) هم مال همون هفته‌ست و جمعه ۲۱ بسته می‌شه.
- **جوایز هفته** ۱۰ دقیقه بعد از بسته شدن هفته (جمعه ۲۱:۱۰) پرداخت می‌شن (`SETTLE_MARGIN`)، پس جدول بعد از پرداخت عوض نمی‌شه.
- **روز تقویمی** (نیمه‌شب تهران، `gameclock.calendar_day`) فقط برای چیزهای غیر پرونده‌ایه: جایزه‌ی ورود روزانه، سقف تبلیغ و معماها. عمداً عوض نشدن تا کسی وسط شب دوباره جایزه نگیره.
- مأموریت‌ها همون قبل: روز مأموریت از ۲۱:۰۰ شروع می‌شه و اسمش تاریخ **فردا**ست (`content.mission_day_str`)، برچسب‌های ذخیره‌شده معتبر می‌مونن.

Settings (env): `NEW_CASE_HOUR` (default 21), `TIMEZONE` (Asia/Tehran), `WEEK_START_WEEKDAY` (default 4 = Friday; Monday=0),
`LEAGUES_ENABLED` (default true; false = one board for everybody, the kill switch).

What changed from the old behaviour: the week used to run Saturday 00:00 to Friday 24:00 by the midnight of the solve day, and the case
that opened Friday 21:00 had 3 hours left in its week; a case solved before tonight's release counted for the new week. Now see above.
The old rule is gone from the code; nothing is stored differently: `CaseProgress.day` of new solves is the game day (old rows keep the
calendar date; it is only used to count distinct days for invites), and the weekly board never reads `day`: it derives the week from the
CASE (`content.case_week`), so old rows work.

**Weekly points (one definition, `server/app/weekboard.py`, used by the board and by the prizes).** A solve counts for week W when the case
belongs to W (`content.week_cases(W)`: the 7 nightly cases and the weekend case published in W), it was solved and ranked, the player is
visible (not a fresh throwaway account), and it was finished BEFORE W closed (Friday 21:00). After that the case is archive: coins, plaques,
album and achievements yes, weekly points no. Points = plaques (stars). Tie-break: more cases solved that week, then less total time, then
older account. Archive purchases never count. The query is bounded by `case_id IN (<= 8 ids)` and the existing index
`ix_progress_case_solved (case_id, solved)`; the board is limited (50/100 rows) and cached 45 s per worker. A player below the limit gets his
own rank by a count query.

**Prizes (`server/app/rewards.py`).** Settled once per week from the same standings. The primary key of `week_settlements` is the claim, so two
workers can never pay twice (a second caller fails and pays nothing). A prize needs at least 2 cases solved in the week. Leagues on: top 3 of each league get
120/80/50 coins (4 leagues = at most 1000 coins a week; the old single board paid up to 1175); the champion avatar/loupe frame (`weekly_top3`) goes only
to the top 3 of the highest league that has winners, to keep it scarce. Leagues off: the old 300/200/150 and 75 for ranks 4-10. Weeks before 16 Oct 2026
(`FIRST_FAIR_WEEK`) were paid by the old rule and are never touched. The server's `notify_plan` carries a `weekresult` entry (Friday 21:10) that the
app schedules; older apps still announce it on Saturday 10:00.

**Leagues.** `تازه‌کار` (XP below the rank «کارآگاه»), `کارآگاه`, `بازرس`, `سرپرست` (XP from the rank «کارآگاه نخبه»), thresholds = the XP of
`economy.RANKS[0, 2, 4, 6]`. `weekboard.ensure_snapshot(week)` stores the league of every player who solved at least one case in `week_leagues`
once, at the start of the week (the 5-minute weekly job, or the first request), with a marker row, so every worker shows the same league all week;
a player without a row (nothing solved at that time) is in league 0. Promotion is the next week's snapshot. `GET /v1/leaderboard?period=weekly&league=N`
shows league N (default: your own), the answer carries `week_ends_at`, `league`, `my_league`, `leagues`.

Migration `0025_week_leagues` (new tables `week_leagues`, `week_settlements`; listed in `.github/workflows/ci.yml`).


## App testers (17 Oct 2026)
To test story mode before it opens: the tester secures his account with his phone in the app (profile), then call
`POST /admin/players/tester` with `X-Admin-Key` and body `{"phone": "09190000000", "tester": true}` (use the real number;
it is never stored in the repo). Send `"tester": false` to remove it. A tester sees the story and its chapters (only the chapters
that are on `main`), his solves never reach any leaderboard or weekly prize, and nothing changes for other players. The phone
must already be linked to one account; the answer `no_player` means nobody verified that number yet.

## Case categories, weekend format 3 (18 Oct 2026, server 1.31.0, app 1.30.0+61)
- Every case has `category` (7 topics, `content.CATEGORIES`; rules in `docs/case-writing-rules.md` §9). `GET /v1/cases` rows carry it
  (`""` when a case has none), the case file carries it, the app shows it with the difficulty and filters the archive by it.
- Weekend schedule is now Thursday 09:00 → Friday 21:00 (`WEEKEND_OPEN_WEEKDAY` 3, `WEEKEND_OPEN_HOUR` 9, `WEEKLY_HOURS` 36).
  Chapter 2 of a format-3 case opens at +12 h (21:00). Format 3 is described in `docs/weekend-format.md`.
- New column `case_progress.night1` (migration 0027, additive, listed in `.github/workflows/ci.yml`). New route `POST /v1/cases/{id}/liar` shares the strict
  `accuse` rate-limit policy. New numbers in `economy.py`: `WEEKLY_EARLY_BONUS` 80, `WEEKEND_LIAR_REWARD` 10. New achievement `weekend_night1`.
- Nothing to set on Liara. Deploy the server from the panel (version 1.31.0). Old apps keep working (all new fields are optional).



## Wallet transactions and concurrent claims

`await util.add_coins(session, player, delta, reason)` uses an SQL increment with
`RETURNING coins`; a debit additionally requires `coins >= cost`. Insufficient funds
return HTTP 402 without clamping the balance or writing a ledger entry. The delta,
its resulting-balance log, and the purchase/reward state commit together; the helper
never commits. All economy amounts and eligibility rules are unchanged.

The authenticated-player dependency locks the account row **before** a mutating
request reads eligibility, balances, progress, one-time flags, counters or XP.
`GET /v1/me` and `GET /v1/avatars` grant rewards, so they also take that lock;
case-detail GETs lock while creating progress. PostgreSQL uses `SELECT FOR UPDATE`
with a fresh ORM snapshot. Different accounts remain independent. Requests for one
account queue, including store-verification latency (existing network timeouts apply).
SQLite single-process development requests use a transaction-scoped process lock,
released on commit/rollback/close. They do not reserve the database writer before
in-handler rate-limit checks (those use an independent transaction). `last_seen`
writes are deferred until those checks finish. This fallback is not suitable for
multiple SQLite workers and is not proof of PostgreSQL concurrency correctness.

Every new wallet/grant caller must acquire `db.lock_players` before its first
eligibility read, keep flags and ledger in the same transaction, and reacquire after
any intermediate commit. Phone verification does this after burning its OTP.
Background referral jobs lock invitee and inviter together in sorted ID order;
weekly settlement locks its complete winner set before changing player statistics.
Existing unique purchase tokens, broadcast claims, achievements, referral devices /
slots and weekly settlement markers remain the final idempotency barriers.

CI's `wallet-postgres` job provisions a disposable PostgreSQL 16 service and runs
`tests/test_wallet_concurrency.py` on independent connections. It covers stale-wallet
updates, insufficient funds, rollback, spending/reward races, repeated claims,
archive/hints/solves, missions, secure-account grants (including the OTP commit gap),
ads, riddles, purchase tokens and referral slots. The fixture drops/recreates only
the isolated `wallet_test` database schema provided by `WALLET_TEST_DATABASE_URL`;
never set this variable to a live database. Regular CI tests still run on SQLite;
the PostgreSQL tests skip when that explicit test URL is absent. No new production
variables, schema migration or economy configuration are required.

## Long-term streak: ladder, frames, flame and the paid repair (20 Oct 2026, server 1.32.0, app 1.32.0+65)
- **Ladder** (`economy.STREAK_MILESTONES`): 3, 7, 14, 30, 60, 100, 200, 365. The coin and warrant rewards did not change (60 coins every 7 nights, a warrant at 14 and 30, badges 7/30/100). 60, 200 and 365 give **only** a permanent frame (`frame_blaze`, `frame_inferno`, `frame_eternal`, drawn in code) and an achievement with XP and 0 coins. `streak_badges` in `/v1/config` stays `[7, 30, 100]` for old apps; new apps read `streak_milestones` and `AccuseOut.streak_milestone`.
- **Flame:** `LeaderRow.streak` (daily, weekly, all-time) is the *live* streak: 0 when the last daily case solved is older than yesterday's, bounded to 9999. No extra query: it uses the player rows the board already loads (`streakrepair.LiveStreak`).
- **Repair:** `POST /v1/wallet/streak-repair`, offered in `GET /v1/me` as `streak_repair {key, streak, price}` (null when not allowed). The server offers it only when the player missed exactly ONE daily case, tonight's case opened less than 24 h ago, the streak is at least 3, no streak insurance is held, and this break was not repaired (`streak_repairs` has UNIQUE (player, broken_after); `players.streak_repair_mark` stops a second offer until the player has played again). One transaction under the player lock: coin debit, ledger row `streak_repair`, bridge the missed night. A double tap pays once (the loser gets 409 `not_eligible`). Not enough coins: 402 `not_enough_coins`.
- **Price** (`economy.streak_repair_cost`): `min(500, 200 + 5 x streak)`: 215 coins at 3 nights, 350 at 30, 500 from 60 nights. Always above the insurance (`FREEZE_COST` 150).
- **Kill switch:** `STREAK_REPAIR_ENABLED=false` hides the offer and answers 403 `repair_disabled`. Rate limit: the strict `wallet` policy (`RL_WALLET`), because the route is under `/v1/wallet/`.
- **Logs:** one line per decision, no player data: `streak_repair decision=repaired|not_eligible|not_enough_coins|already_repaired|disabled streak=N price=N` (logger `streak`). Count them in the Liara logs to see conversion.
- Migration 0028 (`players.streak_repair_mark`, table `streak_repairs`), additive.

## Economy health «اقتصاد سکه» (21 Oct 2026, server 1.34.0)
Admin panel tab «🪙 اقتصاد سکه» (`GET /admin/api/economy?days=14`, 1-60 days, cached 60 s per worker, `app/services/economy_report.py`).
It answers one question: is the coin economy fair enough that players stay AND pay? Derived from `coin_log`, `players`,
`case_progress` and `case_tool_uses`; smoke-test and banned players are left out; no player id or nickname in the answer; a failing
section returns `{"error": "section_failed"}` and the rest still works.
- **Flow:** coins given (by source) and spent (by item), and the split of spending into *desire* (avatars/frames, archive, streak
  insurance, story skips, riddle unlocks) and *escape* (hints, detective tools, reopening a lost case, mending a streak). Mostly
  escape spending means the game earns from frustration; it feels like a trap and players leave.
- **Balances:** coins of players active in the last 7 days in buckets, and the share who can afford the first hint. Many above 700 =
  prices too low or nothing attractive to buy; many at 0 = pressure too high.
- **Cases, hints, tools:** failed %, share of finished cases with 1/3 hints, average hints, tool uses by source (free / stock / coins).
- **After a loss:** of the cases lost, how many players opened another case afterwards, and how many paid the second chance.
- **First day:** new players who spent coins on a hint/tool/reopen in their first 24 h versus the others: did they come back later
  (seen again 24 h+ after signup)? A sample of at most 5000 newest players.
- **Notes:** a few plain sentences (`economy_report.notes`) such as "62 % of spending is escape". They are a guide; they need days of data.
- **Prices set 21 Oct 2026 on this reading:** hints 40 / 80 / 120 (were 30/50/80), tools 35 / 65 / 100. The first hint stays within reach of a
  new player (100 coins), the third is about one day of full free income. Review after a week of the screen's numbers.

## Detective tools «ابزارهای کارآگاهی» (20 Oct 2026, server 1.33.0, app 1.33.0+66)
Three consumables on the daily case screen. They narrow the search, never solve it: no card is named, the culprit is never
said, plaques and stars are untouched, and a tool never counts as investigation (active time and interrogated suspects are
what anti-cheat reads, so a solve with tools alone is still unranked).
- **Tools** (`app/tools.py`, `app/routers/tools.py`): `magnifier` marks ONE card «بی‌ربط»; `fingerprint` says whether a chosen
  suspect is touched by the main (proof) cards; `camera` shows one extra neutral line about a chosen suspect. Once per case
  per kind (`case_tool_uses` is UNIQUE per player, case, kind) and the result is stored there, so it stays pinned on the case.
- **Routes:** `GET /v1/cases/{id}/tools` (tray: price, stock, `available`, `usable`, `used`, `result`, `suspects`),
  `POST /v1/cases/{id}/tools/{kind}/use` (stock or the one-time tutorial tool; 409 `no_tool {price}` otherwise) and
  `POST /v1/cases/{id}/tools/{kind}/buy` (coins; buys one and uses it in the same transaction). Body `{suspect}` for
  fingerprint and camera. Daily cases only: weekend/story answer 409 `tools_not_for_this_case` and the tray says so.
- **Prices** (`economy.TOOL_PRICES`): magnifier 35, fingerprint 65, camera 100 (hints are 40/80/120; both raised on 21 Oct 2026, were 25/45/70 and 30/50/80). The first of each kind per
  player is free ONCE (`player_tools.free_used`, claimed by a guarded UPDATE). The only other free source is a rare drop at
  existing reward points: the 7th chest day in a row (`ChestOut.tool`, kind rotates) and the achievements in
  `economy.TOOL_DROP_ACHIEVEMENTS` (streak_30 fingerprint, cases_50 magnifier, interrogate_10 camera).
- **Atomicity:** the player lock (`current_player`) serialises a player's requests; the unique `case_tool_uses` row is written
  first (a double tap loses there, before any coin or tool moves); coins go through `add_coins` (guarded), stock through
  `UPDATE ... WHERE count >= 1`. A double tap or two workers charge/spend once. Not enough coins: 402 `not_enough_coins`.
- **What the case file must provide** (docs/case-writing-rules.md §10): `solution.irrelevant` (1-2 evidence ids the author
  certifies as not needed; never a proof card and never one the explanation cites) for the magnifier, and `suspect.camera`
  (a line or up to 3, 20-160 characters, neutral) for the camera. The server refuses a file that breaks this. Without that
  data the tool is simply not offered on that case (the tray hides it) and nothing is charged. `camera` lines are stripped
  from the public case JSON. The fingerprint needs no data: it is offered when 2..n-1 suspects are touched (the culprit plus
  everybody named in a proof card), so a "yes" is never "this is the culprit" (29 of the 50 cases at launch).
- **Kill switch:** `DETECTIVE_TOOLS_ENABLED=false` hides the tray (`enabled: false`), refuses use/buy with 503
  `tools_disabled` and stops the drops. Rate limits: `tool_buy` (strict) and `tool_use` (relaxed), `RL_TOOL_BUY`, `RL_TOOL_USE`.
- **Logs** (logger `tools`, no player id): `tool_used kind= case= source=free|stock|coins price=`, `tool_nothing_new`,
  `tool_granted kind= n= why=chest|achievement:<id>`. Count `source=coins` in the Liara logs to see revenue.
- Migration 0029 (`player_tools`, `case_tool_uses`), additive, listed in `.github/workflows/ci.yml`.

## Lost cases and the second chance (20 Oct 2026)
A lost case (failed, not solved) is closed for that player: 402 `locked` + `lost: true` on the case, its stats and the answer, until the player pays `reopen_lost_cost` (2 x the archive price of its difficulty, set by `LOST_REOPEN_FACTOR` in `server/app/economy.py`, shown in `/v1/economy` as `lost_reopen_factor`). Look for the log line `lost_case_reopened` and the coin-log reason `reopen:<case>`. To change the factor, edit the constant and push to main once; the app reads the price from the case list, so no APK is needed for a price change.

## Delegated aggregate analytics (19 Oct 2026; opt-in, no admin access)

`GET /v1/analytics/funnel?days=30` returns the existing funnel/retention report, including aggregate purchase counts,
coin-balance quartiles and per-case completion metrics. It accepts **only** `X-Analytics-Key`. It grants no admin UI,
player listing, email/phone/device access, payment-token access, gifts, bans, wallet changes or config writes.
The original `X-Admin-Key` routes are unchanged. No database migration or APK is needed.

The route is disabled until BOTH environment settings exist:

- `ANALYTICS_API_KEY_SHA256`: lowercase SHA-256 hex digest of a separate random key (not the raw key).
- `ANALYTICS_API_KEY_EXPIRES_AT`: expiry in Unix seconds (UTC). Missing/zero/past expiry refuses access.

Generate the credential on your own trusted computer; never paste its output into GitHub, build logs, tickets or the app:

```bash
python3 - <<'PY'
import hashlib, secrets, time
key = secrets.token_urlsafe(32)
print('Private reader key (share only through your approved secret channel):', key)
print('ANALYTICS_API_KEY_SHA256=' + hashlib.sha256(key.encode()).hexdigest())
print('ANALYTICS_API_KEY_EXPIRES_AT=' + str(int(time.time()) + 7 * 86400))
PY
```

Set only the digest and deadline in Liara's environment, then apply the reviewed server change through the owner's
normal deployment. Merely pushing a feature branch does not enable access. Do not reuse `ADMIN_API_KEY` or `JWT_SECRET`;
the report authentication explicitly refuses either as the delegated key. Keep the raw reader key separate from admin
credentials. To revoke: clear the digest and restart/redeploy workers. To rotate: replace the digest and deadline and
restart/redeploy workers; the old key stops working. After the deadline, requests fail even when the report is cached.
All worker processes need the same environment. This is one delegated credential, not a new admin account.

Read the report from a trusted client. The following prompts for the key without echoing it or putting it in command-line
arguments, sends it only as an HTTPS header, rejects redirects (so a credential cannot follow a redirect to another host),
and saves ONLY aggregate data to `funnel-report.json`. It never needs the main admin key:

```bash
python3 - <<'PY'
import getpass, json, urllib.request
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None
key = getpass.getpass('Reader key: ')
request = urllib.request.Request('https://gaamly.ir/v1/analytics/funnel?days=30',
                                 headers={'X-Analytics-Key': key})
with urllib.request.build_opener(NoRedirect()).open(request, timeout=60) as response:
    data = json.load(response)
with open('funnel-report.json', 'w', encoding='utf-8') as output:
    json.dump(data, output, ensure_ascii=False, indent=2)
print('Saved funnel-report.json')
PY
```

A connected reader needs the raw limited key through an approved secret channel, OR the owner can supply the JSON export;
creating this endpoint alone does not grant an assistant live access. If there is no secure credential channel, use the export.
The current GitHub connector cannot store Liara environment variables or authenticate arbitrary private HTTP APIs.

Controls: `days` is 1..90 (default 30); a dedicated existing-limiter policy allows 6 requests/minute and 60/hour per IP,
shared via Redis or the database and fail-closed if that store fails. `RL_ANALYTICS` uses the usual override format.
Report queries are SELECT-only; the limiter's own counters can still write to `rate_hits`. Auth is checked before report
queries and on every cached response. Internal cache is bounded to 4 windows, 60 seconds per worker; HTTP responses are
`Cache-Control: no-store`. Nested response models whitelist aggregate fields and reconstruct the summary from that data.
Do not record the reader header in a proxy/access-log configuration. Small cohorts still expose business-sensitive
aggregate information: give the key only to a trusted analyst. Retention still measures case open/finish activity, not
all app sessions; purchase counts are not actual paid currency amounts. No metric definition changed in this patch.

Rollback: disable/revoke the credential first; removing this optional route/settings has no effect on existing clients or data.
CI covers denied/default/expired/rotated credentials, admin-scope isolation, window bounds, nested-field filtering,
partial errors, bounded caching and absence of business-data writes.

## Preparing an external content root (CONTENT_DIR)

This is preparation only. Existing JSON files stay in this repository and already-public
answers remain public, including in Git history, forks and old APKs/caches. Setting an
environment variable does not revoke any of those copies or change repository visibility.

With CONTENT_DIR unset/empty, runtime loading is unchanged: server/app/content is used.
Set CONTENT_DIR to an absolute directory containing the complete bundle:
- cases/*.json: nightly/archive cases, with their existing IDs.
- weekly/*.json: weekend cases and their chapter schedules.
- story/sNN/chNN.json: story chapters; empty story/ is allowed.
- riddles.json: the existing riddle pool.
- notify.json: optional notification teasers; missing/broken teasers retain their current safe fallback.

All runtime consumers (cases, weekend, story, riddles and notification planning) use this
single root. There is no per-file fallback/overlay onto the bundled public content.
An explicitly configured root must contain cases/, weekly/, story/ and riddles.json;
a missing/incomplete root fails clearly. Relative paths resolve against the server's
working directory; prefer an absolute mount path. Content is cached at startup: restart
all workers after changing the path or bundle, rather than attempting a hot swap.

Read-only inventory, from server/:
```sh
python tools/unpublished_content.py
CONTENT_DIR=/private/content python tools/unpublished_content.py --at 2026-10-20T01:00:00+03:30
```
The JSON allowlist contains only kind, ID, chapter index, opening time and (when needed)
an unscheduled-season reason. It never exports prose, suspect names, answers or hints.
Daily/weekend publication uses content.opens_at (including a weekend open_hour override);
weekend chapters use at_hours. Story chapters follow the current season's global opening
gate, not their placeholder publish date or a player's personal wait/warrant status.
Other seasons have no invented release date and appear as unscheduled. At the exact opening
instant an item is published. Dates display in Asia/Tehran; an explicit --at needs an offset.

For a later private migration: provision a complete versioned bundle outside public Git,
web/static roots, APK assets and public CI artifacts. Restrict host filesystem access to
the service account; mount it read-only at an absolute path using the host's private storage
mechanism. Validate the bundle and run the inventory in an isolated environment before
pointing the service at it. Keep IDs stable to preserve player progress. Stage a complete
new directory, switch the configured path, then restart all workers together. Do not print
the bundle or secrets into deployment logs. Provisioning, content removal, secret changes,
repository settings and deployment are deliberately not performed by this preparation.

Rollback: restore the previous complete private bundle/path and restart all workers.
Unsetting CONTENT_DIR restores the bundled default, which can be older and public;
only use that fallback intentionally after checking its content/version. No database
migration is needed and this mechanism never rewrites existing player progress.


