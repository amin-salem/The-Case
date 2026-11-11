# UX pack (branch `app/ux-pack`, one Cafe Bazaar release after session 8)

Design source: the design canvas boards (`Update.dc.html` and the others). Real data only: a line is hidden when its number
is not available. Sessions 1-7 push only this branch; session 8 bumps pubspec, writes the Bazaar notes and releases.

## Session 1: update modal and thank-you coins (10 Nov 2026)
- App: the small home `UpdateCard` is replaced by a centered modal `UpdateModal` («نسخه‌ی تازه آماده‌ست», reward line,
  «آپدیت در کافه بازار», ✕ 44 px, «بعداً یادآوری کن»). Opens at most once per launch, from the home page only when it is the
  visible route (never over a case screen or a dialog), after the login calendar and the reminder prompt. Every way out hides
  it for 3 days per `latest_version` (`AppUpdate.closeBanner`); the chip «نسخه‌ی تازه هست · N سکه هدیه» (`UpdateChip`) re-opens it.
  Never with the forced-update page (`min_version`). The reward line and the chip's coins part are hidden when the server
  sends no `update_bonus_coins` (an old server) or 0.
- Server: remote-config `update_bonus_coins` (default 50, 0..300, 0 = off), shown in `/v1/config`, edited in the admin block
  «📲 بروزرسانی اپ». `POST /v1/me/client` pays it once per player per `latest_version` (`app_update.grant_bonus`, ledger
  reason `update_bonus:<latest>`, checked under the player lock, inside a savepoint so a failure never loses the version
  report) and answers `{"ok": true, "bonus_coins": N}`; the app shows «ممنون که آپدیت کردی · N سکه به حسابت اضافه شد».
  The admin block shows how many were paid for the current «آخرین نسخه». No new tables or columns, so nothing in `ci.yml`.
- Compatible both ways: an old app ignores `bonus_coins`; an old server sends no `update_bonus_coins` and no `bonus_coins`.
- Tests: `server/tests/test_update_bonus.py` (repeat, race, downgrade, new install, bounds, admin save; runs on SQLite and
  PostgreSQL in CI), `app/test/app_update_test.dart`, `app/test/update_modal_home_test.dart` (text scale 1.3 and 2.0).

### Update bonus: who can be thanked (10 Nov 2026, after Amin asked to close the faked-build hole)
- The build number is reported by the app, so it can be faked. `grant_bonus` now also requires that the account was created BEFORE
  `latest_version` was set (a newer account installed the new build anyway) and has solved at least one case. A farm of new or empty
  accounts earns nothing. What stays possible: an existing player who has played lies once and gets his single `update_bonus_coins`
  (no way to prove the installed build from the server). Tests: `test_faked_build_numbers_from_new_or_empty_accounts_get_nothing`.

## Session 2: next case after a solve and the starter-pack sheet (10 Nov 2026)
Boards `After.dc.html` and `Starter.dc.html`.
- Result screen (`result_screen.dart`, `widgets/next_case_card.dart`): after a normal solve (not a story chapter) the compact
  plaques + rewards row stay on top and ONE card follows: «هنوز ذهنت گرمه؛ یکی دیگه؟». The suggested case is chosen by the pure
  `pickSuggestedCase` (`services/starter_offer.dart`) from the archive list: unsolved, never lost, not tonight's, not a weekend
  case, not the one just solved; a case that fits the player's level (difficulty cap from the rank: 2 for rank 0-2, 3 for 3-5,
  4 for 6-8, 5 from 9) comes first, then the one closest to the level, then the cheapest, then the better rated, then the newer.
  One button «باز کن · N سکه» (the usual confirm flow of `openCaseRow`); with too few coins it reads
  «… (M سکه کم داری)» and opens the starter-pack sheet, or the normal «سکه کم داری» sheet once the offer is used up/bought.
  A second link «یه پرونده‌ی دیگه نشونم بده» opens the archive tab. Below the card: «فردا ساعت ۲۱ پرونده‌ی بعدی باز می‌شه» from
  the server's real `next_case_at`.
- Real data only: the line «N٪ کارآگاه‌ها حلش کردن» is shown only when a case row carries `solve_rate`. The server does NOT send it
  today (`/stats` answers only after the player finished that case), so the line is hidden. Suspect count comes from the new
  additive `suspect_count` of `/v1/cases` (0 from an old server = the part is hidden).
