# Changelog

## server 1.37.1, app 1.37.1 (build 70): fingerprint reader rebuilt (Amin, 23 Oct 2026)
- The 1.37.0 fingerprint ("your name appears in N cards") told players nothing they cannot already see under every card, so it is replaced: it now shows an authored physical trace per suspect, `suspect.print` (string or 1-3 lines, 20-160 chars, validated like `camera`, never in the public case). A case without `print` does not offer the tool; "nothing new" costs nothing. `mention_count` is gone. Traces were written for all cases (branch `content/prints`, rules in `docs/case-writing-rules.md` §10).
## server 1.37.0, app 1.37.0 (build 69): detective tools v2 (Amin, 23 Oct 2026, urgent)
- **Fingerprint no longer misleads.** It used to say «توی مدارک اصلی نقش داره» for any suspect named in a proof card, so an innocent could get "yes" and a player paid coins for a wrong lead. Now it only says in how many cards the suspect's name appears and that this is neither guilt nor innocence (`tools.mention_count`); a suspect named in no card gives "nothing new" and costs nothing. `touched_ids`/`fingerprint_safe` are gone.
- **Magnifier works on every case** (also the 35 real cases without `solution.irrelevant`): it falls back to a card that is not a proof card (preferring one the explanation does not cite) with honest wording «جزو مدارک اصلی نیست؛ مکمله». An authored `irrelevant` list still wins and keeps its «بی‌ربط» wording.
- **Weekend cases get tools** (story chapters still do not): once per kind PER NIGHT (`case_tool_uses.kind` = `fingerprint`, then `fingerprint@2`; no migration), answers only about cards and suspects already visible, earlier nights' results stay pinned (`earlier`). Tray payload adds `night`, `how` (where each tool comes from / where it is used) and `earlier`.
- **App:** bolder tray (big icon buttons, title row, «چطور کار می‌کنن؟» help sheet), a confirm sheet before EVERY use or buy (what it shows, what it never does, price, balance, once per case/night, nothing-new is free), pinned results of earlier nights. Camera still needs authored `suspect.camera` lines; they are being written per case (branch `content/camera-lines`).
- Tests: `server/tests/test_tools.py` (fact-not-verdict on every real suspect, magnifier on all real cases, weekend per-night and visibility), `app/test/tools_test.dart`.

