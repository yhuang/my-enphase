# My Enphase

An iOS app that shows today's energy metrics — production, consumption, battery, and grid flow — for one or more Enphase solar systems. Data comes directly from the Enphase Enlighten Cloud API v4.

---

## Prerequisites

| What | Where to get it |
|---|---|
| macOS + Xcode (latest) | Mac App Store |
| Enphase Enlighten account | Your existing account at enlighten.enphaseenergy.com |
| Enphase Developer account (free) | developer-v4.enphase.com |

---

## Step 1 — Clone and create your `.env`

```bash
git clone <repo-url>
cd my-enphase
cp .env.example .env
```

Open `.env` in any text editor. Fill in `PROJECT_DIR` with the full path to this folder (e.g. `/Users/yourname/code/my-enphase`) and `BUNDLE_ID` with your app's bundle identifier (you can change this to anything like `com.yourname.MyEnphase` — just keep it consistent with what you set in Xcode).

You'll fill in the remaining fields in the steps below.

---

## Step 2 — Get Enphase API credentials

1. Sign up at **developer-v4.enphase.com** (free — the "Watt" plan is sufficient)
2. Create a new application. For the redirect URI, use:
   ```
   https://api.enphaseenergy.com/oauth/redirect_uri
   ```
3. After creating the app, copy these three values into your `.env`:
   - `ENPHASE_API_KEY` — the API key shown on your app's detail page
   - `ENPHASE_CLIENT_ID` — also called "App ID" or "Client ID"
   - `ENPHASE_CLIENT_SECRET` — also called "App Secret"

---

## Step 3 — Get your OAuth refresh token

The app uses a refresh token to request fresh access tokens automatically. You only need to do this once; the refresh token does not expire unless you revoke it.

### 3a. Open the authorization URL in a browser

Replace `YOUR_CLIENT_ID` in this URL and paste it into your browser:

```
https://api.enphaseenergy.com/oauth/authorize?response_type=code&client_id=YOUR_CLIENT_ID&redirect_uri=https://api.enphaseenergy.com/oauth/redirect_uri
```

Sign in with your **Enlighten** credentials when prompted, then click **Allow**.

### 3b. Copy the authorization code

After you click Allow, your browser redirects to a page that shows a short code. Copy everything after `?code=` in the URL. It looks like `XXXXXXXXXXXXXXXX`.

### 3c. Exchange the code for a refresh token

Run this curl command, substituting your values:

```bash
curl -s -X POST "https://api.enphaseenergy.com/oauth/token" \
  -H "Authorization: Basic $(printf 'YOUR_CLIENT_ID:YOUR_CLIENT_SECRET' | base64)" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&redirect_uri=https://api.enphaseenergy.com/oauth/redirect_uri&code=YOUR_AUTH_CODE" \
  | python3 -m json.tool
```

The response includes `"refresh_token": "..."`. Copy that value into:
- `ENPHASE_REFRESH_TOKEN` in your `.env`
- The **Refresh Token** field in the app's Settings screen (Step 6)

> **Note:** The authorization code from Step 3b is single-use and expires in a few minutes. If the curl command fails, repeat from Step 3a.

---

## Step 4 — Find your system ID(s)

1. Log into **enlighten.enphaseenergy.com**
2. Select one of your systems
3. Look at the browser URL:
   ```
   https://enlighten.enphaseenergy.com/systems/SYSTEM_ID/overview
   ```
4. The number in the URL is your System ID. Repeat for each system you want to monitor.

---

## Step 5 — Open in Xcode and run

```bash
open "My Enphase.xcodeproj"
```

In Xcode:

1. Select the **My Enphase** target in the project navigator
2. Go to **Signing & Capabilities** and choose your development team (your Apple ID works — no paid account required for the simulator)
3. Choose a simulator from the toolbar (iPhone 16 or later recommended)
4. Press **Cmd+R** to build and run

---

## Step 6 — Configure the app

On first launch the dashboard will be empty. Tap the **gear icon (⚙)** to open Settings.