- Starter-pack sheet (`widgets/starter_sheet.dart`, `StarterOffer`): only when the product exists in the store config with a price,
  the pack is not bought (`no_ads`), the phone is online, and the local counter `pref_starter_offer_shown_<playerId>` is below 2
  (at most twice per account lifetime; local, as agreed). Moments: (a) a hint, a detective tool or an archive case needs more
  coins than the player has (`showNeedCoins(..., starter: true)` replaces the plain sheet; it carries a «سکه‌ی رایگان با دیدن
  تبلیغ» link so the free route is never hidden); (b) after the very first solve, once the reading/secure/rate prompts are done.
  Never in a flow that blocks tonight's case: the sheet closes in one tap (✕ 44 px or «فعلاً نه») and tonight's case costs nothing.
  Content: 1000 coins (from the config), «+ همیشه بدون تبلیغ», tiles computed from real prices (archive cases the coins open at the
  cheapest unsolved locked prices; first hints from `hint_costs`; a tile whose number is 0 is dropped), the store price,
  «فقط یک بار برای هر حساب».
- Events (existing `events` table, `POST /v1/events`; the app had no sender, so `Api.track` is new and best effort):
  `starter_offer_shown|tapped|closed|bought` with `moment` = `lack_coins|first_solve`.
- Admin: `economy_report._starter_offer` + a new block «۶. بسته‌ی شروع» in the economy tab (shows, players who tapped, bought,
  closes, split by moment). Missing/empty/error payloads show «هنوز داده‌ای نیست» (tolerant of the mock payloads).
- Server: additive `suspect_count` on case rows; no migration, nothing in `ci.yml`.
- Tests: `app/test/starter_offer_test.dart` (choice of the case, show-twice rule, counter per account, tiles),
  `app/test/next_case_widget_test.dart` (card, sheet, result screen; text scale 1.0, 1.3, 2.0), `server/tests/test_starter_offer.py`
  (funnel on SQLite and PostgreSQL, events endpoint, `suspect_count`, admin page).
## Session 3: shop value and voice sweep (10 Nov 2026)
- Shop (`shop_screen.dart`, new pure helper `services/shop_value.dart`): the «کارآگاه ویژه» card is first; the three bags
  follow, each with one line «≈ N پرونده» (real coins ÷ the 150-coin typical archive case; hidden when it is under one case).
  The «+٪ بیشتر» line and its explanation sentence are gone. The badge «بیشترین ارزش» goes only to the bag with the most
  coins per toman from the real store prices (none when a price is unknown or two bags tie). The VIP card states only
  «کل بایگانی باز، بدون سکه» and «سرنخ اول هر پرونده رایگان»; the line «اگه ماهی N پرونده‌ی قدیمی یا بیشتر باز کنی، از سکه
  خریدن ارزون‌تره» uses N computed from the VIP price and the best real coin rate (hidden when it cannot be computed).
  The starter pack stays its own row under the bags with its real price. Buy flows, errors and dialogs are untouched.
  Revenue note: the VIP and the best-value bag now carry the clear value story; no free coins were added.
- Voice sweep: `docs/app-voice.md` (4 rules, glossary). Applied in `app/lib`: «ـهٔ» forms, formal verbs in the comments
  screen, «بازیکن» → «کارآگاه», «را» in the accuse tag, and the generic / offline / server-down errors now say that coins and
  progress are safe. Case and story content untouched.
- Tests: `app/test/shop_value_test.dart` (badge, tie, unknown price, VIP break-even, hidden lines), `app/test/app_voice_test.dart`
  (curated lint over `app/lib`, `allowed` list empty).
- Not done on purpose: «باز است» on the home story chip stays (an existing test pins it).

