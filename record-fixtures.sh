#!/usr/bin/env bash
#
# record-fixtures.sh
# Copies test fixtures into My Enphase Tests/test-data/ so that the
# integration tests can run.
#
# Fixture sources, tried in order:
#   1. Booted simulator with app installed and fixtures exported via
#      Settings > Export Test Fixtures
#   2. Connected physical device (via devicectl)
#   3. Live Enphase API fetch (requires .env with credentials)
#
# Usage:
#   bash record-fixtures.sh            # auto-detects source or prompts
#   bash record-fixtures.sh --force    # overwrite fixtures for dates that already exist
#
# PREREQUISITES for simulator/device path:
#   1. Build and run the app in DEBUG (bash build.sh, or Cmd+R in Xcode on a simulator).
#   2. Wait for real energy data to load in the SITE ENERGY REPORT.
#   3. Open Settings > Export Test Fixtures.
#   4. Run this script.
#
# PREREQUISITES for API path:
#   Copy .env.example to .env and fill in your credentials, then run this script.
#
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case $arg in
    --force) FORCE=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Source deployment config (never committed — see .env.example)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/.env" ] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

fail() { echo ""; echo "ERROR: $1" >&2; exit 1; }

[ -n "${PROJECT_DIR:-}" ] || fail "PROJECT_DIR not set — copy .env.example to .env and fill it in"
[ -n "${BUNDLE_ID:-}"   ] || fail "BUNDLE_ID not set — copy .env.example to .env and fill it in"
[ -d "$PROJECT_DIR"     ] || fail "PROJECT_DIR does not exist: $PROJECT_DIR"

TEST_DATA_DIR="$PROJECT_DIR/My Enphase Tests/test-data"

section() { echo ""; echo "==> $1"; }
ok()      { echo "    ✓  $1"; }
skip()    { echo "    ⊘  $1 (already exists — use --force to overwrite)"; }
warn()    { echo "    ⚠  $1"; }

echo "============================================================"
echo " Recording test fixtures for: $PROJECT_DIR"
echo "============================================================"

# ── Step 1: find fixture source ──────────────────────────────────

SOURCE_DIR=""
TMP_DIR=""

cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Try a booted simulator first ---
section "Looking for booted simulator with app installed"

BOOTED_IDS=$(xcrun simctl list devices booted -j 2>/dev/null \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
ids = [dev['udid'] for devs in d.get('devices', {}).values() for dev in devs if dev.get('state') == 'Booted']
print('\n'.join(ids))
" 2>/dev/null || true)

for SIM_ID in $BOOTED_IDS; do
  CONTAINER=$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [ -n "$CONTAINER" ] && [ -d "$CONTAINER/Documents/test-data" ]; then
    SOURCE_DIR="$CONTAINER/Documents/test-data"
    ok "Found fixtures in simulator $SIM_ID"
    ok "Source: $SOURCE_DIR"
    break
  elif [ -n "$CONTAINER" ]; then
    warn "App installed on simulator $SIM_ID but no fixtures found."
    warn "Open the app, load data, then tap Settings > Export Test Fixtures."
  fi
done

# --- Fall back to physical device via devicectl ---
if [ -z "$SOURCE_DIR" ]; then
  section "No simulator fixtures found — checking connected devices"

  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/{found=1} found && /[0-9A-F]{8}-/{print $1; exit}' || true)

  if [ -n "$DEVICE_ID" ]; then
    ok "Found connected device: $DEVICE_ID"
    TMP_DIR=$(mktemp -d)

    # devicectl copies the entire app Documents folder
    if xcrun devicectl device copy from \
        --device "$DEVICE_ID" \
        --source "${BUNDLE_ID}/Documents/test-data" \
        --destination "$TMP_DIR" 2>/dev/null; then
      if [ -d "$TMP_DIR/test-data" ]; then
        SOURCE_DIR="$TMP_DIR/test-data"
        ok "Copied fixture data from device"
      fi
    fi

    if [ -z "$SOURCE_DIR" ]; then
      warn "Could not read fixtures from device automatically."
    fi
  fi
fi

# --- Fall back to live Enphase API ---
if [ -z "$SOURCE_DIR" ]; then
  if [ -n "${ENPHASE_REFRESH_TOKEN:-}" ] && \
     [ -n "${ENPHASE_CLIENT_ID:-}" ] && \
     [ -n "${ENPHASE_CLIENT_SECRET:-}" ] && \
     [ -n "${ENPHASE_API_KEY:-}" ]; then
    section "No device fixtures found — fetching directly from Enphase API"
    TMP_DIR=$(mktemp -d)
    API_FETCH_FAILED=0

    python3 - "$TMP_DIR" \
              "$ENPHASE_API_KEY" \
              "$ENPHASE_CLIENT_ID" \
              "$ENPHASE_CLIENT_SECRET" \
              "$ENPHASE_REFRESH_TOKEN" <<'PYEOF' || API_FETCH_FAILED=1
import json, sys, os, time, urllib.request, urllib.parse, urllib.error, base64
from datetime import datetime, date

dest_root, api_key, client_id, client_secret, refresh_token = sys.argv[1:]

BASE_URL  = 'https://api.enphaseenergy.com/api/v4'
TOKEN_URL = 'https://api.enphaseenergy.com/oauth/token'

def get_access_token():
    creds = base64.b64encode(f'{client_id}:{client_secret}'.encode()).decode()
    body  = urllib.parse.urlencode({'grant_type': 'refresh_token',
                                    'refresh_token': refresh_token}).encode()
    req = urllib.request.Request(TOKEN_URL, data=body, method='POST')
    req.add_header('Authorization', f'Basic {creds}')
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())['access_token']
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors='replace')
        print(f'    ✗  Token request failed: HTTP {e.code} — {body}', file=sys.stderr)
        raise

