# Changelog

## server 1.24.2, app 1.24.2 (build 50): email sign-up removed

- The app no longer offers email + password (it was never verified). Securing an account is phone-only. Existing email accounts keep working: the sign-in sheet has a small «ایمیل قدیمی» tab and the phone gate asks them to link a number. The change-password row is gone.
- Server: `POST /v1/auth/email` answers 403 `email_closed` for an account without an email unless `EMAIL_SIGNUP_ENABLED=true` (default false), so old app builds can't create new email accounts. Google login is postponed until we know it works for players in Iran.

## server 1.24.1, app 1.24.1 (build 49): email accounts must link a phone

- Profile has `needs_phone` (email-secured, no phone yet). The app then shows a full-screen, non-closable «حسابت رو به شماره‌ات وصل کن» until the phone is verified; everything stays on the account and no second reward is paid. Guests are never forced; new installs keep the soft prompts. Kill switch: `REQUIRE_PHONE_FOR_EMAIL=false`. Email login still works as a backup. Old app versions do not show the screen.

## server 1.24.0, app 1.24.0 (build 48): messages hub, missions card, suspect intros

- App Home: the mail icon is gone. The avatar (top right) now has a small bell and a red unread pill; tapping it opens the new «پیام‌ها و نشان‌ها» screen (profile card, messages/notifications with filters and «خواندن همه», gifts with «دریافت N سکه», and the badge wall: gold for earned, grey dashed for locked, tap a badge for how to earn it). The same bell sits at the top of the weekend, story, leaderboard and profile screens and in the case header; the number is one shared value, so all bells change together.
- App Home: «مأموریت‌های امروز» is now a big card right under tonight's case (chest, progress ring, three missions with bars, a button to the right place «ادامه: …» or «باز کردن صندوقچه», chest streak, countdown to midnight). The case hero card is unchanged.
- App case screens: «آدم‌های پرونده» snap rail under the case text (portrait, name, role, intro), small portrait chips on evidence cards that name a suspect (tap = quick peek, then the full suspect sheet), intro line in the Suspects tab. Old cached cases without intros show nothing extra.
- Server: `GET /v1/feed` (merged feed: gifts, badges, nightly/weekend openings, announcements; max 40, last 14 days), `POST /v1/feed/seen`, `unread` in `GET /v1/me`. New `players.feed_seen_at` (migration 0018, additive, listed in CI). Gifts are still claimed with the existing inbox claim (pays once).
- Content: every suspect of all 50 nightly cases, w001, w002 and s01ch01 has a neutral `intro` (20–90 characters, 270 in all). The validators now require it; `docs/case-writing-rules.md` tells the writing tasks to add it to new content.
- Deploy: needs the server to be deployed (new endpoint and intros); the app works with the old server (no bell number, no intros) until then.

## server 1.23.0, app 1.23.0 (build 47): secure the account with a phone number

- App: «امن کردن حساب» is now phone-first (number, 5-digit SMS code, resend countdown; email stays as a link). Offers: a sheet after the first solved case (once), a sheet before the first coin purchase (once per app start, «ادامه‌ی خرید بدون امن کردن» closes it and the purchase goes on), a bold card on Home until secured, a red dot on the Profile tab, «ورود با شماره‌ی موبایل» in the sign-in sheet. Profile/Settings show the masked number.
- `SECURE_REWARD` 200 → 100 (coin rebalance). Privacy and delete-account pages mention the phone number.
- Needs on Liara: `SMS_MODE=ghasedak`, `SMS_API_KEY`, `SMS_TEMPLATE`, `PHONE_PEPPER` (see 1.22.0).

## server 1.22.1: «پیامک تست» in the admin panel

- Health tab: type a mobile number and send one real code SMS to check Ghasedak (key, template, plan). Shows what the provider answered when it fails. Limits as for players (1 a minute per number, daily ceiling). `POST /admin/api/sms-test`.

## server 1.22.0: phone-secured accounts (SMS code, Ghasedak)

- New endpoints: `POST /v1/auth/phone/send` + `/verify` (a logged-in player adds a phone number; one number per account; the one-time `SECURE_REWARD` is paid like for email), `POST /v1/auth/phone/login/send` + `/login` (new device: code to the number, logs the old device out). `secured` in the profile is now true for email OR phone; new field `phone` (masked, last 4 digits).
- Only a keyed HMAC of the number is stored (`players.phone_hash`, unique) plus the last 4 digits; codes are 5 digits, hashed, valid 5 minutes, 5 wrong tries burn them. Migration 0017 (+ table `phone_codes`), listed in CI.
- SMS costs money, so everything is strict and fail-closed: `sms_send` (per IP 3/10 min, 10/day), `sms_phone` (1/min, 3/h, 6/day per number), `sms_device` (6/day), `sms_daily` (3000/day for all, `RL_SMS_DAILY`), `sms_verify` (10/10 min per number). A number that is already taken, or unknown at login, costs no SMS. `SMS_ENABLED=false` is the kill switch. Setup in `docs/operations.md`.
- Error codes: `bad_phone`, `phone_taken`, `phone_already_set`, `bad_code`, `code_expired`, `sms_unavailable`, `sms_failed`.

## server 1.21.2: no culprit hint for hasty accusations

