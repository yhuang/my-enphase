#!/usr/bin/env bash
#
# test.sh
# Builds and runs the "My Enphase Tests" suite on an iOS simulator.
#
# Usage:  bash test.sh
#
# SETUP:
#   Copy .env.example to .env and set PROJECT_DIR and SIMULATOR_ID.
#
# WHAT THIS SCRIPT DOES:
#   Runs all unit and integration tests.
#   - CalculationTests always run (synthetic data, no fixtures needed).
#   - SiteDataServiceTests are skipped until you export fixtures from the
#     app (Settings > Export Test Fixtures) and copy them into
#     My Enphase Tests/test-data/<date>/  — or run  bash record-fixtures.sh.
#
set -euo pipefail

# Source deployment config (never committed — see .env.example)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

fail() { echo "ERROR: $1" >&2; exit 1; }

[ -n "${PROJECT_DIR:-}"   ] || fail "PROJECT_DIR not set — copy .env.example to .env and fill it in"
[ -n "${SIMULATOR_ID:-}"  ] || fail "SIMULATOR_ID not set — copy .env.example to .env and fill it in"
[ -d "$PROJECT_DIR"       ] || fail "PROJECT_DIR does not exist: $PROJECT_DIR"

PROJECT_NAME="${PROJECT_NAME:-My Enphase}"
PROJECT="$PROJECT_DIR/$PROJECT_NAME.xcodeproj"
[ -d "$PROJECT" ] || fail "Cannot find $PROJECT_NAME.xcodeproj in $PROJECT_DIR"

echo "============================================================"
echo " Testing: $PROJECT_NAME"
echo " Simulator: $SIMULATOR_ID"
echo " Project:   $PROJECT"
echo "============================================================"

echo "==> Running tests (building first if needed)"
xcodebuild test \
  -project "$PROJECT" \
  -scheme  "$PROJECT_NAME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -configuration Debug \
  2>&1 | grep -E \
    "Test [Ss]uite|Test [Cc]ase .*(passed|failed|skipped)|error:|BUILD FAILED|\*\* TEST" \
  | sed \
    -e 's/Test case /    /' \
    -e "s/' passed.*/ ✓/" \
    -e "s/' failed.*/ ✗/" \
    -e "s/' skipped.*/ ⊘  (no fixtures yet)/" \
    -e "s/Test [Ss]uite '\(.*\)' started.*/\n── \1/" \
    -e "/^$/d"

# Capture xcodebuild exit code through the pipe
EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "============================================================"
if [ "$EXIT_CODE" -eq 0 ]; then
  echo " TESTS PASSED."
else
  echo " TESTS FAILED (exit $EXIT_CODE)."
fi
echo "============================================================"

exit "$EXIT_CODE"
