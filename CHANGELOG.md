# Changelog

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