- «Right person, wrong proof» told a probing throwaway account who the culprit is. Now only a player who investigated (180 s active, 2 suspects interrogated: the same bar as 3 stars) gets that nudge and the free proof misses; a hasty accusation of the culprit with wrong proof gets the plain «wrong_suspect» answer and costs a try. Players who read the case first see no difference. Server only, no app build.

## server 1.21.1, app 1.22.1 (build 46): anti-cheat

Every case has one answer, so the threats are a throwaway account that loses a case and reads the answer for the main account, and farming coins with many accounts. Rules (details in `docs/operations.md`, section Anti-cheat):

- **Delayed answer.** A lost case no longer returns the culprit, proof or explanation until the case closes: nightly case, the next case opening; weekend case, its closing; story chapter, 24 h after the failure; archive cases, at once. The result screen shows «پاسخ ‹وقت› منتشر می‌شه» with a countdown and the case page shows the solution by itself once it is public. Solvers still see the explanation. `/stats`, the case detail and the story outro/thread are closed the same way (new `case_progress.reveal_at`, `answer_at` in the API).
- **Proof of investigation.** 3 stars and a leaderboard place (daily, weekly) need `MIN_ACTIVE_SECONDS` = 180 s of active time and 2 interrogated suspects; otherwise the case is still solved but with 1 star, the normal 1-star reward, no leaderboard entry. The result screen says «برای ۳ ستاره، پرونده رو کامل بررسی کن». Old apps that send no active time can only get 1 star. (`case_progress.ranked`)
- **Throwaway accounts earn little.** `START_COINS` 150 → **100**. The inviter's reward is paid only after the invited player solved cases on **3 different days**, at most **5 paid invites a week** per inviter and **1 per device** (table `referral_payouts`, unique rows, `players.referral_paid`); the invited player still gets his 150 at once. New registrations: **3 per device and 10 per IP per day** (HTTP 429 with a friendly message the app shows). Accounts younger than **48 h** without email are hidden from all leaderboards and weekly prizes (they still play).
- **Per-player shuffle** of suspects and evidence (deterministic from player id + case id, ids unchanged).
- **Scripts.** `accuse` was already 1 request / 3 s and 20 / h per player; registration limits above; Myket/Bazaar tokens were already verified with the store and unique (`purchases.purchase_token`), nothing to change.
- **Cheat report.** `GET /admin/cheat-report?days=7` (admin key): devices with 3+ accounts, solves under 60 s of active time, 4+ new accounts with the same first answer within 10 minutes. A short weekly summary is written to the admin log (`cheat_report`). Ban with `POST /admin/players/{id}/ban`.
- Migration 0016 (columns `players.referral_paid`, `case_progress.ranked`, `case_progress.reveal_at`, table `referral_payouts`), listed in CI. Rate-limit counter rows are now kept 49 h (daily windows).

## server 1.21.0, app 1.22.0 (build 45): story chapters with choices

- **Story mode becomes interactive** (Bandersnatch style): a chapter is a few short scenes, each with 2-3 options; a choice can lock or open paths and relationships, an option can be locked until a clue from earlier is held, and nothing blocks finishing the chapter. After the last scene the normal interrogation and accusation continue unchanged. New **season case board** («تابلوی پرونده»): people with a relationship state, clues held, locked or skipped clues in gray.
- Server: `scenes` / `ending` / `board` in the chapter JSON, validated by `validate_story` (reachable, no dead ends or loops, locked clues obtainable earlier); endpoints `GET /v1/story/chapter/{id}/state`, `POST /v1/story/chapter/{id}/choose`, `GET /v1/story/board`; table `story_state` (migration 0015, listed in CI). Chapters in the old format still play (one scene, one «شروع» option); chapter 1 is only wrapped in the new structure. Format and authoring rules: `docs/story-mode.md` (`FORMAT_READY: choices-v1`).
- **Story is still paused** on production (opens_at 2099); it is reactivated after the new app is installed and tested.

## server 1.20.2: admin panel look

- All tabs are visible on a phone (they wrap into rows instead of hiding to the right), so players, comments and actions are easy to find. New quick buttons on the first screen: pending comments, message/gift to everyone, players (ban, coins).
- The panel uses the game's font (Vazirmatn, served from `/static/fonts/`, three fixed files) with bigger, tabular numbers.
## admin app 1.0.1 (build 2): panel questions work

- The admin app now shows the panel's confirm / notice boxes as normal dialogs, so ban, gift / message to everyone, unlock IP and delete comment work even with an older panel (server 1.20.0). Build with `release-admin`.

## app 1.21.1 (build 44): comments button on every finished case

- The case screen of a solved or failed case (daily, archive, weekend) now has the «نظر کارآگاه‌ها» button under the statistics, not only the result screen.
## server 1.20.1: admin panel works in the admin app again

- Ban, gift / message to everyone, unlock IP and delete comment did nothing inside the admin app: its web view shows no browser pop-ups, so `confirm()` answered «no». The panel now asks in the page itself (`ask()`) and shows a small notice instead of `alert()`. No admin APK rebuild is needed.

## server 1.20.0, app 1.21.0 (build 43): case comments, stars and replies

