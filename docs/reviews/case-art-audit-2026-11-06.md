# Case art audit — 6 November 2026

Base: `1db49849ade2a9de7510d39069dc0ffe94be585b` (remote main).

## Cause and fix

W005/s3 (سیاوش نامور) references m_mid_researcher. W006/s3 (قاسم بیات) references m_mid_worker; W006/s4 (ژیلا پاکزاد) references f_mid_waitress. None existed in the 124-file portrait pool or kPortraits. Both suspect widgets therefore deliberately selected CharacterPainter, not a broken remote download or Flutter logo. Existing tests only checked nightly portrait existence and silently skipped missing portraits in age/album tests.

Added these three distinct illustrated-realism portraits, registered them in kPortraits, and recorded apparent ages 46/36/32. No case text, metadata, answers, identity or reward changed. Existing portraits remain unchanged. Sources were created with the built-in image-generation tool; runtime files are 512×512 WebP, 84,782 bytes total. All 144 pre-existing portrait/scene files decoded locally; no byte-identical files were found. This is exact duplication detection, not a claim that all faces are perceptually distinct.

## Coverage and repetition

| Scope | Cases | Suspect appearances |
|---|---:|---:|
| Nightly | 62 | 310 |
| Weekend | 7 | 56 |
| Existing suspect-format story chapter | 1 | 5 |

Before: 124 shipped portraits, 115 distinct references in nightly/weekend, of which 112 resolved and 3 did not. After: 127 shipped portraits, all 115 references resolve. In nightly/weekend, 15 portraits occur once and 100 occur more than once; 251 of 366 appearances reuse an earlier portrait. No two suspects in the same case share an image. Twelve unused portraits are all elderly female portraits; redistributing them indiscriminately would break age/gender consistency. The five story appearances reuse existing images and do not add distinct portrait references.

Most reused: m_mid_technician and m_mid_lecturer, 8 cases each; m_mid_barista and m_young_casual, 7 each. This is a shared cast pool, not one unique face per fictional identity. Full uniqueness for nightly/weekend alone would require 366 distinct assigned portraits, and at least 239 additional files beyond the now-127 pool, with appropriate demographics (the actual requirement may be larger). This patch repairs missing art; it does not claim to remove existing reuse.

There are 20 shared scene backgrounds across 69 nightly/weekend cases. All referenced scene files exist and are registered. For example library occurs in c009/c029/c047/c061/w005 and hotel in c011/c031/c048/w006/w007. These are atmospheric theme illustrations, not unique forensic depictions of every case. No new investigation mechanics were introduced.

## Validation and release

- Local: `python -m unittest discover -s server/tests -p 'test_case_art_contract.py' -v` passed. Covers nightly, weekend and suspect-format story content, missing/empty portraits, within-cast duplicates, both Dart registries, age metadata and pubspec asset directories.
- Flutter regression test: all registered portraits must be in the built asset manifest and decode; the three repaired IDs must render Image widgets in static and animated suspect views rather than CharacterPainter. Run by branch CI; local Flutter SDK is unavailable.
- Read-only inventory: `python server/tools/audit_case_art.py` prints references/counts, missing files, reuse and SHA-256 duplicates, without culprit/solution fields.
- This is an APK asset fix. Deploying the server alone cannot fix installed clients. Do not spend a Liara deployment on this branch. Merge/integrate with latest release work before an owner-authorized APK release. No main/release push or APK publication was performed as part of this review branch.
- A device check of W005/Siavash and both W006 portraits remains pending. Already-installed older APKs continue using their old bundled assets until updated.

## Reproduction prompts

### m_mid_researcher

Create a single square 1024x1024 high-quality realistic painterly cinematic portrait for an Iranian noir detective mobile game. Head and shoulders, face centered fully visible, looking slightly towards viewer, dark navy almost black plain background. Warm amber sidelight from upper left, muted teal and brown clothing, realistic anatomy, subtly painted skin texture and detailed eyes, premium illustrated realism, not cartoon, not vector, not glossy 3D. Neutral calm expression, no visual implication of guilt. No text, symbols, logos, props or borders. Iranian male manuscript researcher aged 46, short dark hair with slight grey temples, tidy dark moustache, thin rectangular glasses worn on face, muted teal jacket over cream collarless shirt.

### m_mid_worker

Create a single square 1024x1024 high-quality realistic painterly cinematic portrait for an Iranian noir detective mobile game. Head and shoulders, face centered fully visible, looking slightly towards viewer, dark navy almost black plain background. Warm amber sidelight from upper left, muted teal and brown clothing, realistic anatomy, subtly painted skin texture and detailed eyes, premium illustrated realism, not cartoon, not vector, not glossy 3D. Neutral calm expression, no visual implication of guilt. No text, symbols, logos, props or borders. Iranian male hotel housekeeping worker aged 36, short dark hair with a few grey strands, light stubble, medium olive skin, no glasses, plain muted olive work shirt, no badge or tools.

### f_mid_waitress

Create a single square 1024x1024 high-quality realistic painterly cinematic portrait for an Iranian noir detective mobile game. Head and shoulders, face centered fully visible, looking slightly towards viewer, dark navy almost black plain background. Warm amber sidelight from upper left, muted teal and brown clothing, realistic anatomy, subtly painted skin texture and detailed eyes, premium illustrated realism, not cartoon, not vector, not glossy 3D. Neutral calm expression, no visual implication of guilt. No text, symbols, logos, props or borders. Iranian female hotel restaurant attendant aged 32, dark modest headscarf framing face, charcoal grey work blouse, light olive skin, no glasses, no jewellery, composed neutral expression.

