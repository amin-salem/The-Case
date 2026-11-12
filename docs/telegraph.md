# «تلگراف» — Morse mini-puzzle (Amin approved the design, 12 Nov 2026, priority Normal)

Design source: Design canvas https://claude.ai/artifact/QFarByYdV94LXsfJSbzJw9 (Artifact tool, action read),
boards `TelHub`, `TelDecode`, `TelHard`, `TelHint`, `TelSolved`, `TelBook`, `TelSend` (component `Tel.dc.html`).
Style = the new top list and «کارت من»: minimal, RTL, status by design not by labels, as few words as possible.
The brass telegraph key image is `telegraph_key.webp` (transparent, hub hero); Amin supplies the file, ask if it is not in the repo.

## What it is
- A quick night puzzle next to the daily case: the player decodes a Morse telegram. Four levels: آسان (word), متوسط (phrase),
  سخت (sentence), خیلی سخت (paragraph). Tapping dots/dashes on a keyboard of Persian letters; shields = lives.
- The player discovers the Morse table by playing. They own a personal incomplete codebook («دفترچه‌ی رمز»):
  a letter's code is shown only once learned. Keys for already known codes are disabled in the encode direction.
- Why spend coins: a hint (10 coins, «این کد رو باز کنم؟») permanently adds ONE letter to the codebook; a pack «حروف پرکاربرد»
  (40 coins) adds the most common letters. Never block the free path: every night is solvable without coins.
- Tonight's telegram, when decoded, unlocks one extra evidence clue for the daily case (a clue sentence per case).
- «رمز بفرست»: the player writes a short text, gets a golden telegram card and shares it (with invite code, existing share mechanism).
- 7-night week with signal bars, old telegrams list.
- Business: does not give away coins; it creates a new coin sink (hints, packs) and invites (share card).

## Rules
- Morse is produced and checked by code from ONE table; no model writes Morse. First verify the Persian table against the
  official one (letters that share a code, e.g. ث/س/ص, must be treated as equivalent when checking answers). Add a test that
  encodes and decodes every texts in the pool.
- Normalise text (ZWNJ, Arabic ي/ك, digits) before checking.
- Server is the boss of the codebook, hints, coins and unlocks. Hints and packs are atomic and idempotent (unique constraint
  on (player, letter)); two simultaneous requests must not charge twice. Additive migrations, listed in ci.yml.
- Content pool: ~30 nights first, written in the house voice (cold, short, detective; recurring informant «مخبر شب»,
  a small story over each week, last night of the week pays it off). Every text must carry a clue, a jab or a small twist;
  neutral example sentences are rejected. Validation script: only allowed letters, length per level, no duplicates, no bad words.
- Wording: «کارآگاه», «مظنون»; no «ایمن»/«رمزنگاری‌شده» claims. Not in store texts as AI.
- Friend-to-friend telegrams are NOT part of this task (see `docs/ideas-later.md`).
