# Weekend case, format 2 (14 Oct 2026)

Used by every new weekend case (`"format": 2` in `server/app/content/weekly/wNNN.json`). Old files (w001) without
`format` keep the old rules (suspect + proof card + motive). Read `docs/case-writing-rules.md` first: all its rules apply.

## Timing
- Default since 18 Oct 2026: opens **Thursday 09:00**, closes **Friday 21:00 Tehran** (36 h): `content.WEEKEND_OPEN_WEEKDAY` 3,
  `WEEKEND_OPEN_HOUR` 9, `WEEKLY_HOURS` 36 (the app text «هر هفته پنجشنبه صبح ساعت ۹ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.» comes from
  `weekend_schedule()`). `publish` = that Thursday. w001 keeps its old 48 h window through its own `closes_hours`; w002 sets its own.
- Older note: format-2 cases of 14 Oct opened Wednesday 21:00 for 48 h (`open_hour` 21, `closes_hours` 48 in the file).
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

# Format 3: two nights (18 Oct 2026)

Used by weekend cases w003 and later (`"format": 3`). Everything of format 2 applies (two-part accusation, `reactions`, `motives`,
shows per chapter) plus the rules below. The reason: with all suspects and cards in one pile there was no reason to play night 1.

## Timing
`open_hour` 9, `closes_hours` 36, chapters at `at_hours` **0** (Thursday 09:00, «شب اول») and **12** (Thursday 21:00, «شب دوم»).
Exactly two chapters; chapter 2 has `text` (a short update) and `evidence` (at least two new cards). Night 1 has at least four cards.

## Suspects: one newcomer
- `suspects[].appears_chapter`: `0` (default) = there from the start, `1` = appears with chapter 2.
- **Exactly one** suspect has `1` (the newcomer). The culprit is never the newcomer (a night-1 solve must be possible).
- Until chapter 2 opens the server leaves the newcomer out of the case file and refuses to accuse, question or show cards to them
  (`404 no_suspect`). The case file carries a `night2` teaser with counts only (`new_suspects`, `new_cards`, `opens_at`, `open`), no names.
- Each card in the file carries `chapter` (1 or 2) so the app marks the new ones «تازه · شب دوم».

## Night-1 question: «کی دروغ می‌گه؟»
```json
"night1": {"question": "کی دروغ می‌گه؟", "liar": "s3", "card": "e4", "explanation": "..."}
```
- `liar` is a night-1 suspect (not the culprit, not the newcomer) whose statement is contradicted by `card`, a night-1 card.
  Pick a lie that is *not* the crime (a secret), so it also clears a false trail.
- One try per player (`POST /v1/cases/{id}/liar {"suspect"}`), only while chapter 2 is closed. Right: `economy.WEEKEND_LIAR_REWARD` coins
  (10, small on purpose; coins are sold), once. The answer, the card and `explanation` come back in `progress.night1` (right or wrong).
  It never costs an accusation try and does not touch the main answer.
- `night1` is stripped from the public case (`content.SECRET_KEYS`); the file only carries `question`, `open`, `reward`.

## Early reward and plaque
Solving the whole case (who + how) before chapter 2 opens pays `WEEKLY_EARLY_BONUS` (80, was 50) on top of the weekend reward and earns the
plaque **«پلاک شب اول»** (achievement `weekend_night1`). The weekend screen shows this and a countdown to chapter 2, with a split
«شب اول / شب دوم» card. Solving on night 2 pays the normal reward.

## Validation
`content.validate_weekly` → `validate_format3`: two chapters, one newcomer, culprit not the newcomer, `night1` complete and consistent,
reactions for every suspect (the culprit reacts to a proof card). Tests: `server/tests/test_weekend_format3.py`.
