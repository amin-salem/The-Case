# Changelog

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
