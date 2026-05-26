#!/usr/bin/env bash
#
# build.sh
# Builds the "My Enphase" iOS app into an .ipa and delivers it to an
# iCloud Drive folder so it appears in the Files app on the iPhone,
# ready to import into SideStore.
#
# Usage:
#   bash build.sh              # build and deliver the .ipa
#   bash build.sh --setup      # print BUNDLE_ID, DEVELOPMENT_TEAM, and SIMULATOR_ID values
#
# SETUP:
#   Copy .env.example to .env and fill in your values before running.
#
# WHAT THIS SCRIPT DOES NOT DO:
#   It cannot open SideStore on the phone or tap "import" for you.
#   SideStore has no automation interface. After this script runs, the
#   manual step is:  open SideStore -> + -> iCloud Drive -> <folder> ->
#   tap the .ipa -> trust the certificate if prompted.
#
set -euo pipefail

# ── --setup helper ───────────────────────────────────────────────────────────
if [ "${1:-}" = "--setup" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  XCPROJ="$SCRIPT_DIR/My Enphase.xcodeproj/project.pbxproj"

  echo ""
  echo "============================================================"
  echo " .env values for first-time setup"
  echo "============================================================"

  # BUNDLE_ID
  echo ""
  echo "BUNDLE_ID"
  BUNDLE=$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' "$XCPROJ" 2>/dev/null \
    | sed 's/.*= *//; s/["; ]//g' || true)
  if [ -n "$BUNDLE" ]; then
    echo "  $BUNDLE"
  else
    echo "  (could not detect — check Xcode: target → General → Bundle Identifier)"
  fi

  # DEVELOPMENT_TEAM
  echo ""
  echo "DEVELOPMENT_TEAM"
  TEAMS=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '"[^"]+"' | sort -u || true)
  if [ -n "$TEAMS" ]; then
    echo "$TEAMS" | while IFS= read -r cert; do
      tid=$(echo "$cert" | grep -oE '[A-Z0-9]{10}' | tail -1)
      [ -n "$tid" ] && echo "  $tid  $cert"
    done
  else
    echo "  (no signing identities found — sign into Xcode with your Apple ID first)"
    echo "  Xcode → Settings → Accounts → add Apple ID"
  fi

  # SIMULATOR_ID
  echo ""
  echo "SIMULATOR_ID"
  xcrun simctl list devices available 2>/dev/null \
    | grep 'iPhone' \
    | sed 's/^[[:space:]]*/  /' || echo "  (no simulators found — install one via Xcode → Settings → Platforms)"

  echo ""
  echo "============================================================"
  echo " Copy the values above into your .env file."
  echo " Run  cp .env.example .env  first if you haven't already."
  echo "============================================================"
  echo ""
  exit 0
fi

# Source deployment config (never committed — see .env.example)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

fail() { echo "ERROR: $1" >&2; exit 1; }

[ -n "${PROJECT_DIR:-}"        ] || fail "PROJECT_DIR not set — copy .env.example to .env and fill it in"
[ -n "${BUNDLE_ID:-}"          ] || fail "BUNDLE_ID not set — copy .env.example to .env and fill it in"
[ -n "${ICLOUD_FOLDER_NAME:-}" ] || fail "ICLOUD_FOLDER_NAME not set — copy .env.example to .env and fill it in"
[ -d "$PROJECT_DIR"            ] || fail "PROJECT_DIR does not exist: $PROJECT_DIR"

PROJECT_NAME="${PROJECT_NAME:-My Enphase}"
PROJECT="$PROJECT_DIR/$PROJECT_NAME.xcodeproj"
[ -d "$PROJECT" ] || fail "Cannot find $PROJECT_NAME.xcodeproj in $PROJECT_DIR"

BUILD_DIR="$PROJECT_DIR/build"
IPA="$BUILD_DIR/$PROJECT_NAME.ipa"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$ICLOUD_FOLDER_NAME"

echo "============================================================"
echo " Deploying: $PROJECT_NAME"
echo " Bundle ID: $BUNDLE_ID"
echo " Project:   $PROJECT"
echo " Delivery:  iCloud Drive/$ICLOUD_FOLDER_NAME"
echo "============================================================"

# ---- Clean previous build ----
echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$ICLOUD_DIR"

# ---- Build for a real device (Release, iphoneos SDK) ----
echo "==> Building (this can take a minute)"
EXTRA_SIGNING=()
[ -n "${DEVELOPMENT_TEAM:-}" ] && EXTRA_SIGNING=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")

xcodebuild -project "$PROJECT" -scheme "$PROJECT_NAME" \
  -configuration Release -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  "${EXTRA_SIGNING[@]}" \
  build

# ---- Locate the built .app ----
APP_PATH=$(find "$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos" \
  -maxdepth 1 -name "*.app" | head -n1)
[ -n "$APP_PATH" ] || fail "Build finished but no .app was produced."
echo "==> Built app: $APP_PATH"

# ---- Assemble the .ipa manually (free Apple ID cannot use Distribute) ----
echo "==> Packaging .ipa"
rm -rf "$BUILD_DIR/Payload"
mkdir "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
( cd "$BUILD_DIR" && zip -qr "$PROJECT_NAME.ipa" Payload )
[ -f "$IPA" ] || fail ".ipa packaging failed."

# ---- Deliver to iCloud Drive ----
cp "$IPA" "$ICLOUD_DIR/$PROJECT_NAME.ipa"

echo ""
echo "============================================================"
echo " DONE."
echo " .ipa delivered to: iCloud Drive/$ICLOUD_FOLDER_NAME/$PROJECT_NAME.ipa"
echo ""
echo " It will sync to the Files app on your iPhone within a minute."
echo " Then, on the phone (manual - SideStore has no automation):"
echo "   1. Open SideStore"
echo "   2. Tap +"
echo "   3. iCloud Drive -> $ICLOUD_FOLDER_NAME -> $PROJECT_NAME.ipa"
echo "   4. Trust the certificate if prompted"
echo "============================================================"
