# Nightly c037–c039 — review handoff, 2026-10-21

Review branch: `content/rewrite-c037-c039`. Base: current remote main
`cdf625768f65ad9b16e38b08d089e6bdc0d23dac`, fetched afresh for this task.
This is content for owner/Claude review, **not publication approval**.

## Scope and compatibility

- Complete Persian rewrites of the three numbered Nightly cases, not the special-case,
  laboratory, co-op or Story prototypes.
- IDs, numbers, publish dates, scenes, categories, suspect IDs and every avatar/portrait
  object retained. All existing portrait assets are reused. Known evidence types only.
- c037 opens 2026-11-04, c038 2026-11-05, c039 2026-11-06, each at **21:00 Asia/Tehran**,
  unchanged under the existing publication rule. No new opening fields or clock offsets.
- Five suspects, nine evidence cards, three optional escalating hints per case.
  Difficulty is set to the requested **target 5**. **Blind-helper difficulty estimates
  were 3–4, not a validated 5**; see results below. Human difficulty calibration remains
  part of the requested owner/Claude review. Existing difficulty-based economy consumes
  that field; no economy code, tables, historical rewards or balances were changed.
- Maryam's descriptive age changes 50 → 57: the rewritten mother/daughter relationship
  with 38-year-old Nasrin otherwise implies childbirth at 12. The new gap is 19 years.
  Other changes to names, roles, location labels and teasers are narrative text.
- No Naseri, new mechanics, new images, schema/API changes, app UI changes or deployment.
- Only the three matching `notify.json` entries change. No other cases are rewritten.

## Actual accusation contract

The server accepts **one** evidence ID in `solution.proof` after the suspect is selected;
it does not require the whole narrative chain. These are alternative supported citation
cards, at most four of nine, not an ordered multi-evidence proof-chain feature.

| Case | Culprit | Accepted citation IDs | Main structure |
|---|---|---|---|
| c037 «بارِ آخرِ تالار» | s2, مریم داوودی | e1, e4, e5, e9 | 2 — hidden relationship; competing transport routes |
| c038 «شش نمره‌ی اضافه» | s1, داریوش مرادی | e1, e3, e4, e6 | 10 — motive inversion; anonymous-paper reconstruction |
| c039 «کیفِ کنار پنجره» | s5, بهمن زارعی | e1, e5, e6, e8 | 8 — helpful witness is the liar; pre-lounge substitution |

These main types are distinct and do not repeat adjacent types. The preceding ten-case
window does not acquire a third occurrence of any one of these types. Machine-derived
records are contained in c037 e1/e2 (weighing), c038 e1/e5 (pre-review images and system
receipt), and c039 e1/e5 (all scale readings and CCTV). c037 e8 is a factory specification
on a sale receipt, not another weighing event. Family photographs, letters, witness
accounts and signed human inventories do not substitute for unseen machine records.

## c037: route, provenance, then identity

- Gift box + envelopes: **900 + 3120 = 4020 g**.
- Scale rounds each reading to 100 g, maximum error 50 g. Both room loads have a
  displayed **4000 g** excess; each subtraction permits **3900–4100 g**.
  The **3980 g** sound device and **4020 g** gift box both fit. Exact-weight matching
  cannot distinguish them. Flowers' excess is 0 ±100 g, excluding the gift box.
- e8 independently accounts for room 18: earlier payment, matching device body number,
  actual witnessed contents. Debt and a concealed sale explain the three men's lies.
- e3 follows the cloth load to room 12. e4 reserves that room for Nasrin's mother;
  e5 establishes Maryam's motherhood and the surname change. Estrangement explains
  why prior telephone business did not make the family recognize the relationship.
- e9 finds cash, dismantled envelopes and the opened box under that guest's exclusive
  custody. e1 independently traces **50 × 100,000 = 5 million tomans** by complete
  prefix/serial range, س۱۲ / 5001–5050. The remaining 255 million is a cumulative
  inference from total, packaging, route and custody, not individually serial-traced.
- Order: gifts counted/tied before dinner → Maryam observed finishing the cloth load
  → Nasrin signs at the doorway → uninterrupted porter transport → sole room guest
  removes the rectangular object → room search. The box is on the room table at search;
  it is not simultaneously on the returned cart.
- Maryam's appropriation is established; nobody directly sees the initial insertion
  into the transport container. The solution does not claim that observation occurred.
  Nasrin's false alibi and concealed kinship do not prove knowing complicity. No
  unmentioned accomplice or authority to take the couple's gifts is assumed.
- The e7 account dispute explains the desire for money under Maryam's own control.
  It does not identify the unnamed loan holder or make the gifts her property.

## c038: the same increase must not identify its author

Actual submission order: Nora, Kasra, Yasman, Behzad, Armin, Dorsa, Soheil. Each paper
goes **on top** of the previous one; no turning/reordering. Number from the top:

| Code | Student | Valid result / request |
|---|---|---|
| 41 | سهیل | no request |
| 42 | درسا | no request |
| 43 | آرمین | real 12; fabricated +6, entered as 18 |
| 44 | بهزاد | 16; no request |
| 45 | یاسمن | real correction 10 → 16 |
| 46 | کسری | real correction 9 → 15 |
| 47 | نورا | no request |

- **All three requests are +6.** The coded system receipt contains increases only;
  it does not print a unique 12→18 row or student name that bypasses reconstruction.
- Rubric: six 2-point questions + two 3-point questions + 2 reasoning points = 20.
  Armin earned 12 and left the two final answers and margins blank. The independent
  observer's pre-review images and custody protect against later writing/erasure.