- A detective who **finished a case** can leave 1-5 stars and a comment (3-300 characters, no links or @ids), once per case; others can reply (2-200 characters) to approved comments. Everything waits for the admin: the writer sees their own comment marked «در انتظار تأیید», nobody else does. A rejected comment can be rewritten. Entry point: «نظر کارآگاه‌ها» button on the result screen.
- **Admin panel**: new tab «💬 نظرها» (pending / approved / rejected / hidden, filter by case with pending count and average stars). Actions: approve, reject, hide, delete (logged in `admin_log`). The admin app shows the panel, so no admin APK rebuild is needed.
- Server: table `case_comments` (migration 0014, listed in CI), routes `GET/POST /v1/cases/{id}/comments`, `/admin/api/comments*`, rate limit policy `comment` (2/20 s, 10/h per player), kill switch `COMMENTS_ENABLED=false`. Also carries the «کارآگاه» wording build (app 1.20.6).

## app 1.20.6 (build 42): «کارآگاه» instead of «نفر»

- Everywhere the app counts players it now says «کارآگاه» («۱۰ کارآگاه حلش کردن», «۱۰ کارآگاه اول», «اولین کارآگاه باش!», invite-code message, guide). Story text of the cases still says «نفر» for people in the story; suspects are counted as «مظنون» in the new cast strip.

## server 1.19.2, app 1.20.5 (build 41): Cafe Bazaar billing + detective icon

- **Payments now go through Cafe Bazaar** (Poolakey plugin) instead of Myket; Myket is switched off for now (the server still understands `store: myket`, nothing sends it). The app needs the secret `BAZAAR_RSA_KEY` (GitHub secret, the RSA public key from the Bazaar developer panel) at build time; the server needs `BAZAAR_MODE` (`api_secret` or `oauth`) and its credentials on Liara (see docs/operations.md). Share/update links point to the Bazaar page; the health screen flags `BAZAAR_MODE=fake` in production.
- **New app icon**: the detective with magnifier and case file (launcher, adaptive icon, in-app logo, 512 px store icon `app/tools/launcher/store/icon_512.png`).

## server 1.19.1: admin panel look, tab fix, readable charts

- Panel: new look (gradient header, pill tabs that scroll sideways, coloured KPI cards); the open tab is remembered, and a slow answer from a previous tab can no longer overwrite the current one. «فعالیت زنده» rows no longer jump to «بازیکن‌ها» when tapped by accident: only the player name is a link.
- «نمای کلی» charts now print the value on every bar, show today / total / daily average / best day (and the change since yesterday), an average line, and tapping a bar shows that day's date and number.
- Admin app: branded splash, lock and key screens, gradient app bar (rebuild with `release-admin`).

## server 1.19.0, app 1.20.4 (build 40): rate limiter + «درباره‌ی برنامه»

- **Rate limiter** rewritten: a policy table (burst + sustained tiers, every value overridable with `RL_<NAME>`), shared counters
  for the strict limits (`rate_hits` table, or Redis when `REDIS_URL` is set), bounded in-memory counters for the generous ones,
  player-or-IP keys, spoof-proof client IP, fail-open/closed rules, `429` JSON with `Retry-After` and `X-RateLimit-*`,
  admin lockout (5 wrong keys → IP locked 15 min). See `docs/operations.md` «Rate limits». `start.sh` now runs uvicorn with
  `--no-proxy-headers` (the IP is worked out by the limiter).
- Admin panel: Health shows blocked requests, top blocked keys and active lockouts, with a button to clear a lockout (admin log);
  Overview shows how many players use each app version; the player page shows version, platform, OS and device model.
- Migrations 0012 (`rate_hits`) and 0013 (player client columns).
- App: handles `429` (message with countdown, a retried GET at most twice with exponential backoff + jitter, saved copy shown),
  reports its version once per start (`POST /v1/me/client`), and Settings has the new «درباره‌ی برنامه» card (tap = copy support info).
  Not released yet (the avatars task ships the APK).

## server 1.18.0 + admin app 1.0

- New small **admin app** (`admin_app/`, Flutter): a full-screen wrapper of the web panel `/admin/ui` for Amin's own phone. The admin key is typed once on the phone and kept in the Android Keystore (never in the APK or repo); the app opens `/admin/ui#k=<key>` and the page signs in from the URL fragment, then removes it from the address bar. Device-lock gate and screenshot block are switchable in the app. APK: workflow `release-admin.yml`, branch `release-admin`, GitHub release `admin-latest`. See `docs/operations.md`.
- Panel «سلامت» (Health) screen rebuilt: server (version, uptime, workers, DB latency and size), TLS days left for gaamly.ir and thecase.liara.run, content ahead / next weekend case / story chapters / validation, players today, app versions, security flags, Liara balance card. New admin endpoints `GET /admin/api/health2` and `GET /admin/api/liara` (token `LIARA_API_TOKEN` read on the server only; 5 min cache, one real call per 30 s). Panel also refreshes on pull-down on touch screens. No migrations.

## app 1.20.3 / server 1.17.2: dead address removed

- Removed the dead thecase.liara.run address; the only server address is https://gaamly.ir. Players on old APKs that only know the old address stay offline until they update. The uptime watch, release smoke test, docs and tests now use gaamly.ir only; the one-off probe workflow is deleted.

## content: story season 1 chapter 1

- Story mode season 1 «کبریت سوخته» has its bible (`server/app/content/story/s01/bible.md`) and chapter 1 «هفت‌ستاره» (`s01/ch01.json`). From 2026-10-12 00:00 Tehran `/v1/config` shows `upcoming.story.open = true`. Chapters 2–3 follow on the next nightly runs.

