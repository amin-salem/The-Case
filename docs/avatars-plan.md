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
