# Story mode «پرونده‌های سرگرد ناصری» (decided 2026-10-07)

Replaces the planned 7-day big case. An endless career, played at the player's own pace, beside the
nightly case (daily habit + leaderboard) and the weekend case (weekly event), which stay as they are.

## Season 1 (already shown in the app as «به‌زودی»)
- Title **«کبریت سوخته»**: a serial thief who leaves a burnt match at every scene; ناصری has chased him
  for three years. Tagline and opening time live in `STORY_SEASON` in server/app/content.py
  (opens 2026-10-12 00:00 Tehran). The app's story tab (app/lib/screens/story_screen.dart) shows the
  banner (assets/banners/story_s01.webp), ناصری's card and a countdown until then.

## Story
- The player is a rookie detective. Partner: **سرگرد ناصری**, a sharp, slightly sarcastic veteran.
  He introduces each chapter, reacts to how the player did (stars, wrong accusations), gives the hints
  in his own voice, and remembers earlier chapters.
- **Chapter = one full case**, difficulty 5, following `docs/case-writing-rules.md` (blind test too).
  Each chapter also leaves one small thread (a symbol, a name, an object) of the season mystery.
- **Seasons of ~10 chapters.** A big mystery runs under the season; the last chapter solves it. Season 1's
  mystery is the serial-killer / thief story planned for the 7-day case. Then a new season starts.
- Each season has a short bible written first (`server/app/content/story/sNN/bible.md`: the mystery,
  threads per chapter, partner's arc) so every chapter fits.
- A career map screen: chapters as a path, rank badges, the partner's notes.

## Opening chapters
1. Chapters 1–3 of season 1: open at once, free (the hook).
2. Then each chapter needs one **warrant «حکم بازرسی»**. Earned by: solving tonight's case, finishing
   the daily missions, streak milestones, riddles. (The story pulls players into the daily loop.)
3. No warrant: the next chapter opens by itself **12 hours** after the previous one is finished; the wait
   can be skipped with coins.
4. Later: a season pass (whole season open + gold badge). No energy system that stops play mid-case.

## Content
Chapters live on the server like other cases (no app build for new chapters). Written about one chapter
per scheduled run, alongside the nightly cases.

## Notifications for story chapters (added 10 Oct)
- When the chapter list says the next chapter opens later (the 12-hour wait, `next_open_at`), call `Reminders.i.storyReady(openAt, nextChapterTitle)` from the story screen after every list load (it is safe to call repeatedly: it replaces the old one). When a chapter is opened or skipped, call it with the new time or nothing.
- The story opening itself and the weekend chapters already come from the server's `notify` list in `/v1/config` (content.notify_plan).
