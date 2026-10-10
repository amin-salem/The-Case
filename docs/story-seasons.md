# Story seasons roadmap (original stories in the spirit of famous ones)

Rule: we borrow the *shape* (a structure, a mood, a kind of puzzle), never the plot, characters, names, settings or the famous twist.
Everything is rebuilt in contemporary Iran with our own cast. Partner: سرگرد ناصری. Each season = 10 chapters, each solvable alone, threads add up to a season answer.
Season 1 «کبریت سوخته» is already announced. These are next, in the suggested order.

| Season | Inspired by (shape only) | Our original premise | Season mechanic |
|---|---|---|---|
| S2 «هفت مثل» | Se7en: a series of themed crimes and a detective who sees the pattern | Seven crimes, each staged like a Persian proverb (مثل); the proverbs are not the killer's "sins" but one family's forgotten promises | The pattern is a puzzle the player solves across chapters: guess the next proverb to predict the next scene |
| S3 «همسر گمشده‌ی ساعت‌ساز» | Gone Girl: a missing spouse, two conflicting accounts, the public story vs. the truth | A missing husband, told through his notebook and her messages; each chapter flips who the reader trusts | Unreliable narration: every chapter has two versions of one night and the player finds the lie |
| S4 «شب آخر کشتی» | Christie's closed-circle mysteries | Twelve passengers on a night ferry that cannot dock; fictional Gulf island, a locked-circle puzzle with an honest alibi grid | Each chapter removes one suspect from the deck and adds one new fact |
| S5 «کد زودیاک نه» | Cipher-hunting cases (Zodiac, Dan Brown style) | Letters to a newspaper in a cipher based on Persian calligraphy; no real cipher is reused | Chapter puzzles include a real small cipher the player can decode |
| S6 «پنجره‌ی رو‌به‌رو» | Rear Window: crime seen from a window | The player watches one apartment block across a courtyard in one night, clue by clue | Timeline puzzle: when each window light went on |

Guardrails for every season: no famous character names or catchphrases, no famous twist copied (the culprit logic, the reveal and the motive are new), no real places/brands, nothing gory, women with hijab, fair-play proofs per docs/case-writing-rules.md.


## Chapter file format (built 10 Oct)
`server/app/content/story/s01/ch01.json` ... `chNN.json`, numbered 1..N without gaps. It is a normal case file
(docs/case-writing-rules.md, validated like the nightly cases) with these differences and extra fields:
- `id` is `s01ch01` (season and chapter, two digits each), `number` = chapter, plus `season` and `chapter` (ints).
  `publish` is not needed. `difficulty` 5.
- `partner_intro`: ناصری's spoken-Persian intro, shown before the chapter. `partner_outro_win` / `partner_outro_lose`:
  his reaction after the accusation. `thread`: one line, the small clue of the season mystery this chapter leaves
  (shown after the chapter is finished, so it may mention what was solved).
- Optional `partner_hints`: three hint texts in ناصری's voice; if present they replace `hints`.
- Story mode opens for players only when the opening time (`STORY_SEASON.opens_at`) has passed and at least one
  chapter file exists. A chapter file that fails validation stops the server from starting, like other cases.
