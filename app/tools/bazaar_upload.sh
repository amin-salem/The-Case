#!/usr/bin/env bash
# Uploads a built APK to Cafe Bazaar through the Pishkhan API as an UNPUBLISHED release (Amin presses «انتشار» himself).
#   PISHKHAN_API_TOKEN=... tools/bazaar_upload.sh [--dry-run] <apk> <notes.md> <build-number>
# --dry-run prints the requests (token masked) and sends nothing. The token is read from the environment only and is
# never printed. Exit 0 = uploaded and committed, never published; anything else = a clear line on what went wrong.
# API: https://api.pishkhan.cafebazaar.ir/v1 (POST /apps/releases/, DELETE /apps/releases/, POST /apps/releases/upload/,
# POST /apps/releases/commit/), header CAFEBAZAAR-PISHKHAN-API-SECRET.
set -uo pipefail

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
APK="${1:-}"; NOTES="${2:-}"; BUILD="${3:-}"
BASE="${PISHKHAN_BASE:-https://api.pishkhan.cafebazaar.ir/v1}"
TOKEN="${PISHKHAN_API_TOKEN:-}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

say() { echo "bazaar_upload: $*"; }
die() { say "ERROR: $*"; exit 1; }

[ -n "$APK" ] && [ -n "$NOTES" ] && [ -n "$BUILD" ] || die "usage: bazaar_upload.sh [--dry-run] <apk> <notes.md> <build-number>"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "build number must be a number"
if [ "$DRY" = 0 ]; then
  [ -n "$TOKEN" ] || die "PISHKHAN_API_TOKEN is not set (GitHub: Settings > Secrets and variables > Actions)"
  [ -f "$APK" ] || die "APK not found: $APK"
fi
[ -f "$NOTES" ] || die "release notes file missing: $NOTES (write docs/bazaar-release-notes.md before building)"

# the notes of this build: a block that starts with <!-- build: N --> and has "## changelog_fa", "## changelog_en",
# "## developer_note" sections
python3 - "$NOTES" "$BUILD" "$TMP/body.json" <<'PY' || die "no release notes for build $BUILD in $NOTES (add a <!-- build: $BUILD --> block)"
import json, re, sys
path, build, out = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
blocks = re.split(r"<!--\s*build:\s*(\d+)\s*-->", text)
mine = None
for i in range(1, len(blocks) - 1, 2):
    if blocks[i] == build:
        mine = blocks[i + 1]
if mine is None:
    sys.exit(1)
secs = dict((m.group(1), m.group(2).strip()) for m in re.finditer(r"^##\s*(\w+)\s*\n(.*?)(?=^##\s|\Z)", mine, re.S | re.M))
fa = secs.get("changelog_fa", "")
if not fa:
    sys.exit(1)
body = {"changelog_fa": fa, "changelog_en": secs.get("changelog_en", ""), "developer_note": secs.get("developer_note", ""),
        "staged_rollout_percentage": 100, "auto_publish": False}
json.dump(body, open(out, "w", encoding="utf-8"), ensure_ascii=False)
PY

# call METHOD PATH [extra curl args...]: answer body in $TMP/out, prints the HTTP status; 429 is retried 3 times
call() {
  local method="$1" path="$2"; shift 2
  if [ "$DRY" = 1 ]; then
    echo "DRY $method $BASE$path [CAFEBAZAAR-PISHKHAN-API-SECRET: ****] $*" >&2
    echo 200 > "$TMP/code"; echo '{"package":{"version_code":'"$BUILD"'}}' > "$TMP/out"; return 0
  fi
  local n=0 code
  while :; do
    code=$(curl -sS -m 600 -o "$TMP/out" -w '%{http_code}' -X "$method" -H "CAFEBAZAAR-PISHKHAN-API-SECRET: $TOKEN" "$@" "$BASE$path" 2>"$TMP/err") || code=000
    echo "$code" > "$TMP/code"
    if [ "$code" = 429 ] && [ "$n" -lt 3 ]; then n=$((n+1)); say "429 from Bazaar, waiting 20 s (try $n of 3)"; sleep 20; continue; fi
    return 0
  done
}
code() { cat "$TMP/code"; }

say "build $BUILD, $([ "$DRY" = 1 ] && echo 'DRY RUN' || echo 'real upload'), nothing is published"
call POST /apps/releases/ -H 'Content-Type: application/json' -d '{}'
case "$(code)" in
  201|200) ;;
  400) say "an unpublished release already exists: removing the old draft and creating again"
       call DELETE /apps/releases/
       case "$(code)" in 200|202|204) ;; *) die "could not remove the old draft (HTTP $(code))" ;; esac
       call POST /apps/releases/ -H 'Content-Type: application/json' -d '{}'
       case "$(code)" in 201|200) ;; *) die "could not create the release (HTTP $(code))" ;; esac ;;
  401|403) die "Bazaar refused the token (HTTP $(code)): get a new token in Pishkhan > API > دریافت توکن جدید" ;;
  *) die "could not create the release (HTTP $(code))" ;;
esac

call POST /apps/releases/upload/ -F architecture=all -F "apk=@${APK};type=application/vnd.android.package-archive"
case "$(code)" in 200|201) ;; 401|403) die "Bazaar refused the token on upload (HTTP $(code))" ;; *) die "APK upload failed (HTTP $(code))" ;; esac
GOT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("package",{}).get("version_code",""))' "$TMP/out" 2>/dev/null || true)
[ "$GOT" = "$BUILD" ] || die "Bazaar says version_code=$GOT but this build is $BUILD: not committing"

call POST /apps/releases/commit/ -H 'Content-Type: application/json' --data-binary "@$TMP/body.json"
case "$(code)" in 200|201|204) ;; *) die "commit failed (HTTP $(code))" ;; esac
say "done: build $BUILD is committed in Pishkhan and NOT published. Press «انتشار» there after Bazaar's review."
