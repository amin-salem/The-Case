# Changelog

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