def api_get(endpoint, token, _retries=3):
    sep = '&' if '?' in endpoint else '?'
    url = f'{BASE_URL}/{endpoint}{sep}key={urllib.parse.quote(api_key)}'
    req = urllib.request.Request(url)
    req.add_header('Authorization', f'Bearer {token}')
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 429 and _retries > 0:
            print(f'    ⏳ Rate limited — waiting 60s before retry ({_retries} left)...')
            time.sleep(60)
            return api_get(endpoint, token, _retries - 1)
        body = e.read().decode(errors='replace')
        print(f'    ✗  API error: HTTP {e.code} — {body}', file=sys.stderr)
        raise

today    = date.today()
date_str = today.isoformat()
start_at = int(datetime(today.year, today.month, today.day).timestamp())
end_at   = int(time.time())

print(f'    Fetching fixtures for {date_str}')
token   = get_access_token()
print('    ✓  Access token')

systems = api_get('systems', token).get('systems', [])
print(f'    ✓  {len(systems)} system(s) found')

out_dir = os.path.join(dest_root, date_str)
os.makedirs(out_dir, exist_ok=True)

site = {'production': 0.0, 'consumption': 0.0, 'grid_import': 0.0, 'grid_export': 0.0}
sys_values = []

for s in systems:
    sid   = str(s['system_id'])
    sname = s.get('name', sid)
    print(f'    System: {sname} ({sid})')

    ep_map = [
        ('production',  f'systems/{sid}/telemetry/production_meter?start_at={start_at}&end_at={end_at}'),
        ('consumption', f'systems/{sid}/telemetry/consumption_meter?start_at={start_at}&end_at={end_at}'),
        ('battery',     f'systems/{sid}/telemetry/battery?start_at={start_at}&end_at={end_at}'),
        ('grid_import', f'systems/{sid}/energy_import_telemetry?start_at={start_at}&end_at={end_at}'),
        ('grid_export', f'systems/{sid}/energy_export_telemetry?start_at={start_at}&end_at={end_at}'),
    ]
    resp = {}
    for name, ep in ep_map:
        try:
            data = api_get(ep, token)
            with open(os.path.join(out_dir, f'{name}_{sid}.json'), 'w') as f:
                json.dump(data, f, indent=2)
            resp[name] = data
            print(f'      ✓  {name}')
        except Exception as e:
            print(f'      ⚠  {name}: {e}')
            resp[name] = {}

    def sfield(ivals, field):
        return sum((iv.get(field) or 0) for iv in ivals)

    prod_wh   = sfield(resp.get('production',  {}).get('intervals', []), 'wh_del')
    cons_wh   = sfield(resp.get('consumption', {}).get('intervals', []), 'enwh')
    gi_wh     = sum((iv.get('wh_imported') or 0)
                    for arr in resp.get('grid_import', {}).get('intervals', [])
                    for iv in arr)
    ge_wh     = sum((iv.get('wh_exported') or 0)
                    for arr in resp.get('grid_export', {}).get('intervals', [])
                    for iv in arr)
    bat_ivals = resp.get('battery', {}).get('intervals', [])
    bc_wh     = sum(((iv.get('charge')    or {}).get('enwh') or 0) for iv in bat_ivals)
    bd_wh     = sum(((iv.get('discharge') or {}).get('enwh') or 0) for iv in bat_ivals)
    bat_soc   = int(((bat_ivals[-1].get('soc') or {}).get('percent') or 0)) if bat_ivals else 0

    site['production']  += prod_wh
    site['consumption'] += cons_wh
    site['grid_import'] += gi_wh
    site['grid_export'] += ge_wh

    sys_values.append({
        'id':                       sid,
        'production_today':         prod_wh / 1000,
        'consumption_today':        cons_wh / 1000,
        'battery_soc':              bat_soc,
        'grid_import_today':        gi_wh   / 1000,
        'grid_export_today':        ge_wh   / 1000,
        'battery_charged_today':    bc_wh   / 1000,
        'battery_discharged_today': bd_wh   / 1000,
        'net_flow_today':           (gi_wh - ge_wh) / 1000,
    })