## Session 4: archive picks and the weekend tab (10 Nov 2026)
Boards `ArchivePick.dc.html` and `Nav.dc.html` (the nav board stays a proposal; the weekend tab is NOT removed).
- Server `GET /v1/cases/picks` (`server/app/picks.py`, route declared before `/{case_id}`): up to 3 archive cases the player has
  not solved or lost (never tonight's), each with ONE real reason, chosen in this order and never the same case twice:
  `easy` «آسان» (difficulty 1-2, solve rate >= 60 % among >= 20 detectives who played it), `popular` «پرطرفدار» (best average
  rating >= 4.0 over >= 20 ratings, else the most solves in the last 30 days with >= 20), `taste` «سلیقه‌ی تو» (a topic where this
  player solved >= 2 cases, and a case of that topic that >= 20 detectives played). A reason whose real sample is too small is
  dropped; fewer than 3 picks is fine; none = `{"picks": []}` and the app shows no row. The answer carries only the real numbers
  behind the reason plus this player's current `unlock_cost` (first-days prices and promo included).
- Cost: one shared GROUP BY over `case_progress` (cached 120 s per worker, 2 entries) + the existing shared ratings summary + one
  indexed read of the caller's own progress. Nothing per player is cached (a new solve shows at once). Rate policy: the existing
  `read` policy (GET under /v1). Fail-open: any error answers `{"picks": []}` with 200. No migration, nothing in `ci.yml`.
- App: `ArchivePicksRow` on top of the archive list («پیشنهاد برای تو · از روی N پرونده‌ای که حل کردی», three equal cards,
  tap selects, detail card with the real reason and «باز کن · N سکه» / «باز کن · رایگان» / «باز کن» for an opened case). The button
  is the normal `openCaseRow` (confirm dialog, price re-check, first-days prices, need-coins sheet). Hidden for no picks, offline, an
  old server or any error; the search, filters and list below are unchanged. Picks of cases that are solved/lost/not in the list are dropped.
- Weekend tab: kept. `MainShell` sends the existing event `weekend_tab_open` (no props) the first time the tab is opened in an
  app launch (once per session). Admin economy tab, new block «۷. تب «آخر هفته»»: opens per Tehran day, cards for the daily average on
  Thursday-Saturday vs the other days, and a table of the last 30 days; empty/unknown payloads show a calm «هنوز کسی باز نکرده» line.
  Decide from it next release whether to fold the tab into home/archive.
- Tests: `server/tests/test_archive_picks.py` (pure choice, minimum samples, database stats, route price, fail-open, weekend split;
  runs on SQLite and PostgreSQL), `app/test/archive_picks_test.dart` (parsing, row, text scale 1.3/2.0, hidden on error/none, once-per-launch event).

## Session 5: lean home and empty/offline/error states (11 Nov 2026)
Boards `HomeLean.dc.html` and `States.dc.html`. App only (no server change, no migration, nothing in `ci.yml`).
- Home (`home_screen.dart`, pure rules in `services/home_rules.dart`): one primary action (tonight's hero) and the two cards
  (archive + weekend; the weekend card keeps its real state). Everything else shows only when it asks something of the player:
  - Streak row: the streak is at risk (tonight not solved/lost yet and streak >= 3), or the next ladder step is exactly 1 night away,
    or the server offers a streak repair (the repair button lives in this row, so it must stay reachable).
  - «امن‌کردن حساب»: not secured AND (3 or more solved cases OR a purchase). A purchase = a verified store purchase on this phone
    (`Api.hasBought`, local flag `bought_coins_<player>`, set in `verifyPurchase`) or `no_ads` / VIP. The ✕ (48 px) hides it for 7 days
    (`secure_row_closed_<player>`, local); the securing flow stays in the profile/account screen.
  - One collapsed row «بیشتر» (`more-toggle`) holds the missions card, the culprit album strip, «چی تازه شده؟», story, invite
    (profile), leaderboard and shop: nothing was removed, only moved. A finished missions chest shows «صندوقچه‌ی مأموریت‌ها آماده‌ست»
    on the closed row. The old «تازه‌ها» row and the always-visible missions/album rows are gone from the page itself.
  - The update chip (session 1), the next-case card and starter sheet (session 2) are untouched.
- `StateView` (`widgets/state_view.dart`): icon in a circle, title, one explaining line, one primary button, optional quiet second
  button. Factories `offline`, `error`, `empty`, and `forError(e)` which chooses by WHAT went wrong (`Api.failKind`), not by `Api.online`
  (a down server also flips `online`). Errors say coins and progress are safe; a refusal that carries its own sentence (too many
  requests, a business rule) keeps that sentence. No raw codes: the old «کد خطا: …» line on the home error box is gone.
  Offline and error views retry by themselves once when the connection returns (`onBackOnline`, one call per return); the button is
  disabled while a retry runs. Inside a list it takes its own height, in a fixed-height page it scrolls (huge fonts never overflow).
- Used in: home case list (offline with nothing saved / error), archive (error, empty, nothing matches the filters), messages hub
  (error, empty), inbox sheet (error, empty), leaderboard (error, empty league), shop (offline with no store data), profile (no profile).
- Tests: `test/home_rules_test.dart` (the rules), `test/state_view_test.dart` (1.0/1.3/2.0, no English text, forError, retry once,
  offline -> online auto retry), `test/home_nav_test.dart` (visibility per state, the ✕ and 7 days, «بیشتر» keeps every entry,
  offline -> online loads the home without a tap, error page; fonts 1.0/1.3/2.0). `seedHome` got `secured`, `casesSolved`, `bought`,
  `secureClosedAt`.
- Revenue note: the streak-at-risk row and the starter/after-solve cards stay in front; the securing row now meets players who have
  something to lose (3 solves or a purchase), which protects paying accounts. Nothing sellable was given away.

## Session 6: leaderboard redesign (11 Nov 2026)
Board `Leaders.dc.html` (read). Real data only; `portrait-ages.json` untouched (no portrait was added, `test_content.py` still pins it).
- App (`leaderboard_screen.dart`, `services/board_text.dart`, `widgets/player_sheet.dart`): the three tabs keep their podium (2 – 1 – 3, second
  place on the right in RTL), my pinned row and the league switch. New: (a) my pinned row says «N امتیاز تا رتبه‌ی بالاتر (رتبه‌ی X)»
  (weekly and all time), «N ثانیه …» (daily, same plaques) or «N شب …» (streaks), from the server's `gap` (the number that PASSES the place
  above, never 0); with no gap the old «جزو ۱۰ کارآگاه اول» line stays. (b) Daily tab: a card with tonight's case and «N کارآگاه حلش کردن ·
  سریع‌ترین ۹:۴۲ · میانه ۱۳:۱۸» (each part hidden when unknown). (c) «همیشه» has two chips: «پلاک‌ها» and «زنجیره» (the live streak board, a line
  with «رکورد خودت: N شب»). (d) Tap a podium place or a row → player sheet: cases solved, streak, best streak, league history of the last weeks;
  a failing load keeps the sheet with a retry state and a «بستن» button. (e) «بیشتر نشون بده» loads the next page (`next_offset`), at most 1000 deep.
  Old server: no `gap`, `daily`, `pid` or `next_offset` = the old board (rows not tappable, no paging button).
- Server (`routers/leaderboard.py`): `GET /v1/leaderboard` got `offset`, `gap`, `daily`, `next_offset` and a `pid` on each row. The daily and all-time
  boards no longer load every player: a page (`limit` ≤ 100 + 1 row to know if more exist), my rank by COUNT with a total order
  (stars, seconds, progress id / stars_total, cases_solved, id) so pages never overlap, and one OFFSET read for the place above.
  Weekly keeps its 45 s per-worker cache (first `offset+limit+1` rows, window 200) and `weekboard.standings(offset=)` for the place above me.
  `GET /v1/leaderboard/streaks`: the 300 longest STORED streaks of visible players (index `ix_players_streak`), filtered by
  `streakrepair.LiveStreak` (a dead streak never shows), cached 60 s per worker as plain rows; `my_best`, `gap` in nights; my `rank` is 0 (no place)
  when I am below the 300 candidates. `GET /v1/players/{pid}/card`: public numbers only (nickname, avatar, rank title, cases solved, plaques, live
  and best streak, league of the last 6 weeks read by the primary key `(week, player_id)`); hidden accounts (banned, testers, new unsecured when
  the 48-hour switch is on) and unknown ids answer the same 404 `no_player`. Own policy `player_card` (20/10 s, 300/10 min; env `RL_PLAYER_CARD`).
  Daily stats: solved = visible players who solved tonight's case that night; fastest and median come from RANKED solves only (a rush cannot
  set the record); cached 30 s.
