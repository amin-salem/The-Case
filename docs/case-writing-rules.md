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
- **The culprit's portrait is unique across ALL cases** (Amin, 25 Oct 2026: the culprit album must not show the same face
  twice). Before you choose the culprit's portrait, list the culprit portraits already used in `cases/` and `weekly/` and take
  one that no culprit uses yet, of the right gender, close in age and job. Only when every portrait of that gender is already a
  culprit's may you reuse one, and then say so in the case log (the real fix is to ask Amin for new faces: need roughly one new
  portrait per new case of that gender; today men are short: 38 male culprits vs 26 male faces).
  To keep the face from betraying the culprit: the OTHER suspects take any portrait of the pool (a face that was a culprit's
  elsewhere is fine), chosen without looking at who is guilty, never the culprit's face, never repeated inside the case.
  Never reserve "special" faces for culprits and never give innocent suspects only the faces that already were culprits.
  A culprit whose `portrait` is not a shipped file is drawn by code and counts as unique.
- `server/tests/test_content.py::test_culprit_portraits_are_unique` enforces the culprit rule while unused faces exist.
- **Only faces the players have** (Amin, 9 Nov 2026; relaxed 18 Nov 2026): a portrait in `docs/portrait-release.json` needs `first_build` and `usable_from` filled (they are, for every shipped face; the owner raised the minimum app version to build 99). The old date check is gone: any shipped face may be used by any case (test `test_case_uses_only_portraits_players_have`).
- **Spread the faces** (Amin, 18 Nov 2026: "no repeated faces, it is annoying"): the same face must not keep coming back. Before choosing portraits run `python3 tools/portrait_pool.py <gender> <age> "<role>"` (lists compatible faces, least used first) and take the least-used one; never take a face that already appears in 3 or more cases when a less used one fits. Avoid reusing a face in the previous 15 cases. Take the culprit from faces no culprit has. 18 Nov 2026 state: 194 faces for ~470 suspect slots (each face used 1-4 times, the most before was 16). The real fix is more faces: ask Amin for new neutral portraits when the least-used compatible face is already used twice.
- Every suspect needs an `intro` (required; 20–90 characters, spoken-friendly Persian, one line). It is shown on the
  case's «آدم‌های پرونده» strip and on the portrait chips, **before** the player has read any statement, so it says only
  WHO the person is relative to the case: role, relationship to the victim/place, what they were doing there at a
  neutral level («حسابدار طلافروشی زرین؛ حساب‌وکتاب مغازه دست اونه.»). HARD RULES: never mention motive, alibi, a lie, a
  secret, money trouble, suspicious behaviour, or anything that helps decide guilt; nothing that only the statements
  or evidence reveal later; do not contradict `role`, `name`, `age` or `statement`; same vocabulary level as the
  case. If you cannot write a neutral line, use "role + relation" only. Server validation refuses a suspect without it.
- Fictional people and places only; no real religious or political places or figures; nothing gory.
- At least 5 evidence cards (nightly cases usually 7–9; weekend cases about 16, in chapters).
- After editing, run the content checks (JSON loads, `server/app/content.py` validation); CI must be green.

## 9. Category (every case, from 18 Oct 2026)
Every new case sets `"category"` (next to `scene`) with the topic it is really about. Choose it from the intro, the suspects
and the solution, not from the title. The server refuses an unknown key; a missing one is tolerated only for old files.
- `medical` پزشکی: hospital, patient, medicine, a doctor or nurse at the centre.
- `art` هنر و صحنه: museum, theatre, art, antiques, manuscripts, crafts and restoration.
- `family` خانواده و ارث: inheritance, wills, a family secret, relatives who gain or lose.
- `business` تجارت و پول: shops, companies, stock, accounts, contracts, trade fraud.
- `science` علم و پژوهش: labs, universities, research, archaeology.
- `travel` سفر و مهمانی: trains, hotels, airports, tours, weddings and parties, mountain lodges.
- `crime` جرم و قانون: smuggling, customs, arson/insurance, exam leaks, police-and-court matters.
Spread new cases across the categories (the filter chips in the archive show the mix); the app draws the icon and name itself.

## Notification teaser (every nightly case and every weekend case)
Every case needs an entry in `server/app/content/notify.json`: `{"<case id>": {"title": "<the case's exact title>", "head": "...", "body": "..."}}`.
- `head` is the notification title (max ~35 characters, may end with one emoji) and must be different from every other case's head; `body` is one or two spoken-Persian sentences (max ~90 characters).
- It must tease the situation from the case's intro (place, time, object, the central question) without revealing the culprit, motive, or any proof, and without inventing facts that are not in the case.
- When a case is rewritten or its title changes, update its entry (the app falls back to an automatic text while the title does not match). A server test checks that every nightly case has an entry with a unique head.

## 9. Review of every case Gemini (or anyone else) wrote (Amin, 19 Oct 2026)
A case written by Gemini is not imported as it is. Before the blind test, Claude rewrites it into the house voice (the style of
c020-c024) and checks every item below. Findings are FIXED in the file, never only logged.
- **Voice.** Statements and answers are spoken Persian with a personality each (curt, chatty, formal), short sentences, no
  written-style «می‌باشد/لذا». Suspects mention each other. Evidence cards are concrete, with times, numbers, names; no vague
  «افراد مختلفی», «کارکنان گفتند» without a named source.
