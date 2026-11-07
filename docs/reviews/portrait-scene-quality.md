# Portrait and scene quality — execution checkpoint

Base main: 1db49849ade2a9de7510d39069dc0ffe94be585b. Branch: portrait-scene-quality.

Scope: annotate all 127 portraits (124 main + 3 verified recovery assets), enforce age/wardrobe/visual-neighbour rules, review c001-c062 and w001-w006; w007 also included in global uniqueness checks. No main/release push, no APK. Content changes restricted to avatar fields; scene_variant implementation requires owner approval first.

## Scene-variant design — awaiting owner approval

- Keep existing scene enum unchanged. Add optional scene_variant, restricted to lowercase ASCII letters/digits/underscores, length 1..48, and a checked-in allowed variant registry keyed by base scene. Reject path separators/traversal and unknown pairs.
- Server public case payload and summary expose scene_variant additively. No changes to rewards, solutions or schedules.
- Flutter model defaults absent variant to null; scene widget receives both fields. Try assets/scenes/<scene>_<variant>.webp; on asset-load failure use the original assets/scenes/<scene>.webp, preserving the current base-scene animation and procedural last fallback. All call sites must pass variant.
- Tests: legacy case JSON, valid/invalid variants, unknown pair rejection, public API propagation, successful variant display, missing-asset fallback, same base weather behavior.
- Illustrations are atmospheric establishing views, never forensic evidence or culprit clues. Proposed first pairs: tower/clock, tower/apartment, library/binding, library/silver, lab/plant_growth, lab/educational_workshop, airport/lounge, airport/medical_warehouse.
- Do not implement this design or add variant fields until Amin approves. Variant counts and scene briefs still pending the full location inventory.

## Progress and verification

- Ran requested git ls-remote --heads origin 'portrait-scene*': failed because this workspace is not an authenticated git checkout. Checked branch existence using authenticated GitHub branch API instead; no matching branch existed. Created portrait-scene-quality successfully from the base SHA.
- Read main remotely; SHA unchanged from prior audit. Existing asset snapshot previously checked against remote blob SHAs. Three recovery images checked by Git blob SHA and opened visually this turn.
- No tests claimed green at this checkpoint. No implementation complete yet.
