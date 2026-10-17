# Case triage: which old nightly cases need work

Written 17 Oct 2026 (Sonnet, priority Important, asked by Amin 16 Oct). Read-only review: no case JSON was changed and no
blind test was run. Every case was read in full (intro, suspects, answers, evidence, hints, solution) and judged as a
player would, against `docs/case-writing-rules.md`.

**Scope:** c019 and c025–c050 (27 cases). c001–c008 are published and skipped; c009–c018 and c020–c024 were already
rewritten under the rules (see `docs/case-log.md`).

**How the nightly Opus task should use this file:** touch only rows marked **REWRITE** or **REPLACE**. Never touch **KEEP**
rows (a few have an optional one-line tweak listed under "Small notes on KEEP cases"; do those only if you have spare time and
they are marked optional). For both REWRITE and REPLACE keep `id`, `number`, `publish` and `scene` (rules section 8), run the
blind test (rules section 7), and add the case to `docs/case-log.md`.

## Verdicts

- **KEEP**: acceptable at difficulty 3–4 as it is.
- **REWRITE**: the idea is good, the structure is too easy (usually one card names the culprit, or the false trails are weak).
  Keep the premise and rebuild the clue structure.
- **REPLACE**: the idea is weak, a repeat, or the case is only logs plus one lie. A new case with a better idea takes the slot.

"Cards needed" is how many cards a player must combine to prove the culprit. "False trails" counts trails that look
convincing for a while (rules section 1), not suspects who are simply cleared by a camera.

## Table

