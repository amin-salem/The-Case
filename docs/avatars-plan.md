# Profile avatars: free, earned and exclusive (spec for the build run)

Today: `Player.avatar` is an index into app/assets/avatars/det_01..det_10 (webp). Anyone can pick any.

## Catalog (server is the boss: server/app/avatars.py)
Each avatar: id (`det_01`…), rarity, how it unlocks, price (if coins), and a Persian title + one-line story.
- **free (12):** det_01 … det_12, everyone owns them.
- **earned (8), free but only by a challenge** (shown locked with the goal and a progress bar; unlock is automatic when the goal is met, with a celebration):
  | id | title | goal |
  |---|---|---|
  | ex_rookie | کارآگاه تازه‌نفس | solve 10 cases |
  | ex_nightowl | شب‌زنده‌دار | 7-day streak |
  | ex_ironstreak | زنجیره‌ی آهنین | 30-day streak (best_streak counts) |
  | ex_threestar | سه‌ستاره‌ی واقعی | 25 cases with 3 stars |
  | ex_nohint | چشم‌تیز | 10 solved cases without any hint |
  | ex_weekend | استاد آخر هفته | solve 3 weekend cases |
  | ex_partner | شریک ناصری | finish story chapter 5 |
  | ex_champion | قهرمان هفته | finish top 3 of a weekly leaderboard (also by rewards.py) |
- **shop (8), bought with coins** (once, forever; price grows with rarity): epic 600–900, legendary 1800–2500:
  | id | title | rarity | price |
  |---|---|---|---|
  | ex_alchemist | پیرِ کیمیاگر | epic | 600 |
  | ex_journalist | خبرنگار شب | epic | 600 |
  | ex_qajar | بازرس دوران قاجار | epic | 800 |
  | ex_cat | بازرس و گربه‌ی سیاه | epic | 800 |
  | ex_chef | سرآشپز سایه‌ها | epic | 900 |
  | ex_shadow | بازرس سایه | legendary | 1800 |
  | ex_diva | ستاره‌ی صحنه‌ی نوآر | legendary | 2200 |
  | ex_gold | کارآگاه طلایی | legendary | 2500 |
- **limited (later):** Nowruz and Yalda avatars sold only during the event.
Prices are constants in economy.py so Amin can tune them. Coins are a sink here: this is the main use of saved coins.

## Server
- Alembic (only adds): table `player_avatars (player_id, avatar_id, how, created_at)`, unique (player_id, avatar_id). Free avatars need no row.
- `GET /v1/avatars` → catalog + owned + locked reason + progress numbers. `POST /v1/avatars/{id}/buy` (coins, atomic, idempotent, 409 if owned). `POST /profile` with `avatar` only accepts owned avatars (422 `not_owned`). Challenge unlocks are checked after solves/streaks/story/rewards (reuse progress.record / achievements) and add a Gains entry.
- Old profiles keep their avatar; leaderboard rows show the avatar id.
- Tests: ownership, buy twice, not enough coins, locked pick refused, unlock by goal.

## App
- Profile avatar picker: tabs «همه / باز‌شده / قفل‌دار»; owned = normal; locked-by-goal = dimmed with a lock, goal text and progress bar; shop = price chip in coins; legendary has a brass frame. Buying asks to confirm. Placeholders (a code-drawn silhouette) until the images arrive; images go to app/assets/avatars/ex_*.webp.
- Home-screen and leaderboard avatar widgets must load any id.

## Avatar frames (added 10 Oct; part of the same build run)
A frame is a decorative border around the avatar, chosen separately from the avatar. Frames are **drawn in code** (CustomPaint, no image files needed), so no AI images are required and they stay sharp at every size.
- Data: `Player.avatar_frame` (str, default `frame_brass`; a column added by the migration) and the same ownership table with a `kind` column (`avatar` | `frame`; existing rows default to `avatar`). `GET /v1/avatars` returns both lists; `POST /v1/avatars/{id}/buy` works for frames; `POST /profile` accepts `avatar_frame` only if owned (422 `not_owned`). Leaderboard rows and profile show the player's frame, so other players see it (the social reason to buy).
- **Free (everyone):** `frame_brass` (thin brass ring).
- **Earned by a challenge:**
  | id | look | goal |
  |---|---|---|
  | frame_bronze | bronze ring | reach detective rank 3 |
  | frame_silver | silver ring | reach rank 6 |
  | frame_gold | gold ring | reach rank 9 |
  | frame_ember | ring with slow drifting embers | 14-day streak |
  | frame_tape | yellow crime-tape wrapped diagonally | solve 50 cases |
  | frame_laurel | golden laurel leaves | top 3 of a weekly leaderboard |
  (Use the real rank numbering in the code; adjust the numbers if ranks differ.)
- **Shop (coins):**
  | id | look | price |
  |---|---|---|
  | frame_fingerprint | glowing fingerprint swirl ring | 300 |
  | frame_rain | blue-grey ring with rain drops sliding down | 400 |
  | frame_gears | brass clockwork gears turning slowly | 600 |
  | frame_wax | red wax seal edge with stamped notches | 600 |
  | frame_neon | neon-noir double ring, soft pulse | 900 |
  | frame_royal | animated gold shimmer sweeping around | 1500 |
- Performance and taste: animations only on the profile and leaderboard top rows; the whole list is drawn static when the system reduces motion or the phone is low-end. One shared widget `AvatarWithFrame(avatar, frame, size)` used everywhere an avatar appears.
- Picker: a second tab «قاب‌ها» in the same screen, with the same locked/earned/price states and a live preview on the player's avatar.
- Tests: ownership, buy, not enough coins, locked frame refused, challenge unlock.