- `Player.id` is now sent to other players as `pid`. It is a random 32-character value, not a credential (the token is signed with the server secret
  and a per-account generation), and only the card endpoint accepts it, behind the limiter.
- Migration `0037_board_indexes` (additive, guarded for databases built from the models): `ix_players_stars_total`, `ix_players_streak`; the CI
  index check in `.github/workflows/ci.yml` lists both.
- Not done on purpose: the temporary «قهرمان هفته» frame. It needs a new frame item, an expiry per player and an idempotent grant inside the weekly
  settlement, which is more than a simple change; it can be its own task. The design's «زنده» chip and the next-case clock were left out (no real data on this board).
- Kept working (grep checked): update modal (`UpdateModal`), next-case card and starter sheet, shop value + voice lint, archive picks row, lean home
  («بیشتر» row still lists the leaderboard), `StateView` on the board's error/empty states.
- Tests: `server/tests/test_board_redesign.py` (paging, gaps, hidden/banned accounts, rushes excluded from stats, empty boards, dead streaks, card
  privacy and bounds, rate policy; runs on SQLite and PostgreSQL), `app/test/board_redesign_test.dart` (texts, old server, RTL podium, sheet and its
  failure, streak switch, paging, text scale 1.3 / 2.0). The existing `leaderboard_screen_test.dart` and `leaderboard_week_test.dart` stay as they were.
