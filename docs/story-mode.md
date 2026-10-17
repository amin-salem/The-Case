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
2. Then each chapter needs one **warrant «حکم بازرسی»**. Free warrants are **scarce on purpose** (Amin, 17 Oct 2026,
   so that coins buy the rest): the player's very first solved case (onboarding), a streak of **14 and 30** nights,
   and every **second** live weekend case (the 1st, 3rd, 5th). Tonight's case and the daily missions give none any
   more. Rules live in `economy.warrants_for_solve`. Normal player: about one free warrant per two weeks.
3. No warrant: the next chapter opens by itself **12 hours** after the previous one is finished; the wait
   can be skipped with coins.
4. Later: a season pass (whole season open + gold badge). No energy system that stops play mid-case.

## Content
Chapters live on the server like other cases (no app build for new chapters). Written about one chapter
per scheduled run, alongside the nightly cases.

## Notifications for story chapters (added 10 Oct)
- When the chapter list says the next chapter opens later (the 12-hour wait, `next_open_at`), call `Reminders.i.storyReady(openAt, nextChapterTitle)` from the story screen after every list load (it is safe to call repeatedly: it replaces the old one). When a chapter is opened or skipped, call it with the new time or nothing.
- The story opening itself and the weekend chapters already come from the server's `notify` list in `/v1/config` (content.notify_plan).

## Interactive chapters: the choices format (added 12 Oct 2026)

Story chapters play like an interactive film: a chapter is **4-5 short scenes**, each with 2-3 **options**; the
player picks one. Choices cost something (a path closes, another opens) but **never block finishing the chapter**.
An option can be **locked** until the player holds a clue found earlier. Everything found goes to the persistent
**season case board** (people met with a relationship, clues held, clues skipped). The accusation stays at the end
of the chapter (a season finale later) and works exactly as before: the scenes are how the player reaches the
evidence and statements, the case itself (suspects, evidence, solution, hints) is unchanged.

### Fields (added to the normal chapter JSON, next to `suspects`, `evidence`, `solution`, `partner_*`)