| Case | Publish | Diff set | Cards needed | False trails | Type (rules §2) | Verdict | Reason |
|---|---|---|---|---|---|---|---|
| c019 «چمدان چهار کیلو سنگین‌تر» | 2026-10-17 | 3 | 1 (e5 contradicts her statement) | 0–1 | none: alibi break from logs | **REPLACE** | Fingerprint log vs one lie, five of eight cards are logs or cameras, nobody else lies, no people-first clues. |
| c025 «وصیت‌نامه‌ای با جوهر غلط» | 2026-10-23 | 4 | 1 (e4: receipt on Hossein's own card) | 1 (Zari, illiterate beneficiary) | 9 object (pen and ink) with forgery | **REWRITE** | Steady signature of a man with Parkinson's is a lovely clue, but the purchase receipt in the culprit's name names him at once. |
| c026 «برچسب‌های ساعت سه بامداد» | 2026-10-24 | 4 | 1 (e1 VPN account list vs «no VPN») | 1 (the owner, insurance raised) | none: digital trace (VPN, label reprint) | **REWRITE** | Good idea (labels reprinted at 03:12 to fool the audit) but every card is a log or list and the lie is contradicted flat out by the account list. |
| c027 «ساعت‌شمار موتور» | 2026-10-25 | 4 | 2 (e1+e6; the maths in e2/e8 is not needed) | 1 weak (Nader's 12 minutes) | 5 time trick (engine-hour meter) | **REWRITE** | Fresh maths idea, but only one boat's meter moves, so comparing two lists solves it; make two boats move and let the 63 km round trip decide. |
| c028 «پمپ انسولین ساعت سه» | 2026-10-26 | 4 | 1 (e2 smartwatch contradicts «asleep»; e3 only supports) | 0–1 | none: alibi break (smartwatch) | **REWRITE** | Strong setting (ICU, whistleblower surgeon) but the smartwatch card is a one-card giveaway and the other four are cleared by one log each. |
| c029 «برگه‌ی امانت شماره‌ی ۴۱۸» | 2026-10-27 | 4 | 3 (e1+e3+e8) | 2 (Dr Fazeli himself, Maryam's two short gaps) | 5 time trick (one-way stamp counter) | **KEEP** | Clever, fair, needs three cards combined (stamp counter only goes up); best structure in the batch. |
| c030 «تعویض سریع لباس» | 2026-10-28 | 4 | 1 (e1: backstage empty 21:08–21:17) | 0–1 | none: alibi break | **REWRITE** | Vivid theatre premise (quick-change window during Macbeth) but one camera card contradicts the dresser and all others are alibi logs. |
| c031 «شیشه‌ی شکسته به سمت باغ» | 2026-10-29 | 4 | 1 (e8 or e4 alone: bank slip, he said 2 bn) | 0–1 | 6 staged scene | **REPLACE** | Same «glass fell outside, faked break-in» clue as c013, and the insurance-raised motive already appears in c026; owner-did-it is guessed from the intro. |
| c032 «برنج سمی ساعت نه» | 2026-10-30 | 4 | elimination (4 cameras clear 4 people; nothing proves the waiter) | 0 | none: pure alibi elimination | **REPLACE** | The culprit is whoever has no camera; the «tablet silent for 9 minutes» is not a contradiction. Kitchen poison again after c012's kitchen. |
| c033 «کپه‌ی گونی در دودکش» | 2026-10-31 | 4 | 2 (e4+e7: moss only on the roof) | 3 (Behnam's soot, Nasser the heir, Dr Sarmadi the ex-wife) | trace evidence (nearest 9) | **KEEP** | Vivid snow lodge, real false trails (soot explained by the stove cleaning), moss is a good fair clue; the culprit's unprompted excuse is a mild tell, acceptable at 3–4. |
| c034 «سایه‌ی شتر» | 2026-11-01 | 4 | 2 (e5+e8; e7 is the reasoning) | 1 weak | 5 time trick (camera clock plus shadow) | **KEEP** | Fresh visual idea (shadow points west, so it was morning). Optional: e5 nearly gives it away, see notes. |
| c035 «کیف شش‌صد میلیونی» | 2026-11-02 | 4 | 1 (e4: bank slip says 600) | 1 weak (the finder's 12 minutes) | 3 not what it seemed (accuser lies) | **REWRITE** | The accuser is obviously the liar from the intro; one bank slip proves it. Keep the metro, make the money story deeper. |
| c036 «فلاسک HeLa-7» | 2026-11-03 | 4 | 1 (e7 plus his own slip in the statement) | 2 (Ghaffari and Heidari also opened the incubator) | 1 guilty knowledge | **REWRITE** | Guilty-knowledge slip is blatant (he says «HeLa-7» in his first statement). Move the slip into an answer and give innocents a second source for the flask name. |
| c037 «پسرعموی ناشناس» | 2026-11-04 | 4 | 1 (e5 family record vs his own statement) | 0–1 | none: impostor (inverse of 2) | **REPLACE** | Wedding with stolen gift envelopes repeats c017 almost exactly; the title and the intro give away the stranger. |
| c038 «نمره‌ی بیست» | 2026-11-05 | 3 | 2 (e2+e3, e6 repeats it) | 1 weak (the deputy's login) | none: digital trace (Wi-Fi MAC) | **REPLACE** | The student who benefits is the obvious culprit; the whole case is Wi-Fi logs. Weakest idea at difficulty 3. |
| c039 «شاهد مهربان» | 2026-11-06 | 4 | 1 (e3: he entered at 21:42) | 0–1 | 8 the witness is the liar | **REWRITE** | Good type but the entry-time card alone exposes him, and e8/e3 clash (he steals at 21:26 yet enters at 21:42), so the timeline needs rebuilding. Airport again (c019). |
| c040 «ناقوس کلیسای قدیمی جلفا» | 2026-11-07 | 5 | 1 decisive (e7) plus 5 alibi cards | 2 (Khosravi's cinema lie hides an affair, Gharibian had the code) | none: alibi break with an innocent's secret lie | **KEEP** | Best use of rule 3 (the innocent lies for a private reason and a clue explains it); six suspects, vivid. Honest difficulty is 4, set it to 4. |
| c041 «گواهی رج‌شمار» | 2026-11-08 | 4 | 1 (e1 invoice with his signature; e7 is close to a confession) | 0–1 | forged document | **REPLACE** | Third forged-document case in three weeks (c025, c029, c044 too); the invoice and the text message each name him. |
| c042 «ساعتِ ایمیل» | 2026-11-09 | 4 | 3 (e7 converted to Tehran time + e8 + e4) | 2 (Behzad alone in the office, Hamed who installed the VPN) | 5 time trick (UTC email header) | **KEEP** | Fresh and fair: reading the header in UTC flips the suspect and the VPN log flips it back. Log-heavy but acceptable. |
| c043 «واگن رستورانی که نبود» | 2026-11-10 | 4 | 1 (e4: no dining car before Qom) | 0 (only the culprit lies) | 5 time trick (timetable alibi) | **REPLACE** | Same train, same timetable alibi as c023 «کوپه‌ی شماره‌ی هفت» (21 Oct); innocents never lie, one card solves it. |
| c044 «رسید روز جمعه» | 2026-11-11 | 4 | 1 (e2: Saturday entry log) | 0–1 | 5 time trick (calendar) with forged receipt | **REPLACE** | The intro already states the Friday trick, so the player starts with the answer; fourth forged-document case in the batch. |
| c045 «سگی که پارس نکرد» | 2026-11-12 | 4 | 1 (e5 or e7 alone) | 1 weak (nothing else) | 9 object (kebab) with 1 | **REWRITE** | The sedated guard dog is a great idea, but the gambling nephew is the obvious culprit and his own receipt is in his pocket. |
| c046 «بیست پالت، بیست‌وشش بار» | 2026-11-13 | 4 | 1 (e2: 26 lifts; he is the only forklift driver) | 0 | none: counting | **REPLACE** | Only one person could operate the forklift, so there is nothing to deduce; same counting trick as c027. |
| c047 «شمع روی قفسه» | 2026-11-14 | 4 | 2–3 (door-card log e6 or camera e8, plus candle maths) | 1 (Dr Aria, Jafari) | 5 time trick (candle burn rate) | **KEEP** | Fair twist (attendance card is not the door card) and the candle arithmetic is fun. Log-heavy but fine at 3–4. |
| c048 «کلید شماره‌ی دو» | 2026-11-15 | 5 | 3 (e1+e2+e6) | 3 (maid asleep in room, repairman's smoke break, rival guest) | none: alibi break with innocents' side lies | **KEEP** | Designed on rule 3: several staff lie for private reasons and the intro says so. Honest difficulty is 4. |
| c049 «پنج نفر، یک راست‌گو» | 2026-11-16 | 5 | 1 logic argument (the cards add nothing) | 4 (every other captain is a valid wrong answer until the logic is done) | none: logic puzzle | **KEEP** | Different genre, fair and unique solution, a welcome change of pace. Story is thin, so do not add more of these. |
| c050 «ترتیب ورود» | 2026-11-17 | 5 | 2 (e3+e5 plus the ordering logic) | 2 (Zarin's threat, Arman's debt) | none: logic ordering puzzle | **KEEP** | Nobody lies, solved by ordering the arrivals from true statements. One fair-play fix noted below. |

## Summary

| Verdict | Count | Cases |
|---|---|---|
| KEEP | 9 | c029, c033, c034, c040, c042, c047, c048, c049, c050 |
| REWRITE | 9 | c025, c026, c027, c028, c030, c035, c036, c039, c045 |
| REPLACE | 9 | c019, c031, c032, c037, c038, c041, c043, c044, c046 |

So 18 of 27 need work (two thirds). Findings that explain why:

- **Most cases are «one card + one lie».** In 16 of the 27, one card on its own contradicts the culprit's statement. The
  innocent suspects almost never lie about anything (rules sections 1 and 3). Only c040, c048 and c033 do it properly.
- **«Time trick» is used far too often.** c027, c029, c034, c042, c043, c044 and c047 all run on a clock, timetable or
  meter (rules section 2 allows at most two of one type in ten). Avoid type 5 for every new or rewritten case below until
  the other types are caught up.
- **Forged documents cluster.** c025, c029, c041, c044 (will, stamp, certificate, receipt) are four forgeries in 20 days.
- **Settings repeat.** Airport (c019, c039), harbor (c027, c049), villa in rain (c025, c045, c050), train (c023, c043),
  wedding (c017, c037), library (c029, c047). The scene is fixed by the slot, so vary the *crime* instead.
- **Log-heavy.** Many cases are camera, access-log and ledger cards (rules section 3: at most two machine cards).
- **Culprit slots** are reasonably spread (s5 ×7, s1 ×6, s4 ×5, s3 ×5, s2 ×4). When replacing, favour s2 and s3.
- **Difficulty labels are generous.** c040 and c048 are marked 5 but play at 4; c038 at 3 is the weakest idea.

## Suggested order (by publish date, earliest first)

Only cases that need work. The nightly task takes them in this order:

1. **c019** (17 Oct, REPLACE) – note: it opens today, so a replacement will mostly reach archive players.
2. **c025** (23 Oct, REWRITE)
3. **c026** (24 Oct, REWRITE)
4. **c027** (25 Oct, REWRITE)
5. **c028** (26 Oct, REWRITE)
6. **c030** (28 Oct, REWRITE)
7. **c031** (29 Oct, REPLACE)
8. **c032** (30 Oct, REPLACE)
9. **c035** (2 Nov, REWRITE)
10. **c036** (3 Nov, REWRITE)
11. **c037** (4 Nov, REPLACE)
12. **c038** (5 Nov, REPLACE)
13. **c039** (6 Nov, REWRITE)
14. **c041** (8 Nov, REPLACE)
15. **c043** (10 Nov, REPLACE)
16. **c044** (11 Nov, REPLACE)
17. **c045** (12 Nov, REWRITE)
18. **c046** (13 Nov, REPLACE)

Follow the date order: each case opens on its publish date, so the earliest ones are the most urgent. If only a few nights
can be done, prefer the REPLACE rows inside the next week (c019, c031, c032) because they are weaker from the start.

## Seeds for REPLACE cases (one line each; keep id, number, publish, scene)

- **c019 airport:** type 4 wrong victim. Someone swapped baggage tags with the intended courier in the check-in queue, so the +4 kg
  went into an innocent passenger's bag; the tag, not the owner, was the target. An innocent baggage handler lies about a lost glove.
- **c031 hotel (Yazd):** type 10 motive inversion. The «burglar» took the hotel's second cash book (proof of unpaid tax), not
  the money; the cash left behind makes it look like an interrupted burglary. Different clue from c013's glass.
- **c032 kitchen (Tabriz):** type 7 two people, one plan. The cook and a waiter each cover the other's gap at the pass, and the
  order-ticket rail, not cameras, shows the gap. Poison in the sauce, not the rice.
- **c037 wedding (Ahvaz):** type 2 hidden relationship. The hall manager and the DJ are siblings who pretend not to know each other;
  their shifts cover each other's gap. The missing item is the bride's gold set from the dressing room, not gift envelopes (c017).
- **c038 school (Shiraz):** type 6 staged scene. The «grade hack» was arranged to frame the maths teacher, and the arrangement (a
  pen colour, a roster, a lie about a sick day) gives the deputy away; the pupil is only a pawn who benefits.
- **c041 bazaar (Tehran):** type 9 object biography. Follow the carpet itself through five hands (dyer, washer, repairer, trader):
  the fake was swapped in at one of them; the certificate is genuine.
- **c043 train:** type 3 not what it seemed. The necklace is a decoy; the thief wanted a letter or a ticket in the same compartment,
  and the one passenger who never mentions the necklace is the one who knew. No timetable alibi (c023).
- **c044 museum:** type 10 motive inversion. The vase was swapped to save the museum from an audit, not for money; the swap was
  made by an insider, and the restorer is a victim who is blamed. No forged date or receipt.
- **c046 warehouse (Karaj):** type 8 the witness is the liar. The most helpful clerk is the one who loaded the extra pallets after the
  count; the scale and the forklift sensor are only two of nine cards, the rest are people.

## Directions for REWRITE cases (keep the premise, change the structure)

- **c025:** keep the steady signature and the Parkinson's. Hide the purchase: the pen came as a gift or was bought by someone
  else, so Hossein is found through the driver's mileage book and a lie by the secretary about the pen.
- **c026:** keep the 03:12 reprint. Replace list cards with people: a colleague lent his login, the VPN owner is not the one at
  the keyboard, and an innocent lies about being at the warehouse.
- **c027:** let two boats' meters rise (one 4.6 h, one 4.3 h with a legitimate reason) so the player has to do the maths.
- **c028:** keep the ICU; the smartwatch is wrong (she left it on a charger), and a second nurse also left the ward.
- **c030:** keep the quick-change window; add a second person who also left the wings and a prop that proves who opened the safe.
- **c035:** the money was real but part of it was already paid out; the finder's gap and the café are the true trail.
- **c036:** move the slip into an answer; Ghaffari and Heidari also know the flask name from different sources.
- **c039:** rebuild the timeline so the witness is exposed by two combined cards and the cleaner has a side secret.
- **c045:** keep the silent dog; make the nephew a trail, not the answer. The real culprit is someone the dog trusts and who fed it.

## Small notes on KEEP cases (optional, only if time is left; do not rewrite)

- **c034:** e5 (clock changed manually) nearly gives it away. Optional: drop the old time «۰۷:۳۰» so the shadow carries the proof.
- **c040, c048:** set `difficulty` to 4 (they play at 4).
- **c050:** fair-play hole: colchicine acts about an hour after drinking, so the pleasant «Kazem tasted it at 20:35 and was fine»
  proves nothing and Kazem should also fall ill. Optional: make the poison fast-acting or let Kazem only smell it.
