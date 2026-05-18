#!/usr/bin/env bash
#
# deploy_sidestore.sh
# Builds the "My Enphase" iOS app into an .ipa and delivers it to an
# iCloud Drive folder so it appears in the Files app on the iPhone,
# ready to import into SideStore.
#
# Usage:  bash deploy_sidestore.sh
#
# WHAT THIS SCRIPT DOES NOT DO:
#   It cannot open SideStore on the phone or tap "import" for you.
#   SideStore has no automation interface. After this script runs, the
#   manual step is:  open SideStore -> + -> iCloud Drive -> <folder> ->
#   tap the .ipa -> trust the certificate if prompted.
#
set -euo pipefail

# ======================================================================
# REQUIRED INPUT PARAMETERS  --  YOU MUST EDIT ALL THREE BEFORE RUNNING
# ======================================================================

# [1] PROJECT_DIR
#     Absolute path to the folder that CONTAINS "My Enphase.xcodeproj"
#     on your Mac. This is your Xcode project on disk, NOT the iCloud
#     folder. Find it: in Xcode, right-click the project in the
#     navigator -> "Show in Finder", then copy that folder's path.
#     Example: "$HOME/Developer/My Enphase"
PROJECT_DIR="/Users/yhuang/workspace/my-enphase"

# [2] BUNDLE_ID
#     The app's bundle identifier. Find it in Xcode: select the
#     "My Enphase" target -> General tab -> Identity -> Bundle Identifier.
#     Example: "com.jimmyhuang.MyEnphase"
#     (Used only for a sanity check + log output; must be one your free
#      Apple ID can sign.)
BUNDLE_ID="Duragility.Enphase-Monitor-App"

# [3] ICLOUD_FOLDER_NAME
#     The name of the folder you created inside iCloud Drive where the
#     .ipa should be delivered. You said you made one called
#     "My Enphase".  Just the folder name here, not a full path.
ICLOUD_FOLDER_NAME="My Enphase"

# ----------------------------------------------------------------------
# OPTIONAL PARAMETERS  --  leave as-is unless a build error tells you to
# ----------------------------------------------------------------------

# PROJECT_NAME: basename of the .xcodeproj and the scheme name.
# Change only if your .xcodeproj file or scheme is not "My Enphase".
PROJECT_NAME="My Enphase"

# DEVELOPMENT_TEAM: your 10-character Apple Team ID. Leave EMPTY first.
# Only fill this in if the build fails with a code-signing /
# provisioning error. Find it: Xcode -> Settings -> Accounts ->
# select your Apple ID -> the Team ID is shown next to your team.
DEVELOPMENT_TEAM=""

# ======================================================================
# END OF CONFIGURATION  --  no need to edit below this line
# ======================================================================

# ---- Validate that required parameters were filled in ----
fail() { echo "ERROR: $1" >&2; exit 1; }

[ -n "$PROJECT_DIR" ]        || fail "PROJECT_DIR is empty. Set parameter [1]."
[ -n "$BUNDLE_ID" ]          || fail "BUNDLE_ID is empty. Set parameter [2]."
[ -n "$ICLOUD_FOLDER_NAME" ] || fail "ICLOUD_FOLDER_NAME is empty. Set parameter [3]."
[ -d "$PROJECT_DIR" ]        || fail "PROJECT_DIR does not exist: $PROJECT_DIR"

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
xcodebuild -project "$PROJECT" -scheme "$PROJECT_NAME" \
  -configuration Release -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
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