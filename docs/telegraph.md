# «تلگراف» — Morse mini-puzzle (Amin approved the design, 12 Nov 2026, priority Normal)

Design source: Design canvas https://claude.ai/artifact/QFarByYdV94LXsfJSbzJw9 (Artifact tool, action read),
boards `TelHub`, `TelDecode`, `TelCheck`, `TelHard`, `TelHint`, `TelSolved`, `TelBook`, `TelSend` (component `Tel.dc.html`).
Style = the new top list and «کارت من»: minimal, RTL, status by design not by labels, as few words as possible.
The brass telegraph key image is `telegraph_key.webp` (transparent, hub hero); It is in the repo at `app/assets/banners/telegraph_key.webp` (branch app/id-card).

## What it is
- A quick night puzzle next to the daily case: the player decodes a Morse telegram. Four levels: آسان (word), متوسط (phrase),
  سخت (sentence), خیلی سخت (paragraph). Tapping dots/dashes on a keyboard of Persian letters; shields = lives.
- The player discovers the Morse table by playing. They own a personal incomplete codebook («دفترچه‌ی رمز»):
  a letter's code is shown only once learned. Letters whose code is known are disabled on the keyboard.
- **Guesses are tentative (design update, 12 Nov 2026, board `TelCheck`).** Tap a code, tap a letter: EVERY place of that
  code fills with the guess (golden ink). A guess can be replaced freely, costs nothing and is never judged on the spot
  (a letter used for one code moves if used for another). Only the button «بررسی پیام» judges, and only when every place is
  filled. A failed check costs one shield (3 shields) and does not say which letter is wrong. No per-letter right/wrong feedback.
- **Help (رمزیاب) has two choices, the player picks the code:** «فرضم درسته؟» (4 coins, only right/wrong for the guess already
  placed; right = that code becomes known tonight, wrong = the guess is cleared) and «حرفش رو باز کن» (10 coins, opens the letter
  everywhere and permanently adds it to the codebook). Prices are config, not hard-coded.
- The key is tactile: lever animation and glowing dots/dashes when a code is selected; optional haptic with the existing
  «لرزش» setting; no sound needed to solve; respect reduced motion (`MediaQuery.disableAnimations`).
- Tonight's telegram, when decoded, unlocks one extra angle on the daily case (a clue sentence). **It is never required:**
  the case must be fully fair and solvable without it. Value comes from discovery and story, not obligation.
- Difficulty is not just length. Version 1 ships short messages with repetition and context (word, phrase, sentence);
  «بدون فاصله» and the noisy/«خش‌دار» code (board `TelHard`) come later, each introduced alone with one logical discovery.
  Content validator: simulate a fresh player's codebook and require every text to have a reasonable starting point.
- Once a week (night 7) the telegram may end with one short question that pays off the weekly story; no per-night quiz.
- «رمز بفرست»: the player writes a short text, gets a golden telegram card and shares it (with invite code, existing share mechanism).
- 7-night week with signal bars, old telegrams list.
- NOT in version 1 (Amin, 12 Nov 2026): the «حروف پرکاربرد» (40 coins) pack, paragraph/no-space nights, friend-to-friend telegrams.
  Decide the pack after seeing how often hints are bought (it speeds up the end of the game).
- Business: does not give away coins; it creates a new coin sink (two hint prices) and invites (share card).

## Rules
- Morse is produced and checked by code from ONE table; no model writes Morse. First verify the Persian table against the
  official one (letters that share a code, e.g. ث/س/ص, must be treated as equivalent when checking answers). Add a test that
  encodes and decodes every texts in the pool.
- Normalise text (ZWNJ, Arabic ي/ك, digits) before checking.
- Server is the boss of the codebook, hints, coins and unlocks. The check endpoint judges the whole message (equivalence classes for same-code letters); hints are atomic and idempotent (unique constraint
  on (player, letter)); two simultaneous requests must not charge twice. Additive migrations, listed in ci.yml.
- Content pool: ~30 nights first, written in the house voice (cold, short, detective; recurring informant «مخبر شب»,
  a small story over each week, last night of the week pays it off). Every text must carry a clue, a jab or a small twist;
  neutral example sentences are rejected. Validation script: only allowed letters, length per level, no duplicates, no bad words.
- Wording: «کارآگاه», «مظنون»; no «ایمن»/«رمزنگاری‌شده» claims. Not in store texts as AI.
- Friend-to-friend telegrams are NOT part of this task (see `docs/ideas-later.md`).