## app 1.20.2: new domain gaamly.ir

- The app now tries `https://gaamly.ir` first and falls back to `https://thecase.liara.run`. The uptime watch and release check use the same two addresses. The package name `ir.gammly.parvandeh` is unchanged. Players on older builds only reach the server through thecase.liara.run, so they need this update if that address stays down.

## server 1.17.1: admin disabled without a real key

- The admin API and panel now refuse every request while `ADMIN_API_KEY` is still the built-in dev value, whatever `ENV` is (that value is public in the repo). Set a long random `ADMIN_API_KEY` on Liara to use them.

## server 1.17.0: admin panel

- Admin panel at `/admin/ui` (asks for the admin key; nothing is stored on the page): overview charts, live activity feed, player search and full player timelines (cases, coins, purchases, missions, same-device accounts), per-case difficulty stats, money, health, gift / broadcast / ban buttons. JSON under `/admin/api/*`, all behind `X-Admin-Key`. New table `admin_log` records gifts, broadcasts and bans.

## Package name: ir.gammly.parvandeh

- The store package name changes from the placeholder `ir.aminsalem.the_case` to `ir.gammly.parvandeh` (reverse of the gammly.ir domain + the game), set in `app/tools/patch_android.py`. Server defaults for Myket/Bazaar package names and store links follow. It must never change again after publishing. This build is a NEW app for Android: older test installs do not update to it.

## 1.20.1 (app build 37, server 1.16.2): missions and arrows

- The mission «۲ پرونده حل کن» is no longer picked: a free player gets one new case a day (archive cases cost coins), so it could not be finished by everyone. Every daily mission can now be completed for free.
- Chevron arrows (›) in lists and buttons were showing as `>` in the right-to-left layout; they now point `<` for «go in» and `>` for «previous» everywhere.

## 1.20.0 (app build 36): intro and full guide

- New `GuideScreen`: an 8-page intro (welcome, nightly case, investigating, accusing and stars, weekend case, story, coins/rank/prizes, reminders) shown once to new players before the home screen (players who already solved a case never see it), followed by the existing in-case coach marks.
- Settings → «راهنمای کامل بازی» opens the same guide any time.

## server 1.16.1: weekend case w002

- New weekend case w002 «فانوسِ نارنجستان» (Thursday 2026-10-15): opens 09:00 (`open_hour` 9), chapters Thursday/Friday/Saturday 09:00 (`at_hours` 0/24/48), closes Sunday 21:00 (`closes_hours` 84); with its notification teaser.

## 1.19.0 (app build 35, server 1.16.0): story mode

- The «داستان» tab is now the real story mode (it opens by itself once the opening time has passed AND chapters exist; until then the banner and countdown stay). A career map shows the season's chapters as a path: finished ones with stars, the open one, and locked ones with a countdown, «با یک حکم باز کن» or «رد شدن با سکه». A warrant chip («N حکم») shows what the player holds.
- Each chapter is a full case played on the normal case screen. Before it, سرگرد ناصری introduces it in a speech card with his portrait; after the accusation he reacts (win or lose) and leaves the chapter's season thread. His own wording of the hints is supported (`partner_hints`).
- Rules (server, `/v1/story`): chapters 1–3 are free and open one after another; from chapter 4 the next one opens when the previous is finished AND the player spends 1 warrant, or 12 hours have passed, or coins skip the wait (120 coins at the start of the wait, falling to 10 as it runs out). Wrong order is refused. The story tab asks the phone to announce when the wait ends.
- Warrants «حکم بازرسی»: +1 for solving tonight's case, +1 when all the day's missions are done (once a day), +1 at streaks of 3, 7, 14 and 30 nights, +1 for the weekend case. They appear in the profile and in `gains` (a banner and a «+۱ حکم بازرسی» note on the result screen).
- New: table `story_progress`, column `players.warrants` (migration 0010, no data changes). Chapter files live in `server/app/content/story/sNN/chNN.json` (see docs/story-seasons.md); no folder or no files means «به‌زودی». No chapters are written yet.

## 1.18.0 (app build 34, server 1.15.10): notifications written for each case

- Every night's notification now carries that case's own teaser (all 50 cases have a hand-written, spoiler-free title and line in `server/app/content/notify.json`, all different), the evening streak reminder names tonight's case, the weekend case announces itself on Thursday 09:00 and again when chapters 2 and 3 open, and the story announces its opening. The server sends the plan in `/v1/config` (`notify`); if a teaser is missing it builds a text from the case's title and place. `Reminders.storyReady` is ready for the story chapter wait (the story build wires it).
- The case-writing rules now require a teaser entry for every new or rewritten case.

## server 1.15.9: weekend mission can always be finished

- The mission «توی پرونده‌ی آخر هفته با ۲ مظنون صحبت کن» only counted suspects a player had never opened before, so someone who had already talked to the suspects (or solved the case) on an earlier day could not finish it, which also blocked that day's chest. Now each suspect counts once per day, even if met before. Lifetime counters (achievements) are unchanged. The mission text lost the confusing «تو».

## 1.17.8 (app build 33): suspect marks are kept

- Fix: tapping «مشکوک» / «بی‌گناه» on a suspect was only kept if the sheet was closed with «بستن». Swiping the sheet down, tapping outside it or pressing back lost the mark. Now the mark is saved the moment it is tapped.