- e4 authenticates each writer, not the truth of the alleged answers. Carbon and
  sealed-envelope continuity exclude a substituted request or an entry clerk's typo.
- Moradi's specific innocent-error defense fails on both possible papers: code 43
  is Armin, with no answers; seat row three is Yasman, with total 10 and answers on
  the back, not the claimed front margin of a paper totaling 12.
- Genuine corrections bring Kasra to 15 and leave Behzad at 16. Only Armin's actual
  12 triggers the class-fee refund; Moradi's withdrawn share must fund it. The separate
  scholarship threshold is above 10, unchanged within the fictional contract.
- The grandfather's accommodation, Rasti's bedding, and Rahimi/Armin's unreported
  fourth lesson explain the other lies. Three school sessions plus one direct-paid
  extra session are now consistent. Shared login possession is not identity proof.

## c039: distinguish the weight bound from contents continuity

- Human manifest e2 maps scale labels **الف/ب** to the two suitcases and **پ** to
  the handbag. The helper's own tote is explicitly excluded from the weighed cart.
- Bag at entry: **27800 − 13100 − 8200 − 4800 = 1700 g**. Four readings, each ±50 g,
  give **1500–1900 g**, not ±50 g or ±100 g.
- 5000 notes, from 100-note sample 100 ±5 g: notes alone **4750–5250 g**; adding
  the shell's conservative 650 g lower bound gives at least **5400 g**, incompatible
  with entry (the recovered shell reading is 700 g).
- This bound alone proves substantial loss, **not the time of the final missing note**.
  Equal entry/recovery mass also does not prove equal contents. Full loss before
  entry is established separately: e3's only zipped compartment, e5's continuous
  closed-zip/no-bag-swap observation after weighing, and no cash at recovery.
- Order: courier's independent count and receipt → watched handoff at changing rooms
  → orange-card holder alone in room two for 80 seconds → closed return under continuous
  observation → weighing → lounge table → cleaner's cart → property shelf → opening.
  Mansouri remains behind the closed first-room door during the private interval.
- e5 continuously links the orange-card carrier from section entry to room two;
  e6 excludes card transfer beforehand; e8 links the only orange admission to Zarei.
  His arrival-after-weighing story therefore fails. The resealable paper strip is
  only a luggage label and is never treated as an inviolable security seal.
- Five wrapped bundles, each 20×10×10 cm, occupy **10 L** and weigh at most **5.25 kg**.
  They fit the observed tote's **12 L / 10 kg** capacity. Prepared bundles can be swapped
  in 80 seconds; papers can come out of the tote before cash goes in. No recount,
  unseen exit or extra accomplice is needed. Recovery of the hidden money remains a
  subsequent investigative action; the solution does not invent its hiding place.
- Mansouri hides violation of his nondelegation undertaking, the cleaner hides her
  daughter's presence, staff hide an off-book admission. Those explain dishonesty
  without treating every liar as the thief. Zarei's unpaid-contract dispute supplies
  motive; the wage claim does not authorize taking this money.

## Validation and blind-helper record

Read `CLAUDE.md`, current case-writing rules/log, actual original cases, loader/schema,
opening rules, accusation code, app evidence types and CI before writing. No AGENTS.md
was present in the freshly fetched tracked tree.

Separate helpers were invoked **sequentially**, as explicitly required by the repository
authoring rules. Each received only a public JSON with `solution` and `hints` removed,
without old drafts or answer context. These are internal public-only blind helper solves,
**not Claude's independent review** and not representative human-user playtests.

| Case | Actual iterations and resolved findings | Last measured difficulty |
|---|---|---|
| c037 | 3 public-only solves; exact-weight shortcut replaced by rounded competing loads; named cash provenance replaces a direct witnessed appropriation; no unsupported initial-packing claim; box-at-search wording clarified | 4/5 |
| c038 | 3 public-only solves; unique +6 shortcut removed by making all requests +6; unique student/grade mapping removed from receipt; innocent seat-error defense checked; lesson count reconciled | 3/5 |
| c039 | 5 public-only solves, including substantial plot revision; false-victim draft replaced; open-zip gap, tolerance, all-vs-part inference, carrying volume, card-transfer boundary and excessive machine-card spread resolved; final helper found no material flaw | 4/5 |

Validation commands from `server/`:

```sh
python -m pytest -q tests/test_c037_c039_rewrite.py tests/test_content.py tests/test_all_cases_flow.py
python -m pytest -q
```

The new tests extract numeric facts from the actual Persian cards: rounded competing
loads, traced serial subset, reversed stack, equal increases, cart/manifest mapping,
four-reading bounds, separate contents continuity, physical carrying volume and preserved
opening metadata. Existing API tests play all 50 cases, reject wrong suspect/proof and
accept every listed proof on fresh accounts; no test-only production-rule changes.

Local focused suite: **19 passed**. Local full suite: **439 passed, 26 skipped** (the
PostgreSQL-only tests require the isolated CI service). An initial local full run failed
in four unrelated billing tests because this managed environment supplies a SOCKS proxy
without `socksio`; installing that package only in the temporary test venv resolved them.
No dependency or billing code was changed. CI must still be checked at the pushed head;
the exact head/run URLs and outcome belong in the delivery report, not a stale success
claim embedded in this commit. No release workflow is to be triggered.

Known boundary: **target 5 is not independently confirmed by difficulty testing**.
The helper estimates above are reported without inflating them. Technical validation
does not certify enjoyment, reading density, human difficulty or publication readiness.
