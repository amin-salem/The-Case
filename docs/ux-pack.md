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