## 1.17.7 (app build 32): store name in the shop texts

- The shop texts say «مایکت» or «کافه‌بازار» depending on the build's STORE setting (default stays Myket). Real Cafe Bazaar payments still need the Bazaar billing code in the app (not built yet).
- Checked all case, weekend and story files for typing slips (Arabic letters, doubled words, «تو تو», spacing): nothing to fix.

## 1.17.6 (app build 31): wording clean-up

- Fixed awkward or wrong Persian in the app: «تو تو ۱۰ نفر اولی» is now «جزو ۱۰ نفر اولی!», the archive line reads «۳ از ۱۰ پرونده رو حل کردی», and about 20 more texts were smoothed (countdown labels, the weekend tab, story how-it-works, invite rewards, error messages, the quick-riddle mention removed from the rank text).

## 1.17.5 (app build 30, server 1.15.8): weekend case moves to the mornings

- New weekend cases open **Thursday 09:00**, chapter 2 on **Friday 09:00**, chapter 3 on **Saturday 09:00**; accusing is possible from chapter 3 until **Sunday 21:00**. They no longer collide with the 21:00 nightly case. A weekend case file may set `open_hour` and `closes_hours`; without them (like w001) the old timing (21:00, closes Sunday 00:00) is kept.
- The weekend tab texts and the "next opening" fallback countdown follow the new schedule.

## 1.17.4 (app build 29): real music

- New recorded sounds, converted to real Ogg Vorbis (the files were MP3 data with an .ogg name, which some phones refuse), loudness-matched, and the 60 s loops cross-faded so they repeat without a click: `amb_home` (home and other tabs), `music_weekend` (آخر هفته tab), `music_story` (داستان tab), `music_result` (a short ending after a solved case).
- Each main tab fades into its own music. Total size about 2.3 MB.

## server 1.15.7: nightly cases c020–c024 rewritten harder

- Five nights (18–22 October) get new, harder stories under the case-writing rules: «ساعتِ ایستاده‌ی برج» (two people, one plan), «صندوق آهنی سرای گلشن» (motive inversion), «پالتوی شتری» (one coat through five hands), «کوپه‌ی شماره‌ی هفت» (a timetable alibi) and «عطردانِ شاه‌نشین» (a hidden marriage). Same ids, numbers, dates and scenes; new portraits; all blind-tested; case log updated.

## 1.17.3 (app build 28, server 1.15.6): weekly ranking prizes

- When a week (Saturday to Friday) ends, the top 10 on the weekly leaderboard get coins in their inbox with a message: 1st 300, 2nd 200, 3rd 150, 4th to 10th 75. Paid once per week, automatically (hourly check + when the inbox opens). The week that ended on Fri 9 Oct is paid right after this deploy.
- The phone shows a notification when a prize arrives, and a weekly Saturday 10:00 reminder to look at the result.

## server 1.15.5: weekend case w001 rewritten harder

- «شب برفی ویلای صدری»: chapters 2 and 3 rewritten so the answer can't be guessed, only proven by combining cards from all three chapters. Chapter 1 (intro, suspects, first cards) is unchanged; a few suspects got extra answers. Blind-tested; case log updated.

## 1.17.2 (app build 27, server 1.15.4): no accusing before the last chapter

- Weekend case: the server refuses an accusation until the last chapter is out (the proof cards are in it), so no try is wasted; the app shows «متهم کردن از فصل آخر» instead of the button until then.
- Everyone who accused «شب برفی ویلای صدری» (w001) on the first night gets their tries back (database migration 0009); nobody could have solved it yet.

## 1.17.1 (app build 26): two server addresses, server watch

- The app knows both server addresses, https://gammly.ir and https://thecase.liara.run, and uses whichever answers (it remembers the last one that worked). A request that could not connect is tried on the other address; one that timed out is not sent twice.
- New GitHub workflow «Server watch»: every 30 minutes it checks /health on both addresses and fails (GitHub notifies the owner) when neither answers. Optional Liara wallet check with the LIARA_API_TOKEN secret and LIARA_MIN_BALANCE variable.
- Release notes also show gammly.ir health.

## 1.17.0 (app build 25): redesigned home, archive, accuse, result, shop and leaderboard