| field | meaning |
|---|---|
| `scenes` | list of 1-8 scenes (authors write 4-5). **The first one starts the chapter.** |
| `scenes[].id` | unique, `[A-Za-z0-9_]`, up to 24 characters |
| `scenes[].text` | the scene (narration or dialogue), 1-1400 characters (authors: **60-140 words**) |
| `scenes[].speaker` | optional: `"partner"` shows it as ناصری's dialogue bubble; absent = narration card |
| `scenes[].options` | 1-3 options (authors: 2-3); at least one must never be locked |
| `options[].id` | unique inside the scene |
| `options[].title` / `sub` | bold title (up to 120 characters) and a short subtitle |
| `options[].goes_to` | the id of a scene, or the id of `ending` |
| `options[].gives_clue` | optional list of clue ids picked up by choosing it: ids from `board.clues` or **evidence ids** of the chapter |
| `options[].needs_clue` | optional clue id (or list): the option is locked until the player holds it. The app shows «قفل است: به یک سرنخ از فصل N نیاز داری» |
| `options[].relations` | optional `{person_id: state}`, state is `unmet`, `neutral`, `friendly` («با تو راحت است») or `suspicious` («مشکوک به تو») |
| `ending` | `{id, text, speaker?}`: the last scene, no options. After it the app opens the normal interrogation and accusation screens. Do **not** write the outcome here (the partner's win/lose outro still comes after the accusation) |
| `board.people` | `[{id, name, role?}]` people of the chapter shown on the board (usually the suspects and the people the player meets) |
| `board.clues` | `[{id, title, text?}]` extra clues that are not evidence cards. Evidence ids can be used in `gives_clue` without listing them here |

Old chapters without `scenes` still work: they play as one scene (the `partner_intro`) with a single «شروع» option,
then go to the accusation.

### What the validator (`validate_story`, run by CI) enforces
Every scene is reachable from the first; every `goes_to` exists; no dead ends and no loops (the graph is acyclic);
every scene can reach the ending; every clue id exists; every `needs_clue` can be obtained on at least one path
**before** the scene that offers the option; every scene keeps at least one option that is never locked; sizes are
bounded. It **cannot** check the rules below, the writer must.

### Authoring rules
1. Each scene is **60-140 words**, spoken Persian for dialogue, with 2-3 options. Options are short, concrete
   actions («برو سراغ قهوه‌چی», «دفتر را بخوان»), never «درست/غلط».
2. **At least two real branches per chapter**: two different options lead to different scenes (not just different
   words before the same scene).
3. Every option is **fair**. No path may lose evidence needed for the solution: the solution never depends on a
   single choice. A clue that only one branch shows must also be reachable (maybe in another form) through the
   case cards or the interrogation, so a player who took the other branch can still solve it.
4. Choices change **relationships** (`relations`) and **which extra clues show** (`gives_clue`), and locked options
   reward earlier attention (a locked option's clue is always obtainable earlier, checked by the validator).
5. **No spoilers**: scene text, option titles and relation changes never reveal or hint at the culprit or the
   solution (not checkable automatically: re-read every scene as a player who has not solved the case).
6. The scenes lead the player into the existing evidence and statements; they never replace them, and the
   `intro`, suspects, evidence and `solution` keep following `docs/case-writing-rules.md`.
7. Keep the season thread (`thread`) for after the chapter. Relationship states may carry over between chapters
   through the board (same person id in later chapters keeps the state until a choice changes it).

### Example (short)
```json
"scenes": [
  {"id": "market", "speaker": "partner", "text": "…60-140 words…", "options": [
    {"id": "m1", "title": "برو سراغ قهوه‌چی", "sub": "او همه‌چیز را می‌بیند",
     "goes_to": "cafe", "gives_clue": ["e3"], "relations": {"abbas": "friendly"}},
    {"id": "m2", "title": "اول در گاوصندوق را ببین", "sub": "ردی هست؟",
     "goes_to": "safe", "gives_clue": ["safe_scratch"], "relations": {"abbas": "suspicious"}}]},
  {"id": "cafe", "text": "…", "options": [
    {"id": "c1", "title": "از نگهبان بپرس", "goes_to": "office"},
    {"id": "c2", "title": "دفتر قهوه‌چی را بخوان", "goes_to": "office", "gives_clue": ["ledger"]}]},
  {"id": "safe", "text": "…", "options": [
    {"id": "s1", "title": "از نگهبان بپرس", "goes_to": "office"},
    {"id": "s2", "title": "به قهوه‌چی سر بزن", "goes_to": "office"}]},
  {"id": "office", "text": "…", "options": [
    {"id": "o1", "title": "دفتر قدیمی را باز کن", "sub": "نیاز به سرنخ قهوه‌چی",
     "goes_to": "end", "needs_clue": "e3", "gives_clue": ["old_book"]},
    {"id": "o2", "title": "برو سراغ مظنون‌ها", "goes_to": "end"}]}],
"ending": {"id": "end", "speaker": "partner", "text": "…"},
"board": {"people": [{"id": "abbas", "name": "عباس", "role": "قهوه‌چی"}],
          "clues": [{"id": "safe_scratch", "title": "خراش روی گاوصندوق", "text": "…"},
                    {"id": "ledger", "title": "دفتر قهوه‌چی"}, {"id": "old_book", "title": "دفتر قدیمی"}]}
```

### The server
`GET /v1/story/chapter/{id}/state` (the player's current scene with its options, locked ones marked and no
destinations, plus the chapter's board), `POST /v1/story/chapter/{id}/choose {scene, option}` (the server checks the
option belongs to the current scene and its clue requirement; repeating a pick returns the same state; at most 40
choices per chapter), `GET /v1/story/board` (the season board: people, clues held / open / missed). State lives in
table `story_state` (one row per player and chapter). The case endpoint hides `scenes`, `ending` and `board`.

FORMAT_READY: choices-v1
