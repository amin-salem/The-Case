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
