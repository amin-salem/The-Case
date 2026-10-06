# Case-writing rules for «پرونده» (every game mode)

These rules apply to every case written or rewritten from now on: nightly cases
(`server/app/content/cases/cNNN.json`), weekend cases (`server/app/content/weekly/wNNN.json`) and the
future big 7-day cases. Every scheduled writing run reads this file first. The owner's verdict: easy cases
make people think the app is not good; **there must be no easy case.**

## 1. Difficulty
- Every case is difficulty **4 or 5**. Nightly cases are mostly 4, with some 5; weekend and big cases are 5.
- No card gives the answer on its own. The culprit is only proven by **combining at least two cards**,
  usually three. The weekend and big cases need three to four.
- Every suspect looks guilty for a while. There are at least **two strong false trails** that each look like
  the full answer until a later or combined clue clears them.
- Never let the culprit's own statement be the only thing that is "off". Innocent suspects lie too, about
  something else (see 3).

## 2. Puzzle types: vary them
Each case is built around one main type. Two cases in a row never share a main type, and none of the
types is used more than twice in any ten cases. Log each case's type in `docs/case-log.md`.
1. **Guilty knowledge**: someone knows a detail they could only know if they did it.
2. **Hidden relationship**: two suspects who pretend not to know each other (a shared past, debt, family).
3. **Not what it seemed**: the crime is different from what everyone assumes (a theft that is cover for
   something else, an accident that wasn't, a "victim" who staged it).
4. **Wrong victim**: the target was someone else.
5. **Time trick**: a clock, time zone, recording, photo or habit that fakes a timeline.
6. **Staged scene**: the scene was arranged after the fact; the arrangement gives it away.
7. **Two people, one plan**: an accomplice; each one's alibi covers the other's gap.
8. **The witness is the liar**: the most helpful person is the one who did it.
9. **Object biography**: following one object (a key, a cup, a coat) through many hands.
10. **Motive inversion**: the obvious motive is false; the real motive only appears late.

## 3. People first, logs second
- At most **two** "machine" cards per nightly case (key-card logs, sensors, scales, phone records, CCTV).
  The rest of the clues come from people: what they say, carry, wear, know, avoid, and how they talk
  about each other.
- Every suspect has a **short past** (one or two lines in the statement or answers), **ties** to at least
  one other suspect, and **a secret that isn't the crime** (an affair, a debt, a small theft, a lie
  about where they were for an unrelated reason). Innocent suspects lie to protect that secret, and a
  clue explains each such lie, so the player can tell "lying about something" from "lying about the crime".
- Suspects talk about each other in their answers (who saw whom, who dislikes whom). Cross-checking
  statements should be part of solving.

## 4. The motive is discovered, not handed over
- The suspect field `motive` (shown as «انگیزه‌ی احتمالی») holds only what **everyone believes** about that
  person: a surface motive. For the culprit it may be misleading or weak.
- The real motive is found in the evidence (a document, an answer, a relationship). The explanation says
  how.

## 5. Persian
- Statements and answers are **spoken Persian** (محاوره): short sentences, natural words, a little
  personality (one is curt, one talks too much, one is formal). Avoid translated-sounding phrases.
- Intro, evidence and explanation are clean written Persian, concrete and vivid, with no filler.
- Every suspect sounds different. Read the answers aloud in your head: could you tell who is talking?

## 6. Fair play
- Every fact needed to solve is in the cards, statements or answers. No last-minute surprises in the
  explanation.
- Check every timeline twice (who was where, minute by minute), every count, every key and door.
- `solution.proof` lists only cards that **directly contradict the culprit's own statement or answers**.
  It must not be more than half the evidence.
- The 3 hints get progressively stronger: hint 1 points to the right area, hint 2 to the combination,
  hint 3 nearly names the contradiction (without naming the culprit).
- The explanation walks through the combination step by step, and also says why each false trail was
  false.

## 7. Blind test (required for every case)
Before a case is accepted, give a separate helper (the Agent tool, one at a time, never in parallel) only
the **public** case: the JSON without `hints` and `solution`. Ask it to solve: who, which proof card, and
why. Then judge:
- **Too easy**: it names the culprit from one card, or within a few seconds of reasoning. Make it harder
  (hide the giveaway behind a combination, strengthen a false trail).
- **Unfair**: it can't reach the answer, or reaches a different answer that is also consistent with the
  cards. Fix the missing or ambiguous fact.
- Repeat until it solves the case only through the intended combination. Note the result in
  `docs/case-log.md`.

## 8. Format and content rules (unchanged)
- Keep the JSON schema of the file you edit. For a rewrite, keep `id`, `number`, `publish` and `scene`.
  Nightly cases have 5 suspects (6 at most); weekend cases have 8.
- Vary the culprit's slot (s1–s5) across cases.
- Every suspect's `avatar` has a `portrait` from `app/assets/portraits/*.webp` (file name without
  `.webp`) that fits gender, age and job; no repeated portrait inside a case (twins may share).
  Women always have `"hair": "hijab"`.
- Fictional people and places only; no real religious or political places or figures; nothing gory.
- At least 5 evidence cards (nightly cases usually 7–9; weekend cases about 16, in chapters).
- After editing, run the content checks (JSON loads, `server/app/content.py` validation); CI must be green.