## server 1.36.0, app 1.36.0 (build 68): navigation + home (UI batch 1), rating limit, leaked-answer defence (Amin, 22 Oct 2026)
- **Item U, bottom navigation:** five tabs خانه، بایگانی، آخر هفته، برترها، پروفایل on those five screens only (never inside a case or a sheet). The archive is now a TAB (it keeps its filters and search when you switch away and reloads when the tab opens); the story is no longer a tab and opens from «تازه‌ها» on the home screen (`MainShell.openStory`), the weekend tab shows a dot while a weekend case is open and unsolved, Android back from a tab goes to خانه and then leaves. «برو به … بایگانی» jumps in «چی تازه شده؟» now switch to the archive tab. Labels are capped at font scale 1.2 so five labels fit 360 dp.
- **Item U, home:** header (avatar + bell with unread, greeting, rank title, coin chip) → hero for tonight (free pill, number, category, title, location, solvers, the 5-level difficulty bar + label, one primary button) → two quick cards side by side («بایگانی پرونده‌ها» with the REAL number of unsolved old cases, «پرونده‌ی آخر هفته» with its real state: open / «فصل دوم» countdown / solved / lost / closed with the real opening time) → compact missions card → streak row (nights, nights to the next step, the repair offer with a close button) → secure-account row → collapsed «تازه‌ها» (what's new, story, invite, leaderboard, shop). After solving: a result card («پرونده‌ی امشب حل شد», plaques, «مرور نتیجه») + «یک پرونده‌ی دیگر؟» with the real count; a LOST case says it is closed and offers the second chance with the real reopen price from the server (2x), never the answer. Offline strip as before. Tests: `app/test/home_nav_test.dart` (tabs, back, state, hidden in a case, dot, counts, 360x740 fits hero + cards at 1.0 and 1.3, no overflow at 1.0/1.3/2.0), previews from `app/test/home_preview_test.dart` uploaded by CI as the artifact `home-ui-previews`.
- **Item 0, rating limit:** new `POST /v1/cases/{id}/rating` with its own policy `rating` (5/10 s, 200/h per player, relaxed, fail open); `…/comments` keeps the strict `comment` policy for text and replies and still accepts rating-only bodies. The app uses the new route for stars (inline card, rating sheet, archive nudge) and falls back to the old call on 404. The wait text shows seconds / minutes («حدود ۵ دقیقه») / hours. Tests: `server/tests/test_rating.py`, `app/test/rate_case_test.dart`, `app/test/rate_limit_test.dart`.
- **Items 1-4, leaked answers** (details and settings in `docs/operations.md`): (1) spoiler-free share card «پرونده‌ی ۳۴ «عنوان» 🕵️ ۳ پلاک · ۴ مدرک · ۶ دقیقه — تو هم امتحان کن: لینک» (link constant `kShareLinkPlaceholder`, TODO Amin); (2) investigation depth recorded per player per case (cards tapped, questions asked, proof cards, active seconds; migration 0030) and a **ranked** gate with kill switch `DEPTH_GATE_ENABLED`, defaults: 2 questions, cards recorded but not required (a card can be read without a tap); an unranked solve keeps stars and coins and the result screen says why; (3) daily draw: one warrant for one ranked 3-plaque solver per night (table `daily_draws`, deterministic, idempotent, kill switch `DAILY_DRAW_ENABLED`), weekly board now ranks nights solved, then nights on time, then plaques, speed last (`WEEK_RANK_MODE`); (4) admin report `/admin/suspicious-solves`. Tests: `server/tests/test_leak_defence.py`, `app/test/engagement_test.dart`.

## server 1.35.0, app 1.35.0 (build 67): leaderboard calm and honest, weekend chapters, public pages, landing site (Amin, 21 Oct 2026)
- **Leaderboard «برترها», bug a:** the league chips were built inside the list, and an empty league replaced the whole list with one sentence, so the chips vanished (and they also vanished while a new league loaded). The header and the league switch are now ALWAYS built (the last board stays on screen while a new one loads, an empty league shows «هنوز هیچ کارآگاهی توی لیگ … حل نکرده», an error keeps the switch). Widget tests select every league in turn, the empty one included (`app/test/leaderboard_screen_test.dart`).
- **Bug b (reyhoon / «سربازرس»):** there are 9 profile ranks (`economy.RANKS`) and 4 leagues. A league is a RANGE of ranks, decided by the XP at the week's snapshot: تازه‌کار = تازه‌کار..دستیار کارآگاه, کارآگاه = کارآگاه..کارآگاه ارشد, **بازرس = بازرس..سربازرس**, سرپرست = کارآگاه نخبه..افسانه. So no league is named «سربازرس»; a player at 4200 XP plays in «بازرس», and a player promoted DURING the week keeps the week's league (by design, the snapshot is fixed per week) while his row shows his CURRENT rank. Other reasons a player is missing from a board (existing rules, unchanged): no solved ranked case of the week, tester or banned, account younger than 48 h without phone/email. The league table now lives in ONE place (`weekboard.LEAGUE_DEFS`, `league_info`), the API gives each league its `min_xp`, `from_rank`, `to_rank` and each weekly row its `league_name` (additive, old apps ignore them); the «i» sheet lists the ranges. Prizes and the snapshot rule are unchanged. Tests in `server/tests/test_fair_week.py` (seeded XP of سربازرس, promotion in mid-week, every rank in exactly one league).
- **Calmer screen:** one short line on the weekly tab (what it is, when the week ends) and an «i» next to the title (and next to the line) that opens a bottom sheet with the full explanation (weekly clock Friday 21:00, fair week, leagues and their ranks, prizes 120/80/50, ties); one tap closes it.
- **Weekend chapters (items 0b):** every card of a chaptered weekend case shows «فصل N»; cards and suspects of chapter 2+ carry «تازه» / «مظنون تازه · فصل N» until opened (remembered on the phone, `SharedPreferences` per case); a filter row «همه / فصل ۱ …» always shows all OPEN chapters (an empty one shows an empty state) with the count of new cards on the chip; new suspects are listed first and the suspect list says «N مظنون تازه»; a non-blocking banner «فصل ۲ باز شد: ۳ مدرک و ۱ مظنون تازه» (tap = go to that chapter, cross = close) appears when a chapter opens (the screen reloads itself when the next chapter opens). Nightly cases are unchanged. Only existing server fields are used (`chapter` on cards, `appears_chapter` on suspects, `chapters`). Tests: `app/test/weekend_chapters_test.dart`.
- **Public pages rewritten from an audit of the code** (`routers/pages.py`): `/privacy`, `/terms`, `/delete-account` (same URLs) and a new `/support`; dated «۲۹ مهر ۱۴۰۵». `POST /v1/me/delete` now removes every row of the player (coin log, invite payouts, league rows) through `purge.purge_players`, so the page is true. The in-app delete dialog names comments and the phone number. Test: `server/tests/test_pages_site.py`.
- **Landing page at «/»** (`app/site.py`, `app/web/index.html`): self-contained, own font from `/static/fonts`, no external host, ETag + 5 min cache, no database. Playable demo «نسخه‌ی گمشده» (4 مظنون, 6 مدرک, difficulty about 3) written only for the page, not a game case. The Bazaar link is the constant `site.BAZAAR_URL` (TODO: confirm the real address).
## server 1.34.1 (no app change): weekend case w003 reviewed and rewritten (21 Oct 2026)
- **w003 «حراجِ ساعت‌های خاموش»** (opens Thu 22 Oct 09:00): the culprit was named by single cards, the motive options each named a suspect, the watch was never accounted for and several lies were never explained. Rewritten clue chain (clock stopped with the generator tag, theft before the ceremony, fake call from the locked management room, sale to the partner), every innocent's side secret explained, names that clashed with this week's cases changed (Iraj Mostofi, Malihe Roshan). Blind-tested: night 1 leaning (50%), full case 95% in 8 steps with no single giveaway card; difficulty set to **4** (was 5). Details in `docs/case-log.md`.

## server 1.34.0 (no app change): economy health screen and calmer prices (Amin, 21 Oct 2026)
- **Admin tab «🪙 اقتصاد سکه»** (`/admin/api/economy`): coin flow by source and item, desire vs escape spending, balance buckets of active players, hints and tool use, what happens after a loss, first-day spenders vs the rest, plus plain-language notes. Details: `docs/operations.md` «Economy health». Read-only, no new tracking, no player data in the answer. Tests: `server/tests/test_economy_report.py`; the admin menu test now expects 10 tabs.
- **Prices (final for now):** hints **40 / 80 / 120** (was 30/50/80; the 50/90/140 of 1.33.1 was too steep for a stuck player), tools **35 / 65 / 100**. Why: the free income is about 100 coins a day for an engaged player and a solved case pays 6-45, so the third hint at 120 is about a day of income and the first at 40 is one case's reward. Revenue: sinks stay meaningful without making the lost-case moment feel like a trap. Revisit after a week of the new screen.

## server 1.33.1 (no app change): higher hint and tool prices (Amin, 21 Oct 2026)
- Hints 30/50/80 -> **50/90/140**; detective tools 25/45/70 -> **40/70/110** (`economy.HINT_COSTS`, `economy.TOOL_PRICES`). The app reads both from the server (`hint_costs`, the tool tray), so no new APK is needed. Why: a hint cost less than one solve reward (6-45 coins), so nobody needed coins; tools stay a little under the hint beside them because they narrow the search without naming a card. A new player (100 coins) can still buy the first hint; the first tool of each kind stays free. Revenue: every hint and tool now takes a larger share of the free income, which is what sends players to the coin packs (400 / 1300 / 3600).

## server 1.33.0, app 1.33.0 (build 66): detective tools «ابزارهای کارآگاهی» (Amin, 16 Oct 2026; asked as Normal, built 20 Oct)
- **Three consumables on the daily case screen** (a tray above the hint/accuse bar): «ذره‌بین» marks one card «بی‌ربط»; «اثر انگشت‌خوان» says whether a chosen مظنون is touched by the main cards («توی مدارک اصلی نقش داره» / «نقش مهمی نداره»), never guilty/innocent; «دوربین مخفی» shows one extra neutral line about a chosen مظنون. Once per case per kind, results pinned on the case, plaques never change, and a tool never counts as investigation (a solve with tools alone stays unranked). Weekend and story cases: tools off, the tray says so.
- **Prices** (`economy.TOOL_PRICES`): 25 / 45 / 70 coins (hints are 30 / 50 / 80). The first of each kind is free once per player (tutorial). Only other free source: a rare drop at existing reward points (7th chest day in a row; achievements streak_30, cases_50, interrogate_10).
- **Server:** `GET /v1/cases/{id}/tools`, `POST .../tools/{kind}/use|buy`; tables `player_tools` and `case_tool_uses` (UNIQUE per player, case, kind), guarded SQL, one transaction under the player lock, rate limits `tool_buy` (strict) / `tool_use`, kill switch `DETECTIVE_TOOLS_ENABLED=false`, one log line per use (`tool_used ... source=coins` = revenue). Migration 0029 (additive, listed in ci.yml). Tests: `server/tests/test_tools.py` (real case files, double tap, once per case, tutorial, kill switch, abuse, drops), `app/test/tools_test.dart`.
- **Data the tools need, and what the code could not give:** the case files had no "card not needed" mark (new cases cite every card) and every suspect answer is already visible, so the magnifier and the camera read two NEW optional fields (`solution.irrelevant`, `suspect.camera`; rules in `docs/case-writing-rules.md` §10, validated by `content.py`, camera lines never sent to the phone). No existing case has them yet, so at launch only the fingerprint is on offer (29 of 50 cases; the server refuses it where the answer would single out the culprit). The tray shows only what a case supports; nothing is charged when a tool has nothing new.
- Old apps keep working (new routes and optional fields only).

## server 1.32.0, app 1.32.0 (build 65): the streak has a long-term goal (Amin, 16 Oct 2026; asked as Normal, built 20 Oct)
- **Ladder:** 3, 7, 14, 30, 60, 100, 200, 365 nights (`economy.STREAK_MILESTONES`). Existing rewards are unchanged (no new free coins or warrants). 60, 200 and 365 give permanent frames only: «شعله» (`frame_blaze`), «آتشفشان» (`frame_inferno`), «شعله‌ی جاودان» (`frame_eternal`), all drawn in code with flames (`avatar_frame.dart`), plus achievements `streak_60/200/365` with XP and 0 coins. The streak card says «۱۲ شب مونده تا «قاب «شعله»»» and keeps «بهترین زنجیره».
- **Flame:** a small flame with the live streak next to the nickname on all leaderboards and on the profile (`LeaderRow.streak`, 0 for a broken streak, bounded, no extra query).
- **Streak repair:** a streak that broke last night (exactly one missed daily case, no insurance, at least 3 nights) can be mended once per break: `POST /v1/wallet/streak-repair`, price `min(500, 200 + 5 x nights)` (215 at 3, 350 at 30, 500 from 60), atomic and idempotent (player lock + unique row), strict `wallet` rate limit, kill switch `STREAK_REPAIR_ENABLED=false`, one log line per decision. The app shows it once (a sheet on the home screen that closes with one tap, and a button on the streak card); it never blocks tonight's case. Revenue: a coin sink above the insurance price that makes players with a long streak top up coins at the moment they care most.
- Old apps keep working: new fields are optional (`streak_repair`, `streak`, `streak_milestone`); `badge` and `streak_badges` stay 7/30/100. Migration 0028 (additive). Docs: `docs/operations.md`.

## server 1.31.2, app 1.31.2 (build 64): ChatGPT batch merged (Amin, 20 Oct 2026)
- Merged: read-only analytics access, private content-dir prep, result prompts after the explanation, personal claim notes, Android screen-capture protection. Details are in the entries below.

## server 1.31.1, app 1.31.1 (build 63): lost cases stay closed, second chance costs 2x (Amin, 20 Oct 2026)
- A case the player LOST (3 wrong accusations, not solved) no longer opens: `GET /v1/cases/{id}`, its stats and the answer return 402 `locked` with `lost: true` and the reopen price, also after the next case opens or the weekend closes. Story chapters are not affected.
- Reopening costs **2x the archive price of the case difficulty** (200/240/300/360/440; weekend 340-740), `economy.reopen_lost_cost`, kill-free constant `LOST_REOPEN_FACTOR`. VIP pays too. One transaction under the player lock (`reopen:<case>` in the coin log, a double tap charges once), `expected_cost` mismatch gives 409 `price_changed`.
- The reopen gives 3 fresh tries; hints and notes stay; that run is unranked on the daily board. Revenue: a lost case becomes a coin sink instead of a free answer.
- App: the lost row shows the doubled price with «فرصت دوباره» and a dialog that explains it.

## Unreleased — atomic wallet
- Apply wallet deltas with guarded atomic SQL; ledger and related reward/purchase state share one transaction.
- Serialize account mutations and one-time grants across workers; lock referral and weekly-prize state consistently.
- Verify concurrent spending, rewards, claims and rollback with an isolated PostgreSQL CI service.

## app 1.31.0 (build 62): archive fixes + chapter 2 art (Amin, 19 Oct 2026; one slot, one build, app only)

- **Archive card alignment:** the rating and the comments now live in a fixed-size block (`ArchiveStatsSlot`) on the left edge of every card: fixed slot widths, tabular digits, muted placeholders («بدون امتیاز», a grey bubble with ۰) so nothing jumps; comments show even when nobody rated; state text scales down instead of overflowing (tested at 360 dp, font x1/1.5/2).
- **«محبوب‌ترین» was wrong** (it sorted by the number of solvers, so a case solved by many but rated low came first and unrated cases sat in the middle). Now: rated cases first by Bayesian rating (prior 3.5, weight 10 votes, so one 5-star vote does not beat 4.8 from 200), ties by votes, unrated last (newest number first). The old «بهترین امتیاز» duplicated it and is gone. Sorting is done in the app (`app/lib/services/archive_logic.dart`); the server only sends the raw numbers, so no server change.
- **Other sorts and filters reviewed:** newest/oldest tie-break by case number (stable); new «پرنظرترین», «آسان‌ترین», «سخت‌ترین»; filters now «حل‌نشده», «حل‌شده», «۳ پلاک», «بدون قفل» (was the confusing «باز»), «قفل‌دار», «آخر هفته», «امتیاز ندادم»; a search box (title, place, case number; Persian/Arabic digits, ZWNJ, ي/ك handled); chip counts on status and topic chips; chips that would show nothing hide; combined filters + topic + search; a topic that disappears is reset; the empty state has «پاک کردن فیلترها». Unit tests: `archive_logic_test.dart`, `archive_stats_test.dart`.
- **Story chapter 2 art (story stays closed, `opens_at` unchanged):** the five pictures Amin supplied are cropped to webp assets (`app/assets/story/s01ch02/`, about 30 KB each) and shown above the scenes of `s01ch02` (reception, room 311, corridor) plus a before/after toggle (intact / burnt) on the Taban photo clue. Matching is by chapter and scene id in `app/lib/data/story_art.dart`; chapters without art, and the chapter 2 JSON, are unchanged. The ch02 content itself stays on branch `story-inbox`.
- No server change: no push to `main`, no Liara deployment. Build with `git push -f origin slot-0619-archive-story:release`.

## Unreleased: delegated aggregate analytics

- Added an opt-in, expiring report-only credential for `GET /v1/analytics/funnel`. It cannot authorize admin/player endpoints or writes. Server stores only a SHA-256 digest; nested aggregate fields are whitelisted, responses are not HTTP-cached, and reads have a shared fail-closed rate limit. No migration or APK. Activation, expiry, revocation and safe JSON export are documented in `docs/operations.md`.

## server 1.31.0, app 1.30.0 (build 61): Bazaar purchase fix, case categories, weekend format 3 (Amin, 18 Oct 2026)

- **Cafe Bazaar rejection (version code 55) fixed.** The vendored `flutter_poolakey` plugin never answered the `connect` call, so the app's `await connect(...)` hung for ever and the shop always said «برای خرید، اپ کافه‌بازار باید روی گوشی نصب و به‌روز باشه». Now: the plugin answers; the connection is lazy and retried (startup, when buying: 3 tries of 18 s, app resume, after a disconnect); the shop shows «در حال اتصال به کافه‌بازار…» and tells failures apart (not installed → open Bazaar, too old, no answer → retry, key missing, other); the purchase call survives a missing activity and a restored process; patch_android adds the Bazaar `queries`, the `PAY_THROUGH_BAZAAR` permission and R8 keep rules. Unit tests with a fake Poolakey (`app/test/billing_test.dart`). How to test on a phone: `docs/operations.md`.
- **Categories:** `category` on all 53 cases (medical, art, family, business, science, travel, crime), validated by the server, in the case list/detail (optional), shown with the difficulty on the home card, case page and archive, and as filter chips in the archive.
- **Weekend format 3 (two nights):** a newcomer suspect and new cards appear in chapter 2 (`appears_chapter`), night 1 has its own question «کی دروغ می‌گه؟» (one try, 10 coins, `POST /v1/cases/{id}/liar`), the early-solve bonus is 80 coins (was 50) and earns the plaque «پلاک شب اول», and the weekend screen has a «شب اول / شب دوم» card with a countdown. Formats 1 and 2 are unchanged. No case was written for it yet (w003 is the first to use it; Opus).
- **Weekend schedule** is Thursday 09:00 → Friday 21:00 (server constants, app texts, guide). w001 keeps its 48 h window in its file.
- Migration 0027 (`case_progress.night1`, additive). Old apps keep working; new fields are optional.

## server: proof-of-investigation time follows the case difficulty (Amin, 18 Oct 2026)

- A quick reader who reaches the clue was marked «unproven» (1 star, no leaderboard place) by the flat 180 s rule (seen on c019). The needed active time is now 90 s for a difficulty-3 case and scales with the case difficulty: 60 / 75 / 90 / 110 / 130 s for difficulty 1-5 (`economy.min_active_seconds`, `ACTIVE_TIME_FACTOR`). Still needs 2 interrogated suspects. Same rule for the «right person, wrong proof» nudge. No migration, no app change.

## server 1.30.0, app 1.29.2 (build 60): app testers (Amin, 17 Oct 2026)

- New flag `players.tester` (migration 0026, additive). A tester sees the story while it is closed to everybody and never appears on a leaderboard (all-time, daily, weekly, league prizes). Everybody else is unchanged; `opens_at` stays 2099.
- Admin: `POST /admin/players/tester {"phone": "09...", "tester": true|false}` (X-Admin-Key). It finds the player who secured the account with that number (compared as a hash; the number is never stored or logged) and sets the flag. The player must have verified that phone in the app first.
- Game app: the story tab asks the server instead of trusting the global config, so a tester's story opens (needs the next game APK).

## app 1.29.1 (build 59): fix for the black screen at start (builds 57-58)

- **Cause found:** from build 57 on, the CI build resolved a newer `shared_preferences_android` (native side rewritten) than build 56 had; the app waits for saved settings before the first screen, so it stayed on the logo. The APKs prove it: build 56 has the old plugin classes, 57-58 the new ones; nothing else in the plugins differs.
- **Fix:** `shared_preferences_android` pinned to 2.4.28 (`dependency_overrides`), and every start-up step now has a 4 s limit so the app always opens even if a plugin misbehaves. No other change; server stays 1.29.0.

## app 1.29.0 (build 58): everything in one APK (difficulty bar + stars back + all of tonight's changes)

- **Why:** tonight's tasks were scheduled separately and each built its own APK from its own branch; the last build (1.28.0+57) was made from `main`, which had neither the difficulty bar nor the stars fix (1-on-the-right, numbers under the stars), so it still showed hearts and magnifying glasses. This build merges `difficulty-bar` (with `badges-plaques`, i.e. the stars fix) into the latest `main`.
- The rating sheet and the archive «rate old cases» card now use stars too (they were hearts). One widget (`RatingPicker`) everywhere.
- Contains: weekly clock/fair board/leagues (1.27), warrants/rating sheet/rate nudge/weekend time (1.28), difficulty bar (`DifficultyBar`), stars. Server stays 1.29.0 (no server change).
- Rule from now on (Amin, 17 Oct): several tasks for one slot are ONE scheduled task, ONE branch, ONE server version and ONE APK.

## server 1.29.0, app 1.28.0 (build 57): fewer free warrants, rating sheet, rate nudge, exact weekend time

- **Warrants (Amin: players had so many that nobody spent coins on the story).** Cut: tonight's case (1 a day), all daily missions done (1 a day), streak 3 and 7, every weekend case. Kept: the first solved case ever (onboarding), streak 14 and 30, every 2nd live weekend case. New free supply for a normal player: about one warrant per two weeks (before: about 14 a week). Nothing replaces them (no free coins). Warrants already owned stay; only future grants changed (no migration); the grant is still one per solve inside the solve transaction. Rules in `economy.warrants_for_solve`. Story texts, the guide and `docs/story-mode.md` say the new rule; coin skip of the 12 h wait is unchanged and clearly priced.
- **Rating sheet** right after a solve (7 s, once per case, close button, never blocks coins), inline card kept as fallback.
- **Rate nudge** in the archive for solved cases without a rating (every 3 days at most, one tap closes, the button opens the unrated list). Built from the existing case list: no server change.
- **Weekend text:** «معمولاً» removed. The server sends the schedule (`upcoming.weekend.schedule`): «هر هفته چهارشنبه شب ساعت ۲۱ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.» The guide page (which still said Thursday 9:00 / Sunday) was fixed and the fallback countdown follows the same schedule.
- Tests: `test_story.py` (warrant rules), `test_weekly.py` (schedule text), `app/test/weekend_time_test.dart`. «چی تازه شده؟» release 57. Details: `docs/operations.md`.
- Deploy: server change, then the game APK from the same commit.

## server 1.28.0, app 1.27.0 (build 56): one game clock, a fair weekly board, leagues

- **Problem (Amin):** veterans who solved the whole archive fell behind in the weekly board, because the weekly sum counted every solve of the week including bought archive cases (a newcomer could solve 10-20 archive cases in a week). And the game day (new case at 21:00) and the week (midnight) ran on different clocks.
- **One game clock** `server/app/gameclock.py`: game day = 21:00 to 21:00 Tehran (named by the date it starts on = the case's publish date); **week = Friday 21:00 to the next Friday 21:00** (7 daily cases; the Friday-21:00 case belongs to the NEW week and has a full week). `NEW_CASE_HOUR`, `WEEK_START_WEEKDAY` (4 = Friday) are settings. Everything uses zoneinfo and is compared in UTC; the old Saturday-midnight week and `content.week_start` are gone. Missions keep their labels; login reward, ad limit and riddles stay on the calendar day on purpose. Streaks were already by case (publish date), so they are unchanged across the switch: no stored value is rewritten.
- **Fair weekly board** (`weekboard.py`): only the week's own cases count (7 nightly + the weekend case), derived from the case, not from `day`; a case counts until the next week's first case opens, then it is archive (coins, plaques, album yes; weekly points no). Tie-break: more cases, then faster. The screen says it in one sentence and counts down to the end of the week (server time).
- **Prizes** use the same standings, are paid at Friday 21:10 (a safety margin after the close), exactly once (primary key `week_settlements`, safe with 2 workers), and need at least 2 cases. The week of 16-23 Oct 2026 is the first paid by the new rule; weeks before it were paid by the old one.
- **Leagues** (`week_leagues` snapshot per week, by XP: تازه‌کار / کارآگاه / بازرس / سرپرست): own league by default, a switch for the others, top 3 of each league are paid (120/80/50; at most 1000 coins a week against 1175 before). `LEAGUES_ENABLED=false` returns to one board.
- Migration 0025 (two new tables, listed in ci.yml). `notify_plan` has a `weekresult` entry; the app no longer computes a Saturday itself. «چی تازه شده؟» release 56. Tests: `test_gameclock.py`, `test_fair_week.py`, `test_rewards.py`, `test_anticheat.py`, `app/test/leaderboard_week_test.dart`.
- Deploy: server change (migration + new rule) from this commit, then the game APK.

## server 1.27.0: admin screen «قیف و ماندگاری» (funnel and retention)

- Amin (16 Oct, for the Cafe Bazaar launch): real numbers right after publishing. New panel tab **🧭 قیف و ماندگاری** and the call `GET /admin/api/funnel?days=30` (max 90, admin key, cached 60 s per worker).
- **It works for the current players too:** everything is derived from tables that already exist (`players`, `case_progress`, `purchases`); no tracking table. **Retention is derived from case activity** (a case opened or finished on day 1/3/7 after the signup day, Tehran days), so a player who only opened the app does not count as returned. DAU/WAU use `last_seen`.
- Sections: signups per day; funnel (registered → opened a case → finished the first case → solved the first case → solved on 3 different days, the invite-paid rule) per signup-day cohort and in total; D1/D3/D7 (cohorts too young show a dot and are left out of the total) plus DAU, WAU and DAU/WAU; where players stop (last stage reached, top 10 cases opened but not finished); money (payers, conversion of registered and of D7-retained, median hours to the first purchase, purchases and coins by pack, coin quartiles of players seen in 7 days); gameplay quality (plaque 3/2/1 shares, median active seconds, average hints, failed share, per case of the last 14 days).
- Test accounts (device id «smoke-…») and banned players are left out of every number. (The existing player list does not hide smoke accounts; this screen does.)
- Plain SQL aggregates (medians and quartiles with window functions, nearest rank), no rows loaded into Python, no ids, names or emails in the answer or logs. A failing section returns `{"error": "section_failed"}` and the rest of the page works (the failure is logged as one line with the exception class only; partial answers are not cached).
- «کپی به‌صورت متن» copies a plain-text summary (also in the answer as `text`) that Amin can paste to Claude.
- Migration 0024 (additive, skipped when present): `ix_players_created_at`, `ix_players_last_seen`, `ix_progress_opened_at`, `ix_progress_finished_at`; listed in `.github/workflows/ci.yml`.
- Tests: `server/tests/test_funnel.py` (seeded cohorts, retention math with too-young cohorts, smoke/banned excluded, zero-data page, one failing section, the 90-day cap, no personal data). Details: `docs/operations.md` «Funnel and retention».
- Deploy: server only (no APK). Amin deploys version 1.27.0 from the Liara panel.
## app 1.26.3 (build 57): difficulty is a 5-level colour bar, not magnifying glasses

- One widget, `DifficultyBar` (`app/lib/theme.dart`), replaces the old `Difficulty` magnifier row: 5 equal rounded segments, level 1 on the RIGHT filling toward the left, filled segments in the level colour (1 green, 2 light green, 3 yellow, 4 orange, 5 red), the rest muted. Label per level: آسان، نسبتاً آسان، متوسط، سخت، خیلی سخت. The count and the label carry the meaning too (colour-blind safe); semantics «سختی ۴ از ۵». Null/out-of-range is clamped to 1..5.
- Shown in: archive card (compact, fixed 12 dp slot, no label), case intro (normal, with label), weekend screen header (compact, level 5 = خیلی سخت).
- No server text used «ذره‌بین» for difficulty (only avatar/frame names and case story text, left as is). App only: no push to `main`; APK from a branch pushed to `release`. Tests: `app/test/difficulty_bar_test.dart`.

## app 1.26.2 (build 56): rating is stars again, 1 on the right, a number under each star

- Amin did not like the hearts: the case rating is **stars** again (the solving score stays «پلاک»). The app reads right to left, so **1 star is on the right and 5 on the left** (it was reversed), and each star has its **number under it** so the player knows what he gives. One widget (`RatingPicker`) is used by the rating card and the write sheet; `RatingRow` shows a given rating the same way.
- App only: no server change, no push to `main` (APK from branch `release`). «چی تازه شده؟» release 56 replaces the unreleased 55 text.

## server 1.26.1, app 1.26.1 (build 55): «پلاک کارآگاهی» for solving, hearts for rating

- Amin: stars for solving and stars for rating together confused players. Now **solving gives plaques** («پلاک کارآگاهی», police-badge shield icon, brass): 3 = no mistake, 2 = one, 1 = more. **Rating a case used red hearts** (1-5; stars again in app 1.26.2) and the word «امتیاز». The data is unchanged: the server still stores `stars` for the plaque count and `rating` for hearts, so the leaderboard, weekly prizes, XP and achievements behave exactly as before. Only words and icons changed.
- Why «پلاک» and not «نشان»: «نشان‌ها» is already the achievements tab and the profile counter, so a second «نشان» would have recreated the confusion. To switch the word, replace «پلاک» in the app texts and the few server texts.
- Server texts only: mission, achievements (`stars_1`, `stars_10`), avatar `ex_threestar`, the weekly prize message and the privacy page now say plaques/امتیاز. No new call, no migration.
- «چی تازه شده؟» release 55 lists both changes.

## server 1.26.0, app 1.26.0 (build 54): invite codes explained, stars after every case, new archive

- **Invite codes (why testers got no coins):** the redeem itself works (the new player gets 100 coins at once; a test now proves it, and proves the inviter's 150 coins arrive as an inbox gift after the friend solved on 3 different days and the gift is claimed). What failed was the path around it: the only field was hidden in the profile, the first run never asked although the share text says «موقع شروع کد دعوت من رو بزن», accounts older than 7 days are refused (a tester with an older account sees an error), and the card promised the inviter's coins immediately. The app default coin numbers (300/150) did not match the server (150/100) when the config was missing; fixed.
- First run: after the guide, one optional screen «کد دعوت داری؟» (asked once, one tap on «بعداً» closes it). The invite card in the profile now says the rule in plain Persian, shows the closest friend's progress («x از ۳ روز»), how many friends came and were paid, and, for an invited player, his own progress. The share text names the 100 coins.
- New `GET /v1/referrals/status` (bounded, migration 0023 adds `ix_players_referred_by`).
- **Ratings and comments:** a big rating card right after a solve and on every finished case, including archive cases (one tap on a star rates and counts at once; an optional sentence; «بعداً» closes it). Case rows carry the average, the number of ratings and approved comments and the player's own rating (`rating_avg`, `rating_count`, `comment_count`, `my_rating`, cached 30 s per worker). The home card and the archive cards show them. A player who gave only stars may add words once; the stars stay.
- **Archive screen redesigned:** progress header (solved, stars, the price hint), coin chip that opens the shop, sort (newest, oldest, best rated, most solved), filters (all, unsolved, open, 3 stars, «ستاره ندادم»), wide cards with the scene, state (stars / lost / a brass «price · باز کن» button), difficulty and rating.
- «چی تازه شده؟» release 54 lists the three changes. Tests: `server/tests/test_invites_ratings.py`, `app/test/invite_rating_test.dart`.
- Deploy: server change (new call, migration), then the game APK from the same commit. Details: `docs/operations.md` «Invite codes, ratings, archive».

## server 1.25.7: less CPU per request on the app-start calls

- Why: the 500-player load test from Iran (15 Oct) stopped at 40-50 requests per second; the runtime meter showed each worker at about 50 % CPU (one core in all), the pool full and no 5xx. The app was CPU bound, about 24 ms of CPU per request.
- **Not measured:** the workspace could not install the server dependencies (PyPI unreachable), so nothing was profiled. These are code-review fixes of work that was clearly repeated per request; the speed gain is an estimate until the load test is repeated.
- `content.opens_at` is memoised on its pure inputs (publish day, hour, timezone). Before, `GET /v1/cases` asked `todays_case()` once per row, and every `todays_case()` rebuilt the opening time of all 50 cases (about 2,500 timezone computations per request). The list now asks once, and `_opened_case` no longer builds the opened list.
- `GET /v1/cases`, `GET /v1/cases/<id>` and `GET /v1/feed` send the model they already built (`fast_json`: same bytes) instead of validating it again and walking it a third time. The OpenAPI schema is unchanged.
- The bell/feed (`/v1/me` and `/v1/feed`): the "a case / a weekend chapter opened" items are built once per worker (60 s, bounded, nothing per player; the per-player `born` filter and the clock check still run per request) and only the `news` setting is copied instead of the whole config.
- Rate limiter: the trusted-proxy CIDR list is parsed once per setting value, not on every request.
- Same answers: `tests/test_perf.py` compares the new output with the old computation. No migration, no new setting, no rule changed (coins, stars, time and answers stay server-side).

## server 1.25.6: runtime meter (find the real limit of one worker)

- The 500-player load test (15 Oct) stopped at about 40-50 requests per second whatever the pool size or `WEB_CONCURRENCY`, and the Liara graphs showed idle CPU. This release adds a meter per worker so the next test says why: CPU share, event-loop lag, database connections in use, requests in flight, 5xx count.
- One WARNING line `runtime busy pid=... cpu=...% lag_ms=... pool=out/max inflight=...` at most every 10 s, only while the worker is busy (CPU 70 %+, loop lag 200 ms+, 50+ requests in flight or every connection checked out). No personal data.
- New admin call `GET /admin/api/runtime` (X-Admin-Key): the last minute of THIS worker (ask a few times, `pid` tells workers apart). No database use, no new setting, no migration.

## server 1.25.5: capacity for the small Liara plan

- New `server/tools/load_test.py` (N virtual players do what the app does at 21:00; ramp or `--burst`; reports requests, 429/5xx, p50/p95/p99, requests per second) and a 30-player sanity step in CI. New admin call `POST /admin/players/smoke-bulk`. How to run it from Iran: `docs/operations.md` «Capacity».
- Database pool per worker is bounded and configurable (`DB_POOL_SIZE`/`DB_MAX_OVERFLOW`/`DB_POOL_TIMEOUT`/`DB_POOL_RECYCLE`, defaults 5+5, 10 s).
- Per-worker TTL caches (`app/cache.py`) for the config rows, the solver counts on the case list and the public pieces of `/v1/config` (dropped when a case opens). Nothing per player or secret is cached.
- Rate limit: requests with a valid token are limited per player (`global_player`), the per-IP ceiling for them is a high flood guard (`global_ip_auth`); only requests without a valid token keep `global_ip`. Phones behind one carrier IP no longer block each other. Registration limits are unchanged (see the note in «Capacity»).
- Migration 0022 (additive): indexes `ix_progress_case_solved` and `ix_progress_rank` on `case_progress`.
- Docs: workers advice for 0.5 CPU, what to watch, upgrade advice.

## server 1.25.4, app 1.25.2 (build 53): weekend case, new format

- Timing: new weekend cases open Wednesday 21:00 and close Friday 21:00 (48 h), two chapters (0 h and 24 h). The reminder for a weekend opening is moved two minutes so it does not collide with the nightly one. This week's case is a one-off (Thursday 09:00 to Saturday 09:00).
- Accusing is allowed from chapter 1. Right + right early: 3 stars and +50 coins (`WEEKLY_EARLY_BONUS`); wrong costs a try.
- Two-part accusation (who + why/how, `format: 2` cases): both right = 3 stars, culprit only = at most 2 stars, wrong culprit = a try is lost and the case stays open. Older cases keep suspect + proof + motive.
- «نشان دادن مدرک»: show an evidence card to a suspect and hear a reaction written in the case file (3 shows per opened chapter, server-side count, repeats free, new `case_progress.shows` column). The reaction is never in the public case.
- Expired weekend cases are in the archive for 250 coins (`WEEKEND_ARCHIVE_COST`), «آخر هفته» badge, both chapters open, normal archive reward; a player who solved it live keeps it. Not buyable while it is open.
- Format guide for case writers: `docs/weekend-format.md`.
- App: «چی تازه شده؟». After an update the home screen shows a one-line banner (once per build; a fresh install shows nothing) that opens a titles-only sheet with «برو به …» jumps; the list is also in Settings as «چه خبر؟». Small red «تازه» tags (weekend tab and row, «نشان دادن مدرک») vanish when opened or after 7 days. The list is data in `app/lib/data/whats_new.dart`.

## server 1.25.3, app 1.25.1 (build 52): avatars and frames

- Profile avatars: 10 free faces (`det_01`-`det_10`), 8 earned by a challenge (10 cases, 7-night streak, 30-night streak, 25 three-star cases, 10 cases without hints, 3 weekend cases, story chapter 5, top 3 of a week) and 8 sold for coins (600-2500, `economy.AVATAR_PRICE`). Buying is once and forever.
- Frames drawn in code (`AvatarWithFrame`, one widget everywhere): free brass; earned bronze/silver/gold (ranks 3/6/9), ember (14-night streak), tape (50 cases), loupe (top 3 of a week); shop fingerprint 300, blinds 400, cuffs 600, stamp 600, neon 900, royal 1500 (`economy.FRAME_PRICE`). Only ember and neon move, and only on the profile and the leaderboard podium, and not when the phone asks to reduce motion.
- Server: table `player_avatars` (unique per player, kind and id) and columns `players.avatar_id`, `players.avatar_frame` (migration 0020, additive). `GET /v1/avatars` (catalog, owned, goal progress; unlocks reached goals), `POST /v1/avatars/{id}/buy` (402 not enough coins, 409 already owned, 422 not for sale), `PATCH /v1/me` accepts `avatar_id` / `avatar_frame` (422 `not_owned`). Goal unlocks are kept forever and shown as a banner (`gains.avatars`). Leaderboard rows and the profile carry `avatar_id` and `avatar_frame`. The buy route uses the `wallet` rate limit.
- App: «چهره و قاب» screen (tabs چهره‌ها / قاب‌ها, filter همه / باز‌شده / قفل‌دار, locked cards with goal and progress bar, price chips, confirm before buying). Old profiles keep their face (`det_NN` from the old index).
- Operator: nothing to set. The champion avatar and the loupe frame are granted on the player's next visit after the weekly prizes are paid.

## server 1.25.2: no more «smoke-» test players in the database

- `tools/smoke_test.py` now deletes its own throw-away player at the end (`DELETE /v1/me/smoke`, only accepted for device ids starting with `smoke-`, a real player gets 403), so every test run leaves nothing behind.
- Admin call `POST /admin/players/purge-smoke` removes all old «smoke-» players completely (every row of theirs, up to 1000 per call; call again if `more` is true). Call it once after this version is live.

## server 1.25.1, app 1.25.0 (build 51): stars without a comment, red marks on wrong accusations

- Rating a case needs only stars now: the text is optional. Stars alone are counted at once (they are in the average, not listed as a comment); a written comment still waits for the admin. One rating per player and case, as before.
- After a wrong accusation the wrong suspect, the wrong evidence card (right suspect only) and the wrong motive (weekend case) stay on screen with a red frame and a «اشتباه» tag and cannot be picked again. A selected choice now has a brass frame, so red always means wrong. A card is never marked wrong after a wrong SUSPECT (we cannot know if it was right).
- The server remembers each player's wrong accusations (`case_progress.wrong_tries`, at most 10, additive column), so the marks survive a reinstall or a new phone.
- The result screen of a SOLVED case shows «اشتباه‌های تو در این پرونده» with every wrong accusation in order; it never shows for a lost case or a clean solve.

## server 1.25.0: coins are scarcer, missions change at 21:00

- Economy (numbers only, existing players keep their coins): solving a case pays 30/20/10 for 3/2/1 stars (was 60/40/20); daily bonus 15; streak bonus 60; login calendar 10,10,15,15,20,25 and envelope 40-80; mission chest 30 (+60 every 7th day); archive case 150 coins (was 120); invites pay 150 to the inviter and 100 to the new player. Start coins and the secure-account reward stay 100.
- Achievements pay about 60% less (total about 3,410 coins instead of 8,570). «حساب امن» now says phone number and pays 10 (the 100-coin secure reward is paid separately).
- Daily missions now run from 21:00 to 21:00 (`content.mission_day_str`), the same moment the new case opens, instead of resetting at midnight; the countdown in the app reads `next_at` from the server. One-time effect of the switch: a player who already claimed the chest earlier tonight may be able to claim one more.

## server 1.24.5: case c018 rewritten, story chapter 1 in the choices format

- Content: nightly case c018 «سؤال هفتم» (opens 16 Oct) rewritten under the case-writing rules: difficulty 4, type 8 (the helpful witness is the culprit), people-first clues, side secrets for every suspect; blind-tested. Its notification body is updated.
- Story: s01ch01 «هفت‌ستاره» now plays as a real choices chapter (5 scenes, two real branches, a locked option, board people and clues); the case itself is unchanged. Story stays paused (`opens_at` 2099).
- Rules: CLAUDE.md gets «Business priority» and «Story opening gate».

## server 1.24.4: take a phone number over from another account

- «وصل کردن شماره» has a checkbox «اگر این شماره به حساب دیگری وصل است، از آن بگیر»: the number is removed from the other account (it stays, as a guest, nothing deleted) and linked to this one. Logged as `release_phone` (last 4 digits only). Without the checkbox it is still refused with 409.

## server 1.24.3: admin can link a phone number to a player

- Admin panel, player page: «📱 وصل کردن شماره» attaches (or replaces) the phone of an account, so its owner signs in with that number. No SMS, no coins; refused if the number belongs to another account (409 `phone_taken`). Logged as `link_phone` with the last 4 digits only. `POST /admin/api/players/{id}/phone`. The player page also shows the masked number.

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

