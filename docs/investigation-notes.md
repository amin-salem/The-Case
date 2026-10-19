# Optional investigation notes

The evidence tab keeps the existing pins and adds a collapsed personal notebook.
An evidence card's link action or the current statement/Q&A in a suspect sheet can
start a connection. Choose an evidence card and a personal relation (possible
contradiction, possible support, needs checking), with an optional 280-character note.
Links can be revisited, edited or removed. No answer is assessed and no API action,
coin debit, reward, rank change or accusation prerequisite is introduced by notes.
Reading a saved claim/evidence uses a local preview, not an interrogation/reward call.

References use suspect ID and SHA-256 of statement or question+answer, so reordered
questions remain linked; changed/missing claims require an explicit new selection.
Evidence IDs stay stable and a content fingerprint warns when a card's text changes.
The old connection/note remains available for editing or removal. Nothing silently
reattaches to a different claim. Each case has at most 60 links; duplicate pairs merge.

Data lives in the app's private SharedPreferences, scoped by account ID and case ID.
There is no network sync, backup export or automatic clipboard copying. Offline
reopening and switching back to an account preserve its records. Account deletion
removes that account's local scoped records. The legacy app cleared notes when
switching accounts, so surviving legacy marks/pins/seen fields are migrated once to
the account present at upgrade. Unknown-owner legacy data is preserved but is never
adopted by a future account. Other/unknown saved fields are retained when saving.
An open notebook/editor closes or clears when the account changes; stale saves are
refused. Uninstalling/clearing app storage still removes local notes (no server sync).

CI tests cover stable references, content edits, limits, corrupt/missing data,
migration, account isolation, offline persistence, editing/removal, narrow RTL
screens and larger text. The claim-notes-ui artifact contains rendered Flutter
previews produced by the widget tests, not a replacement design/prototype or APK.
