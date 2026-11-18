## «شکار سه‌روزه» (18 Nov 2026, server 1.77.0)

- Admin panel → پرونده‌ها → «شکار سه‌روزه». Make yourself and friends testers first (player page → «تستر شود»).
- «فقط تسترها» + «شروع از همین الان» starts the 47-hour hunt now; a real test is best started on a Wednesday at 22:00 Tehran (the story days then match). Speed ×12 / ×60 is only for a quick look; set it back to «زمان واقعی» and «پاک‌کردن بازی‌ها» before a real run.
- Pictures: `server/app/content/hunts/h001/img/<name>.webp` (cover, killer_photo, howzkhaneh, ev_lantern, ev_tripod, ev_invoices, ev_oldfile, ending, map). A missing picture is simply not shown; adding one needs a server deploy, not a new APK.
- Never open it to «همه» before Amin decides; «پاک‌کردن بازی‌ها» is refused while it is open to everybody.

## Daily leaderboard freshness (15 Nov 2026, server 1.61.3)

Daily summary no longer uses a per-worker TTL cache. One SQL statement counts visible daily solves and computes fastest/median for positive ranked times using window rows in the same snapshot. This works across workers without Redis or cache invalidation. The all-time case-list solver count still includes archive solves; it is a different metric. No migration or environment change. App 1.44.5+94 adds pull-to-refresh and foreground resume refresh to the board, and simplifies desk/settings/shop. Notification battery help no longer points at the removed test row; ordinary reminder scheduling is unchanged.

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
- **GitHub watch:** results are not visible to the server; the card only names the workflow (Liara balance daily 08:00 Tehran).
  The 30-minute «Server watch» (uptime.yml) was removed on 11 Nov 2026 (Amin): it used most of the Actions minutes.

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
| `comment` | POST …/comments (text comments and replies) | player | 2/20 s, 10/h | shared | open |
| `rating` | POST …/rating (stars only; 22 Oct 2026) | player | 5/10 s, 200/h | per worker | open |
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