payload = {
    'date': date_str,
    'site': {
        'production_today':  site['production']  / 1000,
        'consumption_today': site['consumption'] / 1000,
        'grid_import_today': site['grid_import'] / 1000,
        'grid_export_today': site['grid_export'] / 1000,
        'net_flow_today':    (site['grid_import'] - site['grid_export']) / 1000,
    },
    'systems': sys_values,
}
with open(os.path.join(out_dir, 'expected_values.json'), 'w') as f:
    json.dump(payload, f, indent=2, sort_keys=True)
print('    ✓  expected_values.json')
PYEOF

    if [ "$API_FETCH_FAILED" -eq 0 ] && [ -d "$TMP_DIR" ]; then
      SOURCE_DIR="$TMP_DIR"
    else
      warn "API fetch failed — check credentials in .env"
    fi
  fi
fi

# --- Nothing found anywhere ---
if [ -z "$SOURCE_DIR" ]; then
  echo ""
  echo "No fixture data found. Complete these steps first:"
  echo ""
  echo "  API (fastest — no simulator required):"
  echo "    1.  cp .env.example .env"
  echo "    2.  Fill in your credentials in .env"
  echo "    3.  Re-run this script"
  echo ""
  echo "  SIMULATOR (recommended for development):"
  echo "    1.  Boot a simulator: open Simulator.app, or Xcode > Open Simulator"
  echo "    2.  Run the app in DEBUG: bash build.sh  (or Cmd+R in Xcode)"
  echo "    3.  Wait for real data to appear in the SITE ENERGY REPORT"
  echo "    4.  Settings > Export Test Fixtures"
  echo "    5.  Re-run this script"
  echo ""
  echo "  PHYSICAL DEVICE (alternative):"
  echo "    1.  Run the app on device and export fixtures as above"
  echo "    2.  In Xcode: Window > Devices and Simulators"
  echo "    3.  Select your iPhone > Installed Apps > My Enphase"
  echo "    4.  Click the gear icon > Download Container"
  echo "    5.  Right-click the downloaded .xcappdata > Show Package Contents"
  echo "    6.  Copy AppData/Documents/test-data/<date>/ into:"
  echo "        My Enphase Tests/test-data/"
  echo ""
  exit 1
fi

# ── Step 2: copy fixture date directories into the test target ───

section "Copying fixtures to My Enphase Tests/test-data/"

mkdir -p "$TEST_DATA_DIR"

DATE_DIRS=$(find "$SOURCE_DIR" -maxdepth 1 -type d -name "????-??-??" | sort -r)

if [ -z "$DATE_DIRS" ]; then
  fail "Source directory exists but contains no dated fixture folders: $SOURCE_DIR"
fi

COPIED=0
SKIPPED=0

while IFS= read -r DATE_DIR; do
  DATE=$(basename "$DATE_DIR")
  DEST="$TEST_DATA_DIR/$DATE"
  FILE_COUNT=$(find "$DATE_DIR" -type f | wc -l | tr -d ' ')

  if [ -d "$DEST" ] && [ "$FORCE" -eq 0 ]; then
    skip "$DATE  ($FILE_COUNT files)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  rm -rf "$DEST"
  cp -r "$DATE_DIR" "$DEST"
  ok "$DATE  ($FILE_COUNT files copied)"
  COPIED=$((COPIED + 1))
done <<< "$DATE_DIRS"

# ── Step 3: summary ─────────────────────────────────────────────

echo ""
echo "============================================================"
if [ "$COPIED" -gt 0 ]; then
  echo " DONE. $COPIED fixture date(s) recorded."
  echo " Run  bash test.sh  to validate against them."
else
  echo " Nothing new to record ($SKIPPED date(s) already present)."
  echo " Use --force to overwrite existing fixture dates."
fi
echo "============================================================"
