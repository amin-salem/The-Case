# Weekend case, format 2 (14 Oct 2026)

Used by every new weekend case (`"format": 2` in `server/app/content/weekly/wNNN.json`). Old files (w001) without
`format` keep the old rules (suspect + proof card + motive). Read `docs/case-writing-rules.md` first: all its rules apply.

## Timing
- New default: opens **Wednesday 21:00**, closes **Friday 21:00 Tehran** (48 h): `"open_hour": 21` (default),
  `"closes_hours": 48` (default), `publish` = that Wednesday.
- **Two chapters**: `"chapters"` with `at_hours` **0** and **24** (Wednesday 21:00, Thursday 21:00). Chapter 1 has no
  `evidence` list (its cards are the ones not listed in any later chapter); chapter 2 lists the evidence ids that appear later.
- One-off: w002 (14-15 Oct) opens Thursday 09:00 (`open_hour: 9`), chapter 2 Friday 09:00, `closes_hours: 48` (Saturday 09:00).

## Players can accuse from chapter 1
- Right culprit and right why/how before chapter 2 opens: **3 stars + early bonus** (`economy.WEEKLY_EARLY_BONUS`, 50 coins).
- Right culprit, wrong why/how: solved with **at most 2 stars**, no early bonus. Wrong culprit: a try is lost (3 tries), the case stays open.
- So the case must be solvable by a very careful player from chapter 1 + the shows, and *clearly* provable with chapter 2.

## Fields to write
```json
{
  "format": 2,
  "chapters": [{"title": "...", "at_hours": 0}, {"title": "...", "at_hours": 24, "text": "...", "evidence": ["e8", "e9"]}],
  "motives": [{"id": "m1", "text": "برای پنهان‌کردن ... با ... وارد شد"}, {"id": "m2", "text": "..."}, {"id": "m3", "text": "..."}],
  "suspects": [{"id": "s1", "...": "as before", "reactions": {"e1": "what s1 says when shown card e1", "e14": "..."}}],
  "solution": {"culprit": "s7", "motive": "m2", "proof": ["e14", "e15"], "explanation": "..."}
}
```
- `motives` = the **«چرا و چطور؟»** options the player picks in the accusation (3 or 4, one right: `solution.motive`). Word each as
  motive + method in one sentence; the most likely-looking option must be wrong.
- `suspects[].reactions`: a dict `evidence id -> text` (what the suspect says when the player SHOWS that card). Spoken Persian, no
  quotes (the app adds «»). Every suspect needs a `reactions` dict (at least one card). A card without a reaction gets the neutral
  line «اینو دیدم، ولی چیزی برای گفتن ندارم.». Write reactions for the cards that matter: most are neutral or an honest
  explanation; **the culprit and the liars slip in a checkable way** (a time, a place, a detail that contradicts their statement
  or another card), never "I confess". The culprit must react to **at least one `solution.proof` card** (the validator checks it).
- Reactions are never sent with the public case; the server returns one only when the player shows the card (limited:
  `economy.WEEKEND_SHOWS_PER_CHAPTER` = 3 per opened chapter, so 3 in chapter 1 and 6 in total from chapter 2). Showing a
  card the suspect already saw is free (it repeats the answer).
- `solution.proof` stays the list of cards that prove the answer (used for the explanation screen, not asked in the accusation).
- Validation: `content.validate_weekly` (format 2 checks reactions, ids and the culprit/proof rule).

## Archive
After closing, a weekend case is an archive case: `economy.WEEKEND_ARCHIVE_COST` (250 coins), both chapters open, normal
archive rewards (`SOLVE_REWARD`, no weekend bonus, no early bonus). A player who solved it live keeps it free.
