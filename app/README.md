# پرونده: Flutter app

## First time
```bash
cd app
flutter create --org ir.aminsalem --project-name the_case --platforms android .
flutter pub get
flutter run -d R5CRC0PR5WT
```
`flutter create .` only adds the missing `android/` folder. It doesn't touch `lib/`.
The package name becomes `ir.aminsalem.the_case`.

The app talks to `https://thecase.liara.run`. To use another server:
```bash
flutter run --dart-define=API_URL=http://192.168.1.5:8000
```

## Sounds
```bash
python3 tools/make_sounds.py     # numpy + ffmpeg; rewrites assets/sounds/*.ogg
```

## App icon
The icon (fingerprint under a magnifier that shows the night and 9 o'clock) is drawn in `tools/launcher/src/*.svg`.
```bash
python3 tools/launcher/render.py   # needs Chrome/Chromium + Pillow; rewrites tools/launcher/res and assets/icon/logo.png
python3 tools/patch_android.py     # copies the icons into android/ (build_release.sh does this too)
```
`tools/launcher/store/icon_512.png` is the 512×512 icon for the Cafe Bazaar listing.
If you run `flutter run` without the build script, run `python3 tools/patch_android.py` once first so the
launcher and notification icons are in place.

## Tests
```bash
flutter analyze && flutter test   # includes: every server case parses, every scene paints, every sound exists
```

## Release APK
```bash
./tools/build_release.sh
```
The script runs `tools/patch_android.py` (internet and notification permissions, Persian app name, reminder
receivers, Gradle desugaring, launcher and notification icons). For signing your release, see `docs/LAUNCH.md` in the flying_slipper repo; it uses the same steps.

## Code
| Folder | What's in it |
|---|---|
| `lib/screens/` | Screens: home, case, interrogation, accusation, result, archive, leaderboard, shop, profile, inbox |
| `lib/widgets/character.dart` | Characters drawn in code from each case's avatar description. They breathe, blink and talk. |
| `lib/widgets/scene.dart`, `scene_extra.dart` | 20 animated scenes (rain, fire, lighthouse beam, snow, subway headlights, clock tower ...) |
| `lib/widgets/fx.dart` | Screen transitions, count-up numbers, confetti, torchlight, pins, mute button |
| `lib/services/sound.dart` | Ambience per scene, case-opening sting, interface sounds, mute |
| `lib/services/api.dart` | Server connection. Coins, cases and solutions all live on the server. |
