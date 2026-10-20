# Android game screen protection

The game Android generation step now always installs FLAG_SECURE and disables
recents screenshots explicitly on API 33+. It has no runtime release toggle,
sharing bypass or debug exception. Flutter screenshot/widget tests render widgets
without an Android window, so those existing tests remain meaningful without a bypass.
The admin app is not changed.

Source: official Android documentation checked 20 Oct 2026 (Tehran):
- https://developer.android.com/security/fraud-prevention/activities
- https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean)

FLAG_SECURE asks Android to suppress window screenshots and capture on non-secure
displays/recording surfaces. Android/device implementations vary, especially on older
devices; this is one protection layer, not a universal anti-cheat guarantee.
The API-33 recents switch supplements FLAG_SECURE; it alone would not block screenshots.

## Generation and coverage

Run the existing game app/tools/patch_android.py after flutter create, as release
generation already does. The script copies three native source templates into the
generated package (which can differ from applicationId), registers SecureGameApplication
in the manifest, and changes MainActivity's base to SecureFlutterActivity while retaining
its existing body/hooks. It is idempotent and fails explicitly for an unsupported host
or a pre-existing custom Application, instead of silently shipping an unprotected build.

The host sets flags before Flutter's onCreate/first frame, then reapplies on resume and
window-focus changes. Application callbacks protect all activities in the game's own
process, including Poolakey's PaymentActivity and other in-app billing bridges, without
editing third-party libraries. Flutter dialogs/sheets and navigation render in the same
secured Flutter window. A future separately created native Dialog must apply the same
FLAG_SECURE to its own window; there is currently no case-reading native Dialog path.
External store/browser/system activities belong to other apps and are outside this
app's window control. Returning to the game reasserts protection. Text sharing, login,
payment and navigation code is not changed, and personal notes are never auto-copied
to the clipboard by this feature.

## Verification and limits

CI validates regeneration/idempotence, manifest/package binding, preservation of
existing hooks, and fail-closed handling of unsupported hosts. It also compiles the
native policy on a JDK against small Android/Flutter API-contract stubs and exercises
startup-before-super, API guards, lifecycle/focus restoration and a non-Flutter billing
bridge. This is a JVM contract test, not an Android runtime/screenshot test or APK build.

No Android device/emulator is available in the implementation environment. Before
release, on a real device/emulator, verify hardware screenshots, platform screen
recording/casting, recent-app previews, background/resume, rotation/recreation, Flutter
dialogs, payment cancel/success/return, login and existing text sharing. No such manual
platform verification is claimed here. Record Android/device versions and results.

A second physical camera, rooted/modified systems, memorized/previously known answers,
other-account reading and already-public content remain possible. Active-time and score
rules are deliberately unchanged: this measure does not prove the leaderboard cheat-proof.
Review anti-cheat timing/answer exposure separately; no extra scheduled task is created.