### Paid but «خرید انجام نشد» (28 Oct 2026, server 1.41.1)
Check in this order: Liara env `BAZAAR_MODE` is `api_secret` (not `fake`) and `BAZAAR_API_SECRET` is the secret from the Bazaar panel
(«API پیشخوان»); admin Health shows `bazaar_mode` and `bazaar_credentials_set`; the admin activity line «خرید … (rejected: REASON)» and
the Liara log line `purchase verify … reason=…` say why: `store_not_configured` = still fake; `bazaar_error:401/403` = wrong or revoked
secret; `not_found` = the token or product id is unknown to Bazaar (wrong package/product id); `bazaar_bad_answer` = Bazaar answered
something that is not a purchase. Refused purchases are not consumed, so players are credited automatically on their next app start once
the check works.

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
- **Proof of investigation (relaxed 25 Oct 2026).** 3 stars and a leaderboard place need active time that follows the case's difficulty and `MIN_SUSPECTS_SEEN` interrogated suspects. Live values come from Liara env: `ACTIVE_TIME_SCALE` (default **0.3**; needed seconds = 90 × difficulty factor 0.67/0.83/1/1.22/1.44 × scale, so about **18 / 22 / 27 / 33 / 39 s** for difficulty 1-5), `MIN_SUSPECTS_SEEN` (default **1**), `DEPTH_MIN_QUESTIONS` (default **1**). **To go back to the strict (old) rules set `ACTIVE_TIME_SCALE=1`, `MIN_SUSPECTS_SEEN=2`, `DEPTH_MIN_QUESTIONS=2`** (60/75/90/110/130 s); nothing else changes. Otherwise: solved, 1 star, normal 1-star coins, `ranked = false`. Active time is measured by the app's ticks and bounded by real elapsed time on the server. All other protections stay (new-account hiding, device/cluster reports, kill switches, delayed answers).
- **Anti-cheat watcher (admin home card, `GET /admin/anticheat-watch?days=7`).** Read-only, cached 60 s per worker, at most 20 000 rows read, no player ids. It always computes the STRICT verdict (`anticheat.strict_verdict`, frozen constants 90 s / factors / 2 suspects / 2 questions, independent of the env) for solved daily/archive cases and shows: the share of solves the strict rules would have made 1-star or unranked (green below 5 %, amber 5-15 %, red above 15 %), split by reason (time / suspects / depth) and difficulty, how many of them the live rules keep at full stars, the daily trend and the median active seconds by difficulty. Use it to decide whether to tighten again (see the env values above).
- **Giving back the lost stars (admin home, button «برگرداندن ستاره‌ها», `POST /admin/anticheat-restore`).** One-time repair of old solves. Candidates: solved daily/archive `case_progress` rows (not weekend, not story, player not banned/tester) whose stored stars are below the natural stars (`eco.stars_for(hints, attempts, proof_misses)`), that FAILED the old strict proof (time/suspects) and PASS the live relaxed proof. Throwaway patterns (a few seconds, no suspect) stay at 1 star. Restored: `stars` to the natural value, `players.stars_total` by the difference (atomic increment), `ranked = true` when the relaxed depth rule passes and it is not a paid retry (a paid retry only gets its stars back). NOT restored: coins, XP, achievements (giving the coin difference is the owner's decision). `dry_run` is true by default (counts only: candidates, stars, by difficulty). With `dry_run=false` it works in batches (`limit` 300, cursor `after`/`next_after`, loop until `done`), one transaction per batch; the column `case_progress.stars_restored` is set in the same `UPDATE ... WHERE stars_restored = false`, so a second call or two workers can never give the same stars twice. Each batch writes one structured log line (`anticheat restore_batch ...`, counts only) and one `admin_log` row (`anticheat_restore`), then clears the weekly-board and solver caches. Kill switch: `ANTICHEAT_RESTORE_ENABLED=false` refuses the apply (the dry run still works). **How to use: deploy the server first, open the admin panel home, tap «برگرداندن ستاره‌ها», read the numbers, then tap «بله، ستاره‌ها را برگردان».** Migration `0032` (additive column) is listed in `ci.yml`.
- **Throwaway accounts.** `START_COINS` is 100. The inviter's 300 coins arrive after the invited player solved cases on 3 different days (`INVITE_MIN_DAYS`), max 5 paid invites a week (`INVITE_PAID_PER_WEEK`) and 1 per device (`referral_payouts` unique rows). Registration: 3 per device and 10 per IP per day (`register` and `register_device` policies, override with `RL_REGISTER` / `RL_REGISTER_DEVICE`; many players share one mobile-network IP, so watch the blocks counter on the admin health screen and raise the IP number if real players are blocked). Since 28 Oct 2026 new and guest accounts ARE on the leaderboards (Amin: a guest who solved a case should see himself). The weekly prizes and the daily draw still skip accounts under 48 h (`HIDE_NEW_ACCOUNT_HOURS`) without email/phone, so throw-away accounts cannot farm coins; because of that a prize rank can differ from the board rank by the skipped accounts. To bring the old hiding back set `SHOW_NEW_ACCOUNTS_ON_BOARDS=false` in Liara and redeploy.
- **First-days offers (28 Oct 2026, `app/welcome.py`).** Accounts younger than `NEWBIE_DAYS` (3): the first paid reopening of a lost non-weekend case costs `NEWBIE_REOPEN_COST` (100) instead of 2x the archive price, and the first archive case of difficulty 1-2 costs `NEWBIE_ARCHIVE_COST` (50). Once each, read from `coin_log` (`reopen:` / `unlock:`). To change or stop an offer edit the constants (set a price to the normal one or `NEWBIE_DAYS = 0`); watch in the economy report whether first-week players come back and still buy coins.
- **Paid but still «خرید انجام نشد» for one player (28 Oct 2026).** The admin activity line shows the reason: `token_used` = the token sits on another account (since 1.41.4 only a GRANTED token blocks; a refused one moves to the paying account at the next try); `wrong_product` = the token was granted under another product; `bazaar_error:401/403` = Liara `BAZAAR_API_SECRET` wrong; `not_found` = Bazaar does not know the token/product (check that `vip_monthly` is an in-app product in the Bazaar panel and not a subscription); `refunded` = Bazaar refunded it. The player just opens the app again: unconsumed purchases are retried automatically.
- **Unique detective names (28 Oct 2026, `app/nicknames.py`).** Table `nickname_claims` (key = normalised name, primary key). The key ignores case, spaces, punctuation, ZWNJ, ي/ی and ك/ک, digit scripts. `PATCH /v1/me` with a taken name answers 422 `bad_nickname` (old builds show «این اسم قابل قبول نیست»; a later build can map a clearer text). Default names «کارآگاه1234» are not claimed. Migration 0034 claims the existing names for the oldest owners; players who already shared a name keep it until they rename. To free a name by hand: delete its row in `nickname_claims`.
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

## Checking notifications on a phone (27 Oct 2026, app 1.40.4+78)
If nightly/weekend notifications stop: open the app → ⚙ → «صدا و اعلان». A line «اعلان‌ها روی گوشی خاموشه» means Android blocks them; tap it (it re-asks, or opens the app's notification settings). If nightly reminders come late or never (Samsung), open «اگه اعلان‌ها دیر میاد» and set the app's battery to Unrestricted and switch off «Put unused apps to sleep». The server side (`notify.json` teasers, `/v1/config` `notify` plan) is unchanged; the phone schedules a week ahead and again each time the app opens or returns to the foreground.

## What's new («چی تازه شده؟», 14 Oct 2026)
The list is data in `app/lib/data/whats_new.dart` (`kWhatsNew`, newest first). To announce a release: add one `WhatsNewRelease(<build number>, '<version>', '<yyyy-mm-dd>', [WhatsNewItem(id, title, target, tags: [...])])` at the TOP of the list, in the same commit that bumps the build number in `pubspec.yaml`.
- Titles only, in the players' voice («کارآگاه», never «نفر»). `target` is one of weekend, avatars, comments, caseToday, missions (add a case in `whatsNewGo` for a new place).
- The banner shows once per build (prefs `wn_seen`); a fresh install (no saved player) shows nothing. Settings «چه خبر؟» lists the last 2 releases.
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

After a committed case solve (nightly or weekend), `weekboard.invalidate()` clears the board cache in that worker so
a player already in its cached top rows sees the added stars on the next read. Other workers can still serve the old
rows for at most the existing 45-second TTL. This requires only the server update: no setting, migration, backfill,
APK or replay of settled prizes. The current week's already-recorded eligible weekend solves are included by the
same query; older archived cases and unranked solves remain excluded. Regression tests: `tests/test_weekend_weekboard.py`.

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

## Detective tools «ابزارهای کارآگاهی» (20 Oct 2026, server 1.33.0, app 1.33.0+66; v2 23 Oct 2026, server 1.37.0)
**v2 (23 Oct):** fingerprint now answers "the name appears in N cards" (never a verdict); magnifier falls back to any non-proof card when
`solution.irrelevant` is missing; weekend cases have tools once per kind per night (`kind@2` key, no migration; story chapters
none); the tray payload has `night`, `how`, `earlier`. The older lines below that say "weekend answers 409" or "fingerprint says
whether touched by the main cards" are superseded. Players learn where tools come from in the app (help sheet), source `tools.how_to()`.
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




## Leaderboard leagues and rank titles (21 Oct 2026, server 1.35.0, app 1.35.0+67)
- 9 profile ranks (`economy.RANKS`), 4 leagues (`weekboard.LEAGUE_DEFS`: the only place with names and limits). A league is a range of ranks: تازه‌کار (تازه‌کار..دستیار کارآگاه, from 0 XP), کارآگاه (کارآگاه..کارآگاه ارشد, 600), بازرس (بازرس..سربازرس, 2500), سرپرست (کارآگاه نخبه..افسانه, 6500). The league comes from the XP at the week's snapshot and stays all week; the row always shows the CURRENT rank title (`economy.rank_of`, same as the profile). A promotion shows next week.
- A player is missing from the weekly board when: no solved ranked case of the week's own cases, `tester`, `banned`, or (only when `SHOW_NEW_ACCOUNTS_ON_BOARDS=false`) younger than 48 h without phone/email (`anticheat.visible_player`). Prize lists always apply the 48 h rule (`prize=True`).
- The app shows one short line; the long text is behind the «i» (`showBoardInfo`). The league switch is always visible.

## Weekend chapters in the app (21 Oct 2026, app 1.35.0+67)
- Uses the existing fields only: card `chapter` (1-based), suspect `appears_chapter` (0 = from the start), `chapters` (opened ones). Seen state: `SharedPreferences` keys `chapter_seen_<case>` and `chapter_banner_<case>`. Code: `app/lib/widgets/chapter_ui.dart`, wiring in `case_screen.dart`. Nightly cases (`chapters_total < 2`) take none of these paths.

## Public pages and the landing site (21 Oct 2026, server 1.35.0)
- URLs for the Cafe Bazaar listing form: **privacy policy** `https://gaamly.ir/privacy`, **terms** `https://gaamly.ir/terms`, **support** `https://gaamly.ir/support` (contact e-mail on the page), account deletion `https://gaamly.ir/delete-account`. All are rate-limit exempt, built at start, cached 10 minutes.
- The texts were written from the code (what is stored: nickname, avatar, hashed phone + last 4, legacy e-mail, device id, invite data, purchases, comments, app version/OS/model, hashed IP in rate counters only). When you change what the game stores or does, change `routers/pages.py` and `UPDATED` in the same push.
- TODO Amin: the contact is `aminsaalem@gmail.com` (`pages.CONTACT` and the app default `support_email`); use a dedicated address when you have one.
- `GET /` serves `app/web/index.html` (landing + demo case «نسخه‌ی گمشده»). The download link is `site.BAZAAR_URL` (TODO: put the real Bazaar page once the app is published). The demo is not in `app/content`, nothing loads it. To change the page, edit the file; there is no database access.

## Stars-only rating route (22 Oct 2026, server 1.36.0)
- `POST /v1/cases/{id}/rating` `{"rating": 1-5}`: stars only, needs a finished case, counts at once, idempotent per player per case (the same `slot=root` row as a comment; a second call, a double tap or a different value later changes nothing and answers 200 `already: true`). A later text comment keeps the stars. Unknown case 404 `no_case`, not finished 409 `finish_case_first`, bad value 422, banned 403.
- Limiter policy `rating`: **5 per 10 s and 200 per hour per player**, relaxed, per worker (two workers, so up to about 400 an hour in practice), fail open. Before, rating shared the strict `comment` policy (2/20 s, 10/h) and a player rating old cases was blocked after 10. `POST …/comments` and its `comment` policy are unchanged (real text and replies; it still accepts a rating-only body for old apps). Env override: `RL_RATING`.
- The app calls the new route for stars and falls back to the comment route when the server answers 404 (an older server). The wait text shows seconds below 90 s, minutes from 90 s («حدود ۵ دقیقه»), hours from 90 min.

## Leaked answers: depth, draw, consistency, report (22 Oct 2026, server 1.36.0, app 1.36.0+68)
Problem: the daily answer is shared in groups, so the daily ranking prize lost its value. A leak cannot be stopped; these make it worthless for ranking.
- **Spoiler-free share card** (app): «پرونده‌ی ۳۴ «عنوان» 🕵️ ۳ پلاک · ۴ مدرک · ۶ دقیقه — تو هم امتحان کن: لینک». It never names the culprit or a clue. The link is the constant `kShareLinkPlaceholder` in `app/lib/services/api.dart` (**TODO Amin: put the real Cafe Bazaar address**); the remote-config key `share_url` overrides it without a new APK.
- **Investigation depth** (`anticheat.depth_ok`): the app reports, with every tick and with the accusation, the evidence cards the player tapped (`cards`) and the interrogation questions asked (`asks`, "suspect:index"). The server keeps the union in `case_progress.cards_opened` / `questions_asked` (migration 0030; ids that are not in the case are dropped, at most 80 each). A solve is **ranked** (daily board, weekly board, daily draw) only when depth passes; an unranked solve keeps its stars, coins, plaques and streak; the result screen says why in plain Persian and one tap closes it. The response carries `ranked`, `unranked_reason` (`depth` | `time` | `retry`) and `depth {evidence, questions, proof_opened, active}`. Weekend and story cases are not gated. Stars and solving are never blocked.
  Settings (Liara env): `DEPTH_GATE_ENABLED=true` (**kill switch**), `DEPTH_MIN_QUESTIONS=1` (was 2 until 25 Oct 2026; 2 = strict), `DEPTH_MIN_CARDS=0` (cards are recorded but not required yet: the app counts a TAP or a pin, and a card can be read without a tap; raise it, e.g. to 3, only after looking at the real numbers in `/admin/suspicious-solves`), `DEPTH_NEED_PROOF=false` (true = at least one card of `solution.proof` must have been tapped), `DEPTH_REQUIRE_REPORT=false` (true = an old app that never reports depth is gated too; switch it on once most players updated). It sits on top of the older proof of investigation (active time + suspects interrogated).
  Log line when it removes a place: `anticheat depth_unranked case=… why=… cards=… questions=… proof=… active=…` (no player data).
- **Daily draw** (`rewards.settle_daily_draws`, runs in the 5-minute job and is safe to repeat): for each of the last 2 closed nightly cases, one winner among ranked, 3-plaque, visible players who solved it as the night's case. Winner = SHA-256 of the case id modulo the sorted eligible ids (deterministic); claimed by the primary key of `daily_draws` (migration 0030), so two workers cannot draw twice. Prize: ONE story warrant in the winner's inbox (no coins, so coin packs are not undercut; warrants stay scarce). **OFF by default since 24 Oct 2026 (Amin): no draw, no inbox message.** `DAILY_DRAW_ENABLED=true` turns it back on (no code change). Log: `daily_draw case=… eligible=… won=…`.
- **Weekly board** (`weekboard.py`): since 31 Oct 2026 the default `WEEK_RANK_MODE=points` orders by plaques (stars), then nights solved, then nights solved on their own night (`was_daily`), then less total time, then older account (10 plaques over 4 nights beat 8 over 5). `WEEK_RANK_MODE=consistency` restores the order of 22-31 Oct (nights first, then on-time nights, plaques, time) for a rollback. `standings` and `my_standing` use the same keys. The weekly prize settlement uses the same standings and stays idempotent. The «i» sheet and the privacy/terms page say: «اول پلاک، بعد تعداد شب‌ها، بعد شب‌های سر وقت، آخرش سرعت».
- **Suspicious solves** (admin, `GET /admin/suspicious-solves`, last 24 h, at most 5000 rows read, lists cut to 50): solves with very low depth or under 60 s of active time; solves with active time at most 25% of that case's median (needs 8+ solves); clusters of 4+ accounts solving within 60 s of each other, inside 300 s, right after 10 quiet minutes. It only flags: ban by hand with `POST /admin/players/{id}/ban`. One log line per cluster: `suspicious_cluster case=… accounts=… span=…s` (no player ids).
- Rate limits: nothing new; the existing limiter is reused.



## Culprit album and first guess (24 Oct 2026, server 1.38.0, app 1.38.0+71)
- **Nothing to set.** Migration 0031 adds only the table `case_guesses` (also created by `create_all`); no new env variable.
- `GET /v1/album` builds the album from the player's own CaseProgress rows (one query) and a per-worker cache of the published cases (30 s, dropped when the next case opens). It is bounded to 600 cards. It also grants the album frames to a player who already finished a group (that is why it locks the player like `/v1/me`).
- Change the grouping in ONE place: `album.group_of`. Frames: `avatars.py` (`frame_album` at 1 group, `frame_album_noir` at 4), drawn in `app/lib/widgets/avatar_frame.dart`.
- Guess percentages: `guess.MIN_PUBLIC = 20` guesses, counts cached 60 s per worker (`guess_counts`, visible in the cache stats). Nothing personal is stored beyond player id, case id and suspect id.
- If the album shows nothing for a player, check that the app is 1.38.0+ (older apps simply do not have the screen); old apps keep working because every new field is optional.


## Update banner and install source (app 1.40.5+79, server 1.41.0; 27 Oct 2026)
**Update notice.** The app reads two numbers from the remote config (admin panel → config, `PUT /admin/config`, keys `latest_version`, `min_version`, optional `update_url`; defaults 1 / 1 and the Bazaar page):
- `latest_version`: the newest build number that is live on Cafe Bazaar. Players whose build is lower see a dismissible card on the home screen with a button to the store (closed for 3 days; a higher `latest_version` shows it again). Set it only AFTER the new build is accepted on Bazaar (for example 79 once 1.40.5+79 is published).
- `min_version`: builds below it get a full-screen page «برای ادامه باید برنامه رو از کافه بازار آپدیت کنی» and cannot play. Use it only for a real emergency (a broken old build); leave it at 1 normally.
- The check fails open: if the config cannot be read, nobody sees a banner or a block. Only players who install build 79 or newer can show it; older installs do not have the code.
- Nothing is set in the database by the release: the defaults show nothing until you raise the numbers.

**Panel block (server 1.55.0, 9 Nov 2026).** The two numbers are no longer set with API calls: admin panel (or the admin app) → tab «⚙ اقدام‌ها» → «📲 بروزرسانی اپ». After you press «انتشار» for a build in Bazaar, put its number in «آخرین نسخه» and save. «حداقل نسخه» locks older builds (the panel asks a second time when active players would be locked out). `GET/POST /admin/api/app-update`; every save is in the admin log as `app_update`.

**Install source.** The app (build 79+) sends the installer package once per start with `POST /v1/me/client` (`installer`, stored in `players.install_source`). The admin overview shows the counts: `com.farsitel.bazaar` = «کافه بازار», `ir.mservices.market` = «مایکت», empty or any other value = «مستقیم/نامشخص». Only players who opened build 79 or newer report it; everyone else counts as «مستقیم/نامشخص» until they update, so the Bazaar number grows as players update.

## First-days offers query on PostgreSQL (server 1.41.7; 28 Oct 2026)
- 1.41.3 to 1.41.6 returned 500 for accounts younger than 3 days (case list, album, case, unlock) on Liara. In the Liara logs it looks like `welcome.py ... offers_for ... session.execute` ending in a PostgreSQL «must appear in the GROUP BY clause» error. Fixed in 1.41.7; deploy it by hand. Players who saw «هنوز پرونده‌ای روی گوشیت نیست» (new accounts, 28 Oct) just need to reopen the app. Never GROUP BY a bound expression such as `func.substr(col, 1, 7)`; test new queries in the wallet-postgres job.

## «Offline» page on a phone that has internet (28 Oct 2026)
- The app counts every failed connection (DNS, TLS, timeout, a 5xx answer) as «offline». Since build 81 the home page shows «کد خطا: …» under the message: `dns` (phone cannot resolve gaamly.ir), `tls` (certificate or wrong phone clock), `timeout`, `refused`, `network`, `html` (a filter or Wi-Fi login page answered), `http500/503` (the SERVER failed: look at the Liara logs), `other`.
- First check the server: a 500 on /v1/cases for new accounts (1.41.3-1.41.6, fixed in 1.41.7) looked exactly like this.
- A public-DNS fallback was tried in build 80 and removed in build 81 (not proven, could not be tested).

## Names from home, Bazaar helpers (app 1.40.6+80, server 1.42.0; 28 Oct 2026)
- Bazaar reviews (admin tab «⭐ نظرات بازار»): needs the Pishkhan token as Liara env `BAZAAR_API_SECRET` (Pishkhan > «API پیشخان بازار» > «دریافت توکن جدید»). Without it the tab says so. A reply goes to Bazaar and is shown to players after Bazaar approves it. Optional `BAZAAR_REVIEWS_BASE_URL` (default https://sandoghche.cafebazaar.ir).
- Upload to Pishkhan: add the GitHub secret `PISHKHAN_API_TOKEN` (Settings > Secrets and variables > Actions). Before building, write the notes of the build in `docs/bazaar-release-notes.md` (a block `<!-- build: N -->` with `## changelog_fa`, `## changelog_en`, `## developer_note`). Pushing a branch to `release` then builds the APK and sends it as an UNPUBLISHED release; press «انتشار رهانه» in Pishkhan yourself after Bazaar's review, then raise `latest_version` in the admin config. A missing token or missing notes only prints a warning. Try it without sending: `bash app/tools/bazaar_upload.sh --dry-run x.apk docs/bazaar-release-notes.md 80` (CI does this on every push).
- Rating card: shows only after a 3-star solve with 3+ solved cases, once per 30 days, never after the button, Bazaar build only.

## Tests on PostgreSQL and duplicate accounts (28 Oct 2026, server 1.43.0)

### How CI is split now
- Job `server`: the whole suite (`pytest -q` in `server/`) on SQLite, plus migrations, the smoke test against a running server and the small load test.
- Job `server-postgres`: the SAME whole suite on a PostgreSQL 16 service container (what Liara runs). `TEST_DATABASE_URL` points at an empty database `suite_test`, `TEST_AUX_DATABASE_URL` at a second one `aux_test` (used by tests that need a private empty database, see `private_engine` in `tests/conftest.py`). Both databases are wiped at the start; a name that does not end in `_test` is refused.
- Job `wallet-postgres`: only the race tests (`tests/test_wallet_concurrency.py`) in their own database `wallet_test`.
- **Rule: every new query is tested on PostgreSQL in CI.** A new endpoint or service needs a test that runs in the suite (so both jobs run it). Typical PostgreSQL-only failures: GROUP BY on a bound expression (`func.substr(col, 1, 7)`: asyncpg binds the numbers differently in SELECT and GROUP BY), comparing a string column with an integer, a `DISTINCT` with a different `ORDER BY`, a missing cast on `func.sum` (returns Decimal), SQLite's lenient types.
- Test accounts: `new_player` makes a brand-new guest (created just now, no email, no phone). Pass `aged=True` only when the test is about something else and needs the normal rules (not hidden from boards, normal prices, no young-account limits).
- Tests that are SQLite-only are marked `@pytest.mark.sqlite_only` and skipped with a reason in the Postgres job. Current list: none.
- `tests/test_first_run_smoke.py` walks the first run of a brand-new guest; every answer must be 2xx on both databases.

### Duplicate accounts (admin: «بازیکن‌ها» → «حساب‌های تکراری», and cards on the overview)
- Securing an account puts the email/phone on the SAME row, so it does not duplicate. A duplicate appears when a secured player opens the app on a new phone or after clearing data: the app registers a new guest row, then the player signs in to the old account (`_login_as` gives the old account the new device id), and the guest row stays with the SAME device id.
- So a device id shared by 2+ rows is one person counted twice. The screen lists those groups (the secured row, the probable orphans, anything else) and the numbers: all rows, distinct devices, devices with several accounts, probable orphans (a guest with no solved case, no purchase, not banned, not a tester, sharing a device with a secured row) and «real people estimate» = rows minus probable orphans.
- READ ONLY. Nothing is deleted or merged. A purge/merge tool can be built if wanted (it must move coins/purchases first and be logged in the admin log).
- `GET /admin/api/duplicate-accounts?limit=&offset=` (at most 200 groups, 2000 rows) and `/duplicate-accounts/summary`. Uses the index on `players.device_id`; it shows nicknames, short ids, phone last 4 only. The real numbers can be read only in the live admin panel.

## Reset a case for a player (server 1.43.2; 30 Oct 2026)
Admin panel → Players → the player → «↺ ریست پرونده». Enter the case number (c020, w004…), press «دیدن آنچه پاک می‌شود», then «ریست کن» and confirm. Only that case for that player is cleared; coins are not refunded and solving it again pays nothing (no coins, XP, warrants). The action is in «اقدام‌ها» as `case_reset`. Limit: 10 a minute (`RL_ADMIN_CASE_RESET`). Story chapters cannot be reset here.



## Streak insurance by the night, lost weekend case, weekend days (31 Oct 2026, server 1.44.0, app 1.41.0+82)
- **Streak insurance** (`streakrepair.effective_streak` / `settle`): the streak and the insurance are settled against the calendar, not at the next solve. Missed = daily cases strictly between `last_daily_solved` and today's case (today's unsolved case is not missed). All-or-nothing: covered only when `0 < missed <= insurance` and the streak is above 0; the streak then grows by the covered nights and the insurance falls by the same number; otherwise the streak shows 0 and the insurance is untouched. Display (profile, board flame, accuse answers) is computed, never written on GET. Settled and written under the player lock in solve, `POST /v1/wallet/streak-freeze` and `POST /v1/wallet/streak-repair`. A broken streak is marked in `player.stats["streak_broken"]` (= `last_daily_solved` at that moment) so insurance bought later does not cover it; the stored streak stays, the repair offer (one missed case, 24 h, once per break) still knows it. `player.stats["streak_paid"]` is the streak value up to which bonus/badge/milestone/warrant were evaluated; a reward fires when the streak crosses a step above it. Watch the log lines `streak_insurance decision=spent|broken`. No setting, no migration.
- **Lost weekend case**: second-chance price = `WEEKEND_ARCHIVE_PRICES[difficulty] x WEEKEND_LOST_REOPEN_FACTOR` (1, so 170-370; daily/archive keep `LOST_REOPEN_FACTOR` 2). Edit the constant in `economy.py` to change it (exposed as `weekend_lost_reopen_factor` in the economy config). A paid second chance on the live weekend case pays archive coins and is unranked (not on the weekly board). Log line `lost_case_reopened` and coin-log reason `reopen:<case>` as before.
- **Weekend days**: chapter 2 of every weekend case published on or after 2026-11-05 opens Friday 09:00 (`at_hours` 24); the validator (`content.WEEKEND_DAY2_FROM`, `WEEKEND_DAY2_AT_HOURS`) refuses anything else for format 3. The case closes Friday 21:00, so day 2 lasts 12 h. Deploy the server from Liara before Thursday 5 Nov 09:00.

## Rank thresholds (server 1.46.0; 1 Nov 2026)
The XP table is `economy.RANKS` (19 ranks, up to 50 000 XP). Changing it needs a data migration like `alembic/versions/0035_rank_thresholds.py` (lift players to the new threshold of the rank they hold, so nobody is demoted); leagues, achievements and frames follow the rank index. The app reads the table from `/v1/meta`.

## Real users (server 1.47.0; 1 Nov 2026)
Admin home cards and «بازیکن‌ها» (filter «گروه»): real, tried, empty, probable duplicate, excluded (see `services/real_users.py`). «Real» means solved a case or has a granted purchase. A duplicate is only a probable match (same device id, or e-mail names that start the same and an older row that went quiet); check a pair by opening both rows. Nothing is removed automatically.

## Purge of worthless accounts (server 1.48.0; 1 Nov 2026)
Admin → بازیکن‌ها → «پاک‌سازی»: lists guests that are certainly worth nothing (rules in `services/purge.py`: abandoned over 14 days, orphan of a secured account, load-test rows) and deletes them after confirmation, 200 at most per press. It is irreversible; the admin log keeps the count and short ids. Run it again until the list is empty. A player whose device was purged simply gets a new guest account.


## Promo case for ads (server 1.50.0; 2 Nov 2026)
- Start: admin panel → «پرونده‌ها» → «پرونده‌ی تبلیغی»: case id (for example `c020`), hours (48), «شروع». End early with «پایان».
  Do it at the moment the video is posted: the clock runs from the click. Several windows can be open (at most 10).
- Who gets it free: only accounts younger than 3 days. Players who already know the game pay the normal archive price.
  A case the player lost still costs the reopen price. Nothing else changes (rewards are the normal archive rewards).
- Link under the video: `https://gaamly.ir/c/c020` (the case id in the end). It shows the title, opening text, hours left and the
  Cafe Bazaar button. It needs the Bazaar address in `site.py` (`BAZAAR_URL`) to be the real one.
- The list is the config row `promo_cases`; do not edit it by hand (a bad row is ignored, so nothing is free by mistake).
- What to watch: ledger lines `promo:<case>` (one per new player who opened it) against `solve` lines of that case.
- The effect is in the panel: «🗂 پرونده‌ها» → «📈 اثر رایگان‌کردن» (signups in the window against the same length before it, free opens, solves, coin buyers). All panel times are Tehran time.
- Not built yet: opening the app straight on the case from the link (needs a change in the APK build).
- Since server 1.60.0 / app 88 (11 Nov 2026): the «hours» field is the length of the CAMPAIGN (set up to 168 = a week while the video
  is on); every new detective gets 48 free hours counted from HIS signup (`promo.PERSONAL_HOURS`), so someone who installs on day 3 of
  the ad still has two days. «پایان» ends it for everybody at once (the kill switch). The app shows the case on the home page under
  tonight's case («پرونده‌ی هدیه‌ی تو · رایگان برای تو · N ساعت دیگه», `free_until` in `GET /v1/cases`) and pins it at the top of the
  archive; it disappears when he opens, solves or loses it, or when his hours end.

## Sign out of an account (app 88, 11 Nov 2026)
- Settings → «خروج از حساب»: only a secured account (phone or e-mail) can leave; a guest is asked to secure it first (no way back).
  The account stays on the server. The phone then shows «از حسابت خارج شدی»: log in to another account (phone number, old e-mail,
  transfer code) or start as a fresh detective. No account is registered until he chooses. A fresh guest still goes through the
  normal registration (strict limit `register_device`: 3 new accounts a day per install), so signing out again and again cannot farm
  the start coins.

## Update thank-you coins («هدیه‌ی آپدیت») (UX pack, 10 Nov 2026)
- Order matters: first publish the new build on Cafe Bazaar, and only THEN set «آخرین نسخه» in the admin panel (block «📲 بروزرسانی اپ»).
  From that moment every player who updates gets `update_bonus_coins` once (default 50, range 0..300, 0 = off).
  Set the number in the same block. The block also shows how many players were paid for the current «آخرین نسخه».
- Rules (server, `POST /v1/me/client`): the previous build (> 0) must be below «آخرین نسخه» and the build now reported must be at
  least it. New installs (previous build 0 or already current) and downgrades get nothing. One payment per player per
  «آخرین نسخه» (ledger reason `update_bonus:<build>`, checked under the player lock, so a race pays once).
- The build number is reported by the app and can be faked, so the server also requires an account created BEFORE «آخرین نسخه» was saved
  and with at least one solved case. A new or empty account earns nothing; one real player lying about his build gets his single gift at most.
- If you set «آخرین نسخه» before the build is on Bazaar, nobody can claim it yet but the banner already shows: do not.
- A newer «آخرین نسخه» opens a new round of gifts, so raise it only for a build worth announcing.

## Detective names (10 Nov 2026)
- Allowed: letters of any language, digits, single spaces, ZWNJ, `_ . -`, 2-16 characters, at least one letter. No emoji, stickers, symbols or
  invisible characters (`nickname_chars`). Blocked substrings (after removing spaces, case-insensitive): `کس`, `کیر`, `کون`, `جنده`, `fuck`, `sex`,
  `admin`, `مدیر`; also links (`http`, `www.`, `.ir`, `.com`, `@`, `t.me`) and more than 6 digits (`bad_nickname`). A name another detective owns is
  `nickname_taken` (compared by key: case, spaces, punctuation and Arabic/Persian letter variants are ignored).

## Archive picks and the weekend tab (UX pack, 10 Nov 2026)
- `GET /v1/cases/picks` suggests up to 3 archive cases per player from real numbers only (see `docs/ux-pack.md` session 4); it needs
  at least 20 real detectives per reason, so a young game simply shows fewer or no suggestions. Nothing to set.
- Economy tab, block «۷. تب «آخر هفته»»: how often the weekend tab is opened, Thursday-Saturday vs the other days (event `weekend_tab_open`,
  once per app launch, only from the new app). Read it after a week of the new version before deciding about the tab.

## GitHub Actions minutes (11 Nov 2026)
- The repo is private, so Actions minutes are limited by the account plan. On 11 Nov 2026 they ran out: jobs did not start («recent account
  payments have failed or your spending limit needs to be increased»). Fix: GitHub → Settings → Billing and plans (payment method or the
  Actions spending limit), or wait for the next month.
- To spend less: CI skips the build branches, newer pushes cancel older runs, the admin menu browser test runs only when the admin page
  changes (`admin-menu.yml`, also by hand from the Actions tab), and the server watch (`uptime.yml`) is gone.

## Hiding duplicate accounts (15 Nov 2026)
- Admin panel → Players → «حساب‌های تکراری»: select guest rows of a device and «پنهان‌کن». They disappear from lists and counts at once.
- 30 days later the screen shows «حذف نهایی N حساب سررسیده»; there is NO automatic job, so press it yourself. Accounts used after hiding are never deleted (they show «بعد از پنهان‌شدن استفاده شده»); restore them.
- Migration 0038 adds `players.hidden_at` (nullable); nothing to set.


## Board header from the table rows, arithmetic mean, new portraits (16 Nov 2026, server 1.66.0, app 1.44.6+95)

`GET /v1/leaderboard?period=daily` returns `daily.solved` = the number of rows the table lists (solved tonight, ranked, visible player), `daily.fastest`, `daily.mean` (arithmetic mean, rounded to whole seconds) and `daily.median` (only for old app builds); times use durations > 0 only. No migration, no environment change. 33 new portraits and 8 staged scene images ship in the app; no case uses them until `usable_from` is set. The nightly draw reward is unchanged; only its help text was removed.


## Detective help and the tool kit (16 Nov 2026, server 1.67.0, app 1.45.0+97)

- `POST /v1/tools/kit` {request_id 8-24 chars [A-Za-z0-9_-]}: buys 3 magnifiers + 2 fingerprint readers + 1 camera. Idempotent through the coin-log reason `kit:<request_id>` under the player row lock; 402 `not_enough_coins` (`need`), 503 `kit_disabled`, 422 `bad_request_id`. Route policy `tool_buy`.
- Environment: `TOOL_KIT_ENABLED` (default true; false hides and refuses the kit; `DETECTIVE_TOOLS_ENABLED=false` also does), `TOOL_KIT_PRICE` (default 280). Public config: `economy.tool_kit` {enabled, price, items}. No migration.
- Nudge events (`help_nudge_shown`, `help_nudge_tapped`, `help_nudge_closed`) go through `/v1/events` and appear in the admin economy report; each nudge shows once per case per player (kept on the phone).
- Watch: kit purchases are logged as `tool_kit_bought`; coin-log rows with reason `kit:*` are the revenue trail.


## Free first case (17 Nov 2026, server 1.68.0, app 1.45.1+98)

- File: `server/app/content/intro/intro01.json` (id `intro01`, number 0, difficulty 2). Never in `all_cases()`, so nothing in the nightly schedule, archive, album or tests that walk the cases sees it.
- `GET /v1/cases` field `intro`: set for a player with `cases_solved == 0`, or one who already has progress on it. Opening and playing it is free; solving pays the normal difficulty-2 reward.
- Kill switch: `INTRO_CASE_ENABLED=false` (default true). No migration.


## Eight leagues (17 Nov 2026, server 1.69.0, app 1.46.0+99)

- Migration 0039 (data only): `UPDATE week_leagues SET league = league * 2`. Runs once with `alembic upgrade head` on deploy. Old league k becomes 2k, and the new XP floors of those indexes equal the old ones, so every snapshot (past weeks, the current week) keeps its players in the same league. Rollback (downgrade) halves the even values.
- `GET /v1/leaderboard?period=weekly&league=0..7`; `leagues` now lists eight entries. Prizes `LEAGUE_PRIZES` 60 / 40 / 25 per league (8 x 125 = 1000 coins a week). No new environment variable (`LEAGUES_ENABLED` still switches everything back to the single board).
- Watch after the deploy: the first settlement (Friday 21:00) should pay up to 24 winners; the admin economy report shows the weekly prize total.