- Home: a top bar with portrait, name and rank (tap: profile), a red 🔥 streak chip (tap: the streak card with insurance in a small sheet), coins (tap: shop) and the inbox. One big card for tonight's case (scene, crime tape, «پرونده‌ی امشب · شماره‌ی N», title, place · how many solved it, «شروع تحقیقات» or how it went) with «پرونده‌ی بعدی: hh:mm:ss» inside it. Under it only one-line rows: «مأموریت‌های امروز» with three progress pills, «آخر هفته: …» with the time left or «به‌زودی», «بایگانی پرونده‌ها» (N پرونده · M تا حل کردی), and for guests «حسابت رو امن کن». The separate next-case card, the big streak card, the weekend card and the inline archive list are gone from home.
- New archive page: «بایگانی» with «X از Y حل شده», filters همه / حل‌نشده / رایگان / ۳ ستاره, a two-column grid (locked cases dimmed with a lock and the coin price), pull to refresh. Tapping opens or unlocks a case exactly as before.
- Accusing is now a stepper with «مرحله‌ی N از M» and a bar: the suspect, then the proof card, then (weekend case) the motive, with «ادامه» / «قبلی». Above the final button an amber card «اتهام تو: … · با …». A wrong try goes back to the step that was wrong. Same API call and messages.
- Result: the big stamp and stars, one small row of rewards (coins, nights in a row, rank; tap the rank for the leaderboard), a slim new-badge banner, the culprit with the explanation folded to three lines («ادامه‌ی توضیح ▾»), «بقیه چی فکر می‌کردن؟», then a red «پز بده» (a short text with the case number, the stars and the app link) and «برگشت به خانه».
- Shop: the 30-day VIP on top as a brass «پیشنهاد ویژه» card with a red «بخر»; three equal coin packs (محبوب / بهترین ارزش), the starter pack, then «با سکه» (streak insurance). No green buttons anywhere (green only means correct).
- Leaderboard: a podium for the top three (2 – 1 – 3, a crown on the first, brass / silver / bronze rings), the list from 4, and your own row pinned at the bottom: «تو · N رتبه تا ۱۰ نفر اول» or «تو تو ۱۰ نفر اولی!».
- Case: the evidence tab shows «X از Y مدرک دیده شده» (cards you tapped or pinned, kept with your notes).
- First case ever: three short coach marks over the case (مدارک رو بخون → از مظنون‌ها سؤال کن → با مدرک متهم کن), skippable with «رد کن», shown once. Players who already solved cases don't see it.

## 1.16.0 (app build 24): profile and settings

- The profile is now just the detective: a header card (portrait with a pencil to change it, name with a pencil to rename, rank, XP and how many points to the next rank; tap it for the rank ladder), three numbers (پرونده‌ی حل‌شده، زنجیره، بهترین زنجیره), the four latest badges with «همه» for every achievement, and the invite card with «بفرست» and «کد دوستت رو داری؟». Guests see one amber line «حسابت هنوز امن نیست…» with «امنش کن». The streak badges moved out (they are achievements already).
- New Settings page behind the ⚙ at the top of the profile: حساب (امن کردن حساب / عوض کردن رمز, ورود یا انتقال از گوشی دیگر), ظاهر (فونت و اندازه‌ی متن), صدا و اعلان (صدا و موسیقی, یادآوری پرونده‌ی هر شب), پشتیبانی و قوانین (تماس با ما when the server config has `support_url` or `support_email`, حریم خصوصی, قوانین), then «حذف حساب» and the app version.
- Every account form opens in a bottom sheet. Signing in from another phone is one sheet with two tabs, «با ایمیل» and «با کد انتقال», and a warning that this phone's progress is replaced. Same API calls as before.

## server 1.15.3: harder cases 13–16

- c013 «جام برف‌چال» (staged scene), c014 «اسطرلاب ریگ‌سفید» (hidden relationship), c015 «خروجیِ بسته» (guilty knowledge) and c016 «آزمایشگاه ۲۰۴» (not what it seemed) rewritten under the case-writing rules: difficulty 4, new plots, painted portraits, blind-tested. Case log updated.

## server 1.15.2: daily missions without riddles

- Every day: «پرونده‌ی امشب رو حل کن», one skill mission (۳ ستاره / بدون سرنخ / بدون اتهام اشتباه) and one investigation mission (بازجویی از همه / حرف زدن با ۳ مظنون / حل ۲ پرونده). Friday and Saturday, while the weekend case is open, the third one is «تو پرونده‌ی آخر هفته از ۲ مظنون بازجویی کن».
- No mission makes you spend coins any more (buying a hint / unlocking an archive case are out). Riddle achievements are hidden while riddles are off.

## 1.15.1 (app build 23, server 1.15.1): quieter home, weekend countdown fix

