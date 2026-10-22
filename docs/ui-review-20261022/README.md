# ChatGPT UI proposal (22 Oct 2026), reference only

Extracted from `parvandeh-ui-preview.html` (embedded images removed). Interactive mockup with demo data, 37 screens.
- `body.html`: page shell. `style.css`: all styles (design tokens, home, cards, bottom nav). `script.js`: the screens (`home()`, `archive()`, `weekend()`, `leaderboard()`, `shop()` ...) and, in `definitions`, the author's before/after note per screen.
- It is a design reference, NOT code to ship. Known differences from the real game that must NOT be copied: shop prices (use the server/remote_config prices), 3 difficulty labels (the app has a 5-level bar), failed result showing the answer (a lost case stays closed, reopen costs 2x), missing weekend chapter badges, missing streak repair/frames.