1. **API credentials** — enter the API Key, Client ID, Client Secret, and Refresh Token from Steps 2–3
2. **Systems** — tap **Add System**, enter the System ID from Step 4 and a friendly name (e.g. "Main House"). Repeat for each system.
3. Tap **Save**

Back on the dashboard, tap the **refresh button (↻)** to load today's data.

> **API Budget:** The free Enphase Watt plan provides 10 API requests per minute. With 2 systems × 5 metrics = 10 calls per fetch, one full fetch exhausts the entire per-minute budget. The app tracks this with a 60-second cooldown and serves cached data instead of re-fetching when the budget is exhausted.

> **Cache persistence:** The last fetched report is saved to disk. If you close and reopen the app within 60 seconds of a successful fetch, the cached data is shown immediately without any API calls.

---

## Running the tests

The test suite has two layers:

- **CalculationTests** — pure unit tests, no setup required, always run
- **SiteDataServiceTests** — integration tests that validate the full calculation pipeline against recorded API responses; they skip automatically until you provide fixture data

### Get a simulator UDID

```bash
xcrun simctl list devices available | grep iPhone
```

Copy a UDID (the string in parentheses) and add it to your `.env`:

```
SIMULATOR_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
```

### Record fixtures (one-time)

Fixtures are your personal API responses. They are gitignored — every developer generates their own.

**Option A — from the app (recommended):**

1. Run the app in Xcode on a simulator (**Cmd+R**)
2. Wait for today's data to appear in the dashboard
3. Open Settings → tap **Export Test Fixtures**
4. Run the recorder:
   ```bash
   bash record-fixtures.sh
   ```

**Option B — directly from the API (no simulator needed):**

Make sure `ENPHASE_API_KEY`, `ENPHASE_CLIENT_ID`, `ENPHASE_CLIENT_SECRET`, and `ENPHASE_REFRESH_TOKEN` are set in your `.env`, then:

```bash
bash record-fixtures.sh
```

The script fetches today's data and writes it to `My Enphase Tests/test-data/<today's date>/`.

> **If you see HTTP 429:** The Enphase Watt plan has a daily request budget. If it is exhausted, wait until the next calendar day and try again, or use Option A (the simulator export does not consume API budget).

### Run the tests

```bash
bash test.sh
```

---

## Building an .ipa for SideStore (optional)

If you want to sideload the app onto a real iPhone without a paid Apple Developer account, use **SideStore** with an `.ipa` built from this script.

1. Print the values you need for your `.env`:
   ```bash
   bash build.sh --setup
   ```
   This shows your `BUNDLE_ID` (detected from the project), `DEVELOPMENT_TEAM` (all signing identities on this Mac), and `SIMULATOR_ID` (all available simulators).
2. Copy the values into your `.env`
3. Build and deliver to iCloud Drive:
   ```bash
   bash build.sh
   ```
4. On your iPhone: open **SideStore** → **+** → **iCloud Drive** → find `My Enphase.ipa` → tap to install

---

## Troubleshooting

**"Authentication required" or blank dashboard**
Verify all four credential fields in Settings (API Key, Client ID, Client Secret, Refresh Token). Make sure the Client ID and Client Secret match the same developer app you used to generate the refresh token.

**HTTP 429 / "Usage limit exceeded for plan Watt"**
You've hit the API budget for this minute or day. The app will serve cached data. Wait 60 seconds for the per-minute limit, or until midnight (Pacific time) for the daily limit.

**Refresh token curl returns an error**
The authorization code from Step 3b is single-use and expires in a few minutes. Go back to Step 3a and start fresh.

**`bash test.sh` fails with "SIMULATOR_ID not set"**
Add `SIMULATOR_ID=...` to your `.env` (see the "Running the tests" section above).

**SiteDataServiceTests all show ⊘ (skipped)**
No fixture data is present. Follow the "Record fixtures" steps above.

**Build fails: "No account for team"**
In Xcode → Signing & Capabilities, set the team to your personal Apple ID. A free account is enough for simulator and sideloading via SideStore.