- Quick riddles are hidden for now: no «روزانه» tab and no riddle card on home; daily missions no longer ask for riddles (the missions list opens from the home row).
- Weekend countdown: when the server does not send the next opening time it now counts to the next Thursday 21:00 (it wrongly showed tonight's 21:00). The rules card says the case stays open until the end of Saturday.
- Story countdown falls back to Mon 12 Oct 00:00.

## 1.15.0 (app build 22, server 1.15.0): weekend and story tabs

- Two new main tabs: «آخر هفته» (this weekend's big case, or a banner with a countdown to the next one, opening Thursday 21:00) and «داستان» (season 1 «کبریت سوخته» with سرگرد ناصری, counting down to Monday 12 Oct 00:00).
- The shop moved to the coin chip; the bottom bar is now خانه، روزانه، آخر هفته، داستان، برترها، پروفایل.
- Server: /v1/config has `upcoming.weekend` and `upcoming.story` (title, time, open).

## 1.14.1 (app build 21, server 1.14.1): permanent signing key

- The APK is now signed with the permanent release key (the same one Myket will use). This is the last version that needs an uninstall; every later version installs over it and keeps the player's data.

## 1.14.0 (app build 20, server 1.14.0): font and text size

- Profile → «فونت و اندازه‌ی متن»: choose the font (وزیرمتن، ساحل، شبنم، استعداد) and the text size (کوچک، معمولی، بزرگ، خیلی بزرگ), with a live sample. The choice is saved on the phone and applies to every screen right away.

## server 1.13.3: harder cases 11 and 12

- c011 «مرواریدهای اتاق ۲۱۴» and c012 «سیصد پرس» rewritten under the case-writing rules (difficulty 4, blind-tested). Case log updated.

## server 1.13.2: harder case 10, weekend case reviewed

- c010 rewritten under the case-writing rules (difficulty 4, «پرده‌ی دوم», blind-tested).
- w001 reviewed before it opens: surface-only motives, side secrets with explaining clues for every innocent suspect, spoken Persian answers, a second left-hand ring so chapter 3 is needed (two new clues: e17–e19). Plot, chapters and solution unchanged.

## server 1.13.1: harder case 9

- c009 rewritten under the case-writing rules (difficulty 4, new plot «لنگرگاه چهار قلاچ», blind-tested).

## 1.13.0 (app build 19, server 1.13.0): crime-scene tape

- Opening a case: two yellow police tapes («صحنه‌ی جرم • وارد نشوید») snap across the screen and are pulled away.
- A strip of tape stays across the case intro and along the bottom of the case header.
- Evidence cards carry numbered yellow evidence markers, like the tents at a real scene.

## 1.12.0 (app build 18, server 1.12.0): "Evidence room" colors

- New palette: neutral charcoal backgrounds (no pure black), warm off-white text, police-tape amber accents, a softer red for stamps and buttons, calmer green. Easier on the eyes at night; portraits and scenes stand out more.

## 1.11.1 (app build 17, server 1.11.1): 8 more portraits

- Exact faces for roles that borrowed one: boat captains (c027, c049), train conductors (c023, c043), the male night
  nurse (c028), receptionists (c019, c031, c039, c044, c048), archaeologists (c014, c034), IT specialists (c002,
  c022, c042) and wedding DJs (c017, c037). 48 portraits in all.

## 1.11.0 (app build 16, server 1.11.0): painted art

- 20 painted scene backgrounds replace the drawn ones, with a slow camera drift and rain, snow or floating dust.
- 40 painted suspect portraits; every one of the 257 suspects in the 50 cases and the weekend case now has one,
  matched by gender, age and job (no repeats inside a case; the twins in c021 share a face).
- 10 painted detective avatars for players (home, profile, leaderboards).
- All art is WebP: about 1.6 MB in total.

## 1.10.0 (app build 15, server 1.10.0): weekend case and fair time

- «پرونده‌ی آخر هفته»: a much harder case every Thursday 21:00 until Saturday night, free for everyone.
  Eight suspects, 16 clues in three chapters (Thursday night, Friday 10:00, Friday 21:00), a twist in the last
  chapter, and the player must also pick the motive. Reward 300/200/120 coins and 150/100/60 XP. First case:
  «شب برفی ویلای صدری» (8 Oct). It does not affect the nightly streak.
- Fair solving time: only the time the case screen is open counts. It pauses when the player leaves the case,
  switches app or locks the phone; the server caps every report so the time can't be faked upward. Old app
  versions keep the old clock.

## 1.9.1 (app build 14, server 1.9.1): first painted portraits

- Suspects can have a painted portrait (assets/portraits, WebP ~25 KB each) shown with slow breathing motion;
  nervous suspects sway, the caught culprit darkens. Others are still drawn in code.
- First 4 portraits: c007 (customs inspector, crane operator) and c008 (cleaner, night nurse; the nurse is now
  «فرشته عزیزی»).

## 1.9.0 (app build 13, server 1.9.0): bottom tabs and harder cases

- Bottom navigation with five tabs: خانه, روزانه (quick riddles + missions), برترها, فروشگاه, پروفایل. The home page
  now shows only tonight's case, the next-case timer, short riddle/mission summaries, the streak and the archive.
- The reminder sentence in the profile now says clearly what happens at 21:00 and 22:30.
- Cases c008-c012 (6-10 Oct) rewritten to be harder: no card that gives the answer away on its own, a red herring in
  each, and the proof only makes sense when two cards are read together.

## 1.8.0 (app build 12, server 1.8.0): achievements

- 33 achievements in 7 groups (cases, skill, streaks, quick riddles, missions, account, rank), each with coins
  and XP: first 3-star case, cases without hints, solved under 5 and 2 minutes, solved in the first half hour,
  3/7/30/100-night streaks, 10/50 riddles, error-free riddle days, 7 days of missions in a row, and more.
- Computed on the server from lifetime counters; ones already deserved (streaks, secured account, invites) are
  granted on the next visit. A banner shows each one as it is earned.
- Achievements screen with progress bars, reachable from the home page and the profile.

## 1.7.0 (app build 11, server 1.7.0): detective rank

- XP for everything: solved cases (25/40/60 by stars, +15 on its own day, 5 for a lost case), quick riddles
  (10 right, 2 wrong) and the mission chest (40). Nine ranks from «کارآگاه تازه‌کار» to «افسانه» (15,000 XP).
- Rank bar on the home page, the full ladder in the profile, rank titles next to names on every leaderboard,
  and a banner on rank-up. Existing players start with XP for the stars they already have.

## 1.6.0 (app build 10, server 1.6.0): daily missions

- Three daily missions for everyone (one about quick riddles, one about cases, one extra), picked from a pool of
  12. Progress comes from real actions on the server: answering riddles, solving cases (with 3 stars, without
  hints), interrogating every suspect, buying a hint, opening archive cases or locked riddles.
- When all three are done, a chest gives 80 coins; every 7th day in a row adds 150 more.
- A banner slides in on any screen when a mission is finished.

## 1.5.0 (app build 9, server 1.5.0): quick riddles

- «معمای سریع»: five one-minute mini mysteries every day, the same set for everyone (60 original riddles,
  shuffled per 12-day cycle). The first three are free, the others open for 20 coins; a right answer pays 10.
  Answers are checked on the server and the explanation is shown after answering.
- A card on the home page shows today's riddles at a glance.

## 1.4.0 (app build 8, server 1.4.0): ready for Myket

- Real payments through Myket; every purchase is checked by the server with Myket before coins are added, and a
  purchase paid while offline is credited later. Prices come from Myket (fallback labels in remote config).
- VIP is a 30-day pass. Ad-removal and rewarded ads are hidden until a real ad network is added.
- Privacy policy, terms and account deletion (in the app and at /privacy, /terms, /delete-account).
- Release builds can be signed with a permanent key (GitHub secrets) and carry the Myket RSA key.

## 1.3.0 (app build 7, server 1.3.0): fairness and sound

- Suspects and evidence are shuffled per case (same order for everyone); the culprit is no longer usually first.
- Every card that breaks the culprit's story is accepted as proof (c001, c047, c049 fixed). The right suspect with
  the wrong proof now costs a star instead of a try (twice).
- Contradictions fixed in c006, c020, c027, c040, c049 and c050.
- All women are drawn with hijab; real religious and state places renamed to fictional or generic ones.
- Sound: even loudness on phone speakers, no hiss or sub-bass drone, no clicks; new gentle wrong/lose/heartbeat
  sounds; buttons make a soft tap; the verdict lowers the background; plays alongside your music.

## 1.2.2 (app build 6)

- **Plays without internet**: the app always opens. Opened cases, the case list, profile and notes are kept on the
  phone; a calm banner shows when offline and it reconnects by itself. Things that need the server (accusing, hints,
  shop, leaderboard, account) say so instead of failing.
- **Only friendly messages**: no technical error text in the app any more.
- **Buttons no longer hide under the phone's navigation bar** (the «متهم کن» bar, sheets, dialogs); the case intro
  scrolls on small phones and with big system fonts.
- Suspect marks and pinned evidence are saved per case.
- CI renders 39 real screens to the `screens-out` branch for design review.

## 1.2.1 (app build 5, server 1.2.0)

**App icon**
- New icon: a fingerprint on paper, with a magnifier that shows the night sky and a clock at 9. Adaptive icon for
  Android 8+ (fits round and rounded-square masks), a themed (monochrome) version for Android 13, a white
  notification icon for the reminders, the logo on the start screen, and a 512×512 store icon.

## 1.2.0 (app build 3, server 1.2.0)

**Coming back every night**
- **Share card** after a case: tries, stars, time, hints and streak as emoji, with the app link. It never shows the
  culprit or the evidence.
- **What others thought**: after finishing a case, bars show who players accused first, plus solved % and first-try %.
- **Streak insurance**: 150 coins, hold up to 2. If a nightly case is missed, one is spent and the streak survives.
- **Streak badges** at 7, 30 and 100 nights in a row (account screen, and a banner when one is earned).
- **7-day login calendar**: 20, 30, 40, 50, 60, 80 coins, and a sealed envelope (100–250) on day 7. Missing a day starts
  again from day 1.
- **Reminders** on the phone (no Firebase): 21:00 "tonight's case is open", 22:30 "your streak is in danger" when the
  case isn't solved yet. A switch in the account screen turns them off.

**Server**
- New: `POST /v1/wallet/streak-freeze`, `GET /v1/cases/{id}/stats` (only after finishing). Migration 0002 adds three
  columns. Config has `share_url` and the new numbers.
- `app/tools/patch_android.py` prepares the manifest and Gradle for the reminders; `build_release.sh` runs it.

## 1.1.0 (app build 2, server 1.1.0)

**Cases**
- 44 new cases: **50 in total**, one every night until 17 Nov 2026. 34 are difficulty 4, five are difficulty 5.
- New cases have five suspects, 8–9 pieces of evidence, decoys and a real chain of reasoning (logs, clocks, time zones,
  forged stamps, calendars, arithmetic, logic puzzles).
- The server now refuses a case file with an unknown scene, difficulty outside 1–5, fewer than 5 pieces of evidence or
  fewer than 2 questions per suspect.

**Look and animation**
- 14 new animated scenes (harbor, hospital, library, theater, hotel, kitchen, snow lodge, desert, subway, lab, wedding,
  school, airport, clock tower); fog, floating dust and film flicker on every scene.
- New screen transitions, count-up coins and rewards, confetti on a solved case, pins on evidence, a pulsing "new" tag,
  a collection progress bar, torchlight on the start screen, difficulty shown out of 5.

**Sound**
- A mystery sound bed for every theme, a sting when a case opens, interface sounds, a mute button. All synthesised.

**Checks**
- `server/tools/smoke_test.py` checks that a running server answers every call the app makes.
- Server tests play all 50 cases through the API; app tests check every case parses, every scene paints and every
  sound exists.
- `/health` now also reports the server version.

## 1.0.1
- Server version bump to trigger a Liara deploy.

## 1.0.0
- First release: daily cases, interrogation, accusation with proof, coins, archive, leaderboards, shop, inbox.