- **One truth.** Write the true timeline first (who, where, minute by minute). Every card, answer and the explanation must agree with
  it. Check: clock offsets (a «5 minutes fast» clock must show the right real time), counts, keys, doors, directions and distances
  (28 km east + 30 km west = 58 km), room names (archive room vs management room), days of the week.
- **Every sentence of the explanation points to a card the player has.** No fact appears only in the explanation or only in a
  suspect's «story» (no «petty cash settled» unless a card or answer says it). Every alibi used to clear someone has a card.
- **Questions match statements.** A question never presumes something the suspect did not say (no «why did you say you did not
  see it?» if they did not). Reactions are keyed to the right card id and answer what that card actually says.
- **The culprit's lie is testable.** His own statement is contradicted by at least two cards that the player can combine. «I do not
  have much schooling» is not a lie; «the notebook is filled in by Mahnaz» is.
- **The trick must matter.** If a clock/time trick is the point, the case must be unsolvable or wrong without it (at the naive time
  everybody has an alibi; at the real time only the culprit is free). Blind-test it.
- **Motives.** The `motive` field is only what everybody believes (a surface motive, never exculpatory). The real motive is in a card.
- **Names and polish.** No repeated first name inside one case; no leftover names from other cases in the same week; ZWNJ only where
  needed (no «جا‌لیوانی»); proof ≤ half the cards and every proof card contradicts the culprit's own words.
- **Difficulty is measured, not claimed.** Blind test the public file; below 3.5 → harden (a second strong false trail, no
  card that names him) and test again. Weekend cases: a chapter-1-only run and a full run.

## 10. Data for the detective tools (optional, from 20 Oct 2026)
The tools «ذره‌بین» and «دوربین مخفی» only appear on a case whose file carries the data below. Add it when a case has a
natural place for it; never force it. The server refuses a file that breaks these rules (`content._validate_tool_data`).
- `solution.irrelevant`: 1 or 2 evidence ids that are truly **not needed** for the solution: not in `proof`, not used to clear a
  false trail, not cited by id in the explanation. The magnifier tells the player «this card is irrelevant», so a wrong entry
  would send a player away from a card he needs. If every card matters (the house rule for new cases), leave it out.
- `suspect.camera`: one line (or up to 3), 20-160 characters, a **neutral observation** about the person's behaviour or a small
  fact («چند بار به ساعت مچی‌اش نگاه کرد»). It names no guilt, no motive, no lie, and does not repeat a statement or an answer.
  It must not make the culprit stand out compared with the others (give every suspect with a camera line a line of the same weight).
- The fingerprint reader shows `suspect.print` (a string or 1-3 lines, 20-160 chars): a small physical trace the suspect left on some object (print, fibre, smudge, wear) that NO card shows. Same rules as camera: innocent-looking and explainable for everybody (culprit included), equal tone and length across suspects, never proof or exclusion by itself, never a new event, not a repeat of a card or of the camera line. A case without `print` simply does not offer the tool.

### 10b. Tool lines must be worth the coins (Amin, 25 Oct 2026; replaces the "neutral" wording above where they differ)
Players said the tools were «بی‌فایده بود و چیزی نگفت». A line that tells the player nothing is a coin wasted, and a player who
got «nothing» once stops buying anything. From now on every `camera` and `print` line is a **useful, true fact**:
- **One checkable fact, no filler.** `camera` = what was SEEN (a sighting with a time and a place, who was with whom, who carried
  what in or out: «ساعت ۲۱:۴۰ جلوی آسانسور دیده شد، یه کیف دستش بود»). `print` = what was TOUCHED or left (which named object a
  suspect handled, or a trace on it, and roughly when). The two never repeat each other, a card or an answer.
- **It must move the player's thinking.** After reading it the player can confirm a statement, weaken a statement, close an
  alibi window or open a new question, and then combine it with cards. If the line would not change what any reader believes
  about any statement, rewrite it.
- **Never decisive alone.** No line names the culprit, clears everybody else, or hands over the decisive trick of the case. The
  solution must still need the card combination. Tool facts are extra help, never required for fair play.
- **One truth.** Add every line to the true timeline (rules §9, step 1) and check it against every card, answer and the
  explanation before accepting it. A line that contradicts anything, or adds an event the story does not have, is an error.
- **Equal weight and tone.** Every suspect gets a fact of the same kind and about the same length. The culprit's line must be a
  true fact that looks as informative as the others (for example his real whereabouts, which fit his statement on the surface and
  fail only in combination). A dull line for the culprit gives him away by elimination.
- **Spoken, short Persian**, 20-160 characters (the server limit), no accusation words, no motive.
- **Written in the same pass as the case**, never added afterwards. The blind-test reader also gets the tool lines and must report
  (1) whether any single line decides the case, (2) whether each line told him something useful. Either answer "yes decides" or
  "told me nothing" means rewrite and test again.
