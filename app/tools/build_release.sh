#!/usr/bin/env bash
# Builds the signed release APK for Cafe Bazaar.
#   ./tools/build_release.sh
#   API_URL=https://api.yourdomain.ir ./tools/build_release.sh
set -e
cd "$(dirname "$0")/.."

MANIFEST=android/app/src/main/AndroidManifest.xml
if [ ! -f "$MANIFEST" ]; then
  echo "Android project missing - run first:  flutter create --org ir.aminsalem --project-name the_case --platforms android ."
  exit 1
fi
# Release builds can't use the internet without this permission.
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  echo "Adding the INTERNET permission ..."
  sed -i '0,/<application/s||<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$MANIFEST"
fi
# Persian app name on the home screen
sed -i 's|android:label="the_case"|android:label="پرونده"|' "$MANIFEST"

if [ ! -f android/key.properties ]; then
  echo "NOTE: android/key.properties is missing, so this APK is signed with the DEBUG key (fine for testing, not for Bazaar)."
fi
BUILD=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
NAME=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
API=${API_URL:-https://thecase.liara.run}
echo "Building version $NAME (build $BUILD) for $API ..."

flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=APP_BUILD="$BUILD" --dart-define=API_URL="$API"

mkdir -p release
cp build/app/outputs/flutter-apk/app-release.apk "release/the_case-$NAME-$BUILD.apk"
echo "Done: release/the_case-$NAME-$BUILD.apk"
echo "Install:  adb install -r release/the_case-$NAME-$BUILD.apk"
