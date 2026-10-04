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

## Release APK
```bash
./tools/build_release.sh
```
The script adds the internet permission and the Persian app name if they're missing. For signing your release, see `docs/LAUNCH.md` in the flying_slipper repo; it uses the same steps.

## Code
| Folder | What's in it |
|---|---|
| `lib/screens/` | Screens: home, case, interrogation, accusation, result, archive, leaderboard, shop, profile, inbox |
| `lib/widgets/character.dart` | Characters drawn in code from each case's avatar description. They breathe, blink and talk. |
| `lib/widgets/scene.dart` | Animated scenes: rain, lightning, fire, lamps, train lights |
| `lib/services/api.dart` | Server connection. Coins, cases and solutions all live on the server. |
