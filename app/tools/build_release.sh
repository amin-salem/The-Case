#!/usr/bin/env bash
# Builds the signed release APK for Cafe Bazaar.
#   ./tools/build_release.sh
#   API_URL=https://api.yourdomain.ir ./tools/build_release.sh
set -e
cd "$(dirname "$0")/.."

# INTERNET permission, Persian name, reminder permissions/receivers, desugaring (safe to repeat)
python3 tools/patch_android.py

if [ ! -f android/key.properties ]; then
  echo "NOTE: android/key.properties is missing, so this APK is signed with the DEBUG key (fine for testing, not for Bazaar)."
fi
BUILD=$(grep '^version:' pubspec.yaml | sed 's/.*+//')
NAME=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
API=${API_URL:-https://thecase.liara.run}
echo "Building version $NAME (build $BUILD) for $API ..."

flutter pub get
# never ship a build that fails its own checks (cases parse, scenes paint, sounds exist)
flutter analyze
flutter test
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=APP_BUILD="$BUILD" --dart-define=API_URL="$API"

mkdir -p release
cp build/app/outputs/flutter-apk/app-release.apk "release/the_case-$NAME-$BUILD.apk"
echo "Done: release/the_case-$NAME-$BUILD.apk"
echo "Install:  adb install -r release/the_case-$NAME-$BUILD.apk"
