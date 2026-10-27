# Nightly c025–c030 content revision — 2026-10-24

Scope: six existing cases, their notification teasers and review records. Base main:
`73b9c3a673920cc3d59c8d1efe2ed65adef921d6`. No runtime code, assets, opening dates,
case ids, culprit slots or player records are changed. Names/portraits were cross-checked.
Siavash is now Reza Behroozi's son **Siavash Behroozi**; Zari (30) is Hussein's (44)
younger sister. Story Mode's inspector is absent from all six Nightly intros.

## Deduction and corrections (spoilers)

- **c025 / s2 / proof e9:** Replaced handwriting identification and exhaustive alibi elimination
  with the blank receipt pair → witnessed writing → direct handoff → carbon transfer chain.
  Exact corrected lettering and the signature overrun through the torn corner connect the
  original will to that writing. No ink-age or pressure-dating claim. Mahnaz's old draft and
  Siavash's pen/payment are credible false leads, not handwriting proof of authorship.
- **c026 / s3 / e1,e3,e7,e9:** Distinguishes phone pallets from replacement sand pallets and
  inventory labels from device serials. The home clock is 40 minutes fast: recorded 03:12
  means 02:32. Keivan is present 02:20–02:55; Afshar 03:00–03:30. Automatic reconnection
  explains the session starting before Keivan arrives; the matched request's physical
  confirmation is required. Recovered phones plus labels establish the cover-up. The
  masked loader's identity is not falsely claimed as independently witnessed. Shared bank
  payment and Sohrab's username no longer identify the culprit by themselves.
- **c027 / s1 / e6,e7:** Unit17 → engine826 → Sadaf; unit28 → engine419 → Tufan.
  Deltas 4.8h and 6.8h minus witnessed tests of 1h and 2h leave 3.8h and 4.8h.
  Minimum powered trip is 60/14 + 20/60 = 4.619h; rounding cannot rescue Sadaf.
  Kourosh's 22:40–03:25 observed passage is 4.75h, compatible with Tufan.
  Speed is a stated route-tested ground-speed bound, not an RPM-limit assumption.
  Engine operation at the unmoored loading platform is explicit; refrigeration is not
  falsely treated as making theft physically impossible. Captain identity has its own witness.
- **c028 / s3 / e1–e4:** Device +40min: service 02:35–02:42 means01:55–02:02;
  tampering03:10–03:12 means02:30–02:32. Clean-cover baseline, exact torn label,
  intact cuff02:25 and torn return02:40 establish contact. The coat's owner is not
  assumed its wearer. Maziar's alibi does not cover the true interval, making the
  garment necessary. Spring closure is immediately logged; no second user can act
  after release without another opening. Simultaneous access is independently excluded.
  Rescue uses an external stop/disconnection; no medication dose instructions are supplied.
- **c029 / s5 / e1,e5,e8,e9:** Stamp5521 must follow14:24; its partial imprint continues
  onto the original book's fixed liner. Intact folder seal from14:40 bounds stamping
  before that time. Babak alone has access in that bounded interval. Witness sightline
  covers approaches, not hidden hand movements. Forged lending delays inspection;
  it does not magically transfer legal liability. Book recovered before departure.
- **c030 / s2 / e3,e4,e8,e10:** Removed guilty-knowledge giveaway. Fresh original-clasp
  tape is matched by exact tear and ink to a fragment enclosed in the second costume's
  seam. Empty clean hem/table inspected21:15; uninterrupted custody, only Mahtab handles
  it while sewing21:16–18; seam is intact until inspected. Quick change begins21:19,
  so innocent transfer during changing cannot place the fragment inside. The recovered
  original is in a shared prop box; the box's location does not identify Omid as thief.

## Review method and validation

Astra helpers received only public case snapshots (no hints/solutions), one helper at a time.
Early drafts were rejected as too easy, not recorded as passes. Final r5 blind scores:
c025 4.0; c026 4.5; c027 4.3; c028 4.2 with a successive-user gap; c029 4.5;
c030 4.1 with a custody gap. The two gaps were corrected and subjected to targeted review.
A new independent public-only Astra helper then read the exact final c028 and c030 snapshots,
sequentially: both PASS, 4/5, with no supported alternative or internal contradiction.
These were fresh blind checks, distinct from the targeted amendment reviews.

Stored difficulty is conservatively 4 for c025/c027/c028/c029/c030 and 5 for c026.
The existing difficulty economy therefore changes future eligible c026 quotes/rewards;
this revision does not backfill payments, clear progress, or change economy policy.

Commands:
- `python -m pytest -q tests/test_content.py tests/test_all_cases_flow.py tests/test_explanation_readable.py`
- `python -m pytest -q` — 470 passed, 26 PostgreSQL-only skips locally before final wording cleanup.
- Final focused rerun after wording/proof changes: 15 passed.
- Fraction-based arithmetic check: route lower bound, meter uncertainty, witnessed trip,
  both 40-minute offsets and seam-before-change ordering verified.
- `git diff --check`
- Runtime metadata/portrait comparison against base: all six ids, numbers, publish dates,
  scenes, categories and avatars preserved. All evidence references are schema-validated.

AI blind scores are editorial estimates, not measured retention or human playtest results.
No claim of independent human/Claude testing or production deployment verification.
