# My Enphase iOS App

An iOS application for monitoring energy metrics from multiple Enphase solar systems via the Enphase Enlighten Cloud API v4. This app provides the same functionality as the Go terminal application but with a native iOS interface.

## Features

- **Multi-System Monitoring**: View combined metrics from multiple Enphase systems
- **Comprehensive Metrics**: Track production, consumption, battery usage, grid import/export
- **Historical Queries**: Query data by day, month, or year
- **OAuth 2.0 Authentication**: Secure API access with token management
- **Native iOS Interface**: SwiftUI-based design optimized for iPhone and iPad
- **Real-time Updates**: Fetch latest energy data with pull-to-refresh

## Screenshots

The app displays:
- Combined energy report (total production, consumption, net flow)
- Individual system details (per-system metrics and battery status)
- Historical data querying (select date and query type)
- Settings management (API credentials and system configuration)

## Prerequisites

- iOS 16.0 or later
- Xcode 15.0 or later
- **Enphase Developer Portal Account**: Register at https://developer-v4.enphase.com/
- **OAuth Credentials**: API key, client ID, client secret from the Developer Portal
- **System IDs**: Your Enphase system IDs from Enlighten

## Installation

1. **Open the project in Xcode:**
   ```bash
   open "Enphase Monitor App.xcodeproj"
   ```

2. **Select your development team** in the project settings (Signing & Capabilities)

3. **Build and run** the app on your device or simulator

## Configuration

### First-Time Setup

1. **Launch the app** - you'll see a welcome screen
2. **Tap "Open Settings"** to configure the app
3. **Enter API credentials:**
   - API Key from Enphase Developer Portal
   - Client ID (OAuth)
   - Client Secret (OAuth)
   - Refresh Token (from OAuth flow)

4. **Add your systems:**
   - Tap "Add System"
   - Enter System ID (from Enlighten URL)
   - Enter a friendly name
   - Repeat for each system

5. **Save Configuration**

### Finding Your System IDs

1. Log into https://enlighten.enphaseenergy.com
2. Select one of your systems
3. Look at the URL: `https://enlighten.enphaseenergy.com/systems/SYSTEM_ID/overview`
4. The number in the URL is your System ID

### OAuth Setup

To get your refresh token:

1. Use the Go application's OAuth setup:
   ```bash
   cd /path/to/enphase-monitor
   ./enphase-monitor --setup-oauth
   ```

2. Follow the interactive wizard to authorize and get your refresh token
3. Copy the refresh token to the iOS app settings

**Note**: The iOS app currently requires a pre-configured refresh token. A future version will include in-app OAuth flow.

## Usage

### Viewing Current Data

1. **Tap the refresh button** (↻) in the top-right to load today's data
2. View the **Combined Energy Report** showing totals across all systems
3. Scroll down to see **Individual System Reports** with detailed metrics

### Querying Historical Data

1. **Tap the calendar button** (📅) in the top-left
2. Select query type: **Day**, **Month**, or **Year**
3. Choose a date using the date picker
4. Tap **Apply** to load historical data

### Understanding Metrics

**Combined Energy Report:**
- **Produced**: Total solar generation (kWh)
- **Consumed**: Total household consumption (kWh)
# My Enphase (iOS)

An iOS app to monitor energy metrics from one or more Enphase systems using the Enphase Enlighten Cloud API v4. The app is implemented in SwiftUI and is intended as a personal utility for viewing combined and per-system energy metrics.

## Highlights

- Multi-system monitoring with combined and per-system reports
- Day / Month / Year historical queries
- OAuth 2.0 token refresh (refresh token required)
- SwiftUI-based UI (iPhone / iPad)
- Manual refresh to respect API rate limits

## Prerequisites

- macOS with Xcode 15 (or latest compatible Xcode)
- iOS 16 or later to run the app on device/simulator
- Enphase Developer Portal account: https://developer-v4.enphase.com/
- OAuth credentials (API key, client ID, client secret) and a refresh token

## Open & Run

1. Open the Xcode project at:

   open "My Enphase.xcodeproj"

2. Choose your development team under Signing & Capabilities.
3. Build and run on a simulator or device.

## Configuration (In-App)

1. Launch the app and open `Settings`.
2. Enter API credentials:
   - API Key
   - Client ID
   - Client Secret
   - Refresh Token (required for in-app requests)
3. Add one or more systems via `Add System` (enter System ID and a friendly name).
4. Save configuration.

Note: The app currently expects a pre-obtained refresh token. An in-app OAuth authorization flow is planned.

### Finding Your System ID

1. Log into https://enlighten.enphaseenergy.com
2. Select a system and inspect the URL such as:

   https://enlighten.enphaseenergy.com/systems/SYSTEM_ID/overview

3. The numeric `SYSTEM_ID` is what you enter in the app.

## Project Structure

- Models: [My Enphase/Models/EnphaseModels.swift](My%20Enphase/Models/EnphaseModels.swift)
  - `SystemMetrics`, `AggregatedMetrics`, `APIConfig`, `AppConfig`

- Services:
  - [My Enphase/Services/EnphaseAPIClient.swift](My%20Enphase/Services/EnphaseAPIClient.swift) — API client with OAuth refresh, telemetry endpoints, rate-limit handling, and helper calculations
  - [My Enphase/Services/DataAggregator.swift](My%20Enphase/Services/DataAggregator.swift) — Orchestrates multi-system requests and aggregates metrics
  - [My Enphase/Services/ConfigManager.swift](My%20Enphase/Services/ConfigManager.swift) — Persists `AppConfig` to `UserDefaults` and provides helpers to add/remove systems

- Views: [My Enphase/Views](My%20Enphase/Views)
  - `DashboardView.swift` — Main UI and coordinator
  - `SettingsView.swift` — Configure API credentials and systems
  - `Components/` — `HeaderView`, `CombinedReportView`, `IndividualSystemsView`

## Implementation Notes (from code)

- OAuth: `EnphaseAPIClient.refreshAccessToken(using:)` performs a token refresh using the configured `authorizationURL` and caches the `access_token` until expiry.
- API key: The client appends the API key as a URL parameter to each request (per the current implementation).
- Endpoints: Production, consumption, battery, import/export telemetry endpoints are called individually for each system; each refresh can produce multiple API calls per system.
- Rate limits: The client maps HTTP 429 to a `rateLimitExceeded` error; the UI uses manual refresh to avoid uncontrolled polling.
- Persistence: `ConfigManager` stores `AppConfig` in `UserDefaults` under the `enphase_app_config` key.

## Usage

- Tap the refresh control to fetch current data (DataAggregator will call the API for each configured system).
- Use the calendar control to switch between Day / Month / Year queries.

## Troubleshooting

- "Authentication Required": verify `API Key`, `Client ID`, `Client Secret`, and `Refresh Token` in `Settings`.
- "Rate Limit Exceeded": wait ~60 seconds and try again; limit API calls when multiple systems are configured.
- No data: ensure your systems are reporting to Enlighten and system IDs are correct.

## Future Work

- In-app OAuth flow (obtain refresh token inside the app)
- Response caching for offline viewing
- Background refresh with notifications
- Charts for historical trends, widget and Watch support

## Related Projects

If you use a companion CLI or helper (external) tool to obtain OAuth refresh tokens, keep its instructions with that project. This repository does not include the OAuth CLI.

## License

Personal utility project — modify for your own use.
