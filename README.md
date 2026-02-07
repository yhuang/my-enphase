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

An iOS app to monitor energy metrics from one or more Enphase systems using the Enphase Enlighten Cloud API v4. Features a clean, icon-enhanced interface with pull-to-refresh support and intelligent caching.

## Highlights

- **Multi-system monitoring** with combined and per-system reports
- **Pull-to-refresh** with intelligent 60-second cache to minimize API calls
- **Icon-enhanced UI** with SF Symbols for battery, solar, and grid status
- **OAuth 2.0 token refresh** (refresh token required)
- **SwiftUI-based** responsive design (iPhone / iPad)
- **Monospaced typography** at 16pt with clear visual hierarchy

## Prerequisites

- macOS with Xcode 15 (or latest compatible Xcode)
- iOS 16 or later to run the app on device/simulator
- Enphase Developer Portal account: https://developer-v4.enphase.com/
- OAuth credentials (API key, client ID, client secret) and a refresh token

## Open & Run

1. Open the Xcode project:
   ```bash
   open "My Enphase.xcodeproj"
   ```

2. Choose your development team under Signing & Capabilities
3. Build and run on a simulator or device

## Configuration (In-App)

1. Launch the app and tap the **gear icon** (⚙️) to open Settings
2. Enter API credentials:
   - API Key
   - Client ID
   - Client Secret
   - Refresh Token (required for in-app requests)
3. Add one or more systems via `Add System` (enter System ID and friendly name)
4. Save configuration

**Note**: The app currently expects a pre-obtained refresh token. An in-app OAuth authorization flow is planned.

### Finding Your System ID

1. Log into https://enlighten.enphaseenergy.com
2. Select a system and inspect the URL:
   ```
   https://enlighten.enphaseenergy.com/systems/SYSTEM_ID/overview
   ```
3. The numeric `SYSTEM_ID` is what you enter in the app

## UI Overview

### Navigation Bar
- **Title**: "ENPHASE MULTI-SYSTEM MONITOR" (19pt, orange, monospaced)
- **Settings**: Gear icon (⚙️) in top-right corner

### Report Stats (Header)
- **Updated**: Timestamp showing last data refresh
- **Orange separators** frame the stats section

### Combined Energy Report
- **Produced**: Total solar generation with sun icon (☀️)
- **Consumed**: Total household consumption
- **Net Flow**: Grid import/export with directional arrows
  - Pink ⬇️ for import (buying from grid)
  - Cyan ⬆️ for export (selling to grid)

### Individual Systems Report
For each system:
- **Grid Import**: Pink with down arrow icon
- **Grid Export**: Cyan with up arrow icon
- **Produced**: Yellow with sun.max.fill icon (☀️)
- **Net Grid Flow**: Shows import/export with arrows
- **Charged**: Green (#7acf38) with battery.100percent.bolt icon (🔋⚡)
- **Discharged**: Green (#7acf38) with battery.0percent icon (🔋)
- **Percent**: Battery state of charge (SOC) percentage
- **Total Consumed**: Orange

## Features

### Pull-to-Refresh
- **Pull down** on any screen to refresh data
- **Smart caching**: If data is < 60 seconds old, serves cached data immediately
- **No unnecessary API calls**: Respects cache TTL to avoid rate limits
- **Automatic retry**: Handles rate limit errors with intelligent backoff

### Intelligent Caching
- **60-second TTL**: Fresh data is reused to minimize API calls
- **Persistent cache**: Survives app restarts
- **Stale data fallback**: Shows cached data if API fails
- **Per-endpoint caching**: Each API call is independently cached

### Visual Design
- **Monospaced fonts**: 16pt for content, 19pt for title
- **Icon integration**: SF Symbols sized at 15pt for perfect alignment
- **Color coding**:
  - Orange: Headings, consumed energy, navigation title
  - Yellow: Solar production
  - Pink: Grid import
  - Cyan: Grid export
  - Green (#7acf38): Battery metrics
- **16pt left padding**: Content slightly indented for visual breathing room

## Project Structure

### Models
- [My Enphase/Models/EnphaseModels.swift](My%20Enphase/Models/EnphaseModels.swift)
  - `SystemMetrics`, `AggregatedMetrics`, `APIConfig`, `AppConfig`

### Services
- [My Enphase/Services/EnphaseAPIClient.swift](My%20Enphase/Services/EnphaseAPIClient.swift)
  - API client with OAuth refresh, telemetry endpoints
  - Rate-limit handling with automatic retry
  - Per-endpoint response caching (60-second TTL)
  
- [My Enphase/Services/APICache.swift](My%20Enphase/Services/APICache.swift)
  - Persistent cache with disk storage
  - Automatic expiration and cleanup
  
- [My Enphase/Services/DataAggregator.swift](My%20Enphase/Services/DataAggregator.swift)
  - Orchestrates multi-system requests
  - Aggregates metrics with report-level caching
  - Handles pull-to-refresh with cache awareness
  
- [My Enphase/Services/ConfigManager.swift](My%20Enphase/Services/ConfigManager.swift)
  - Persists `AppConfig` to `UserDefaults`
  - System add/remove helpers

### Views
- [My Enphase/Views/DashboardView.swift](My%20Enphase/Views/DashboardView.swift)
  - Main UI coordinator with pull-to-refresh
  - Navigation bar with title and settings
  
- [My Enphase/Views/SettingsView.swift](My%20Enphase/Views/SettingsView.swift)
  - Configure API credentials and systems
  
- **Components**:
  - `ReportStatsView` — Updated timestamp header
  - `CombinedReportView` — Aggregated totals
  - `IndividualSystemsView` — Per-system breakdown with icons

## Implementation Notes

### OAuth
- `EnphaseAPIClient.refreshAccessToken(using:)` performs token refresh
- Caches `access_token` until expiry
- API key appended as URL parameter to each request

### API Endpoints
Production, consumption, battery, import/export telemetry endpoints are called individually for each system. Each refresh can produce 4-6 API calls per system.

### Rate Limits
- HTTP 429 mapped to `rateLimitExceeded` error
- 60-second cache prevents excessive API calls
- Manual refresh control prevents uncontrolled polling
- Automatic retry with configurable wait time

### Persistence
- **Config**: `UserDefaults` key `enphase_app_config`
- **API Cache**: Disk-persisted at `enphase_api_cache.json`
- **Report Cache**: Disk-persisted at `enphase_report_cache.json`

## Usage

### Daily Monitoring
1. **Launch app** — shows most recent data from cache if available
2. **Pull down** to refresh if cache is stale (> 60 seconds)
3. View combined totals and individual system breakdowns
4. **Scroll down** to see "Updated:" timestamp at bottom

### Managing Settings
1. Tap **gear icon** (⚙️)
2. Modify API credentials or systems
3. Tap **Save**
4. App auto-refreshes if configured and no data loaded

## Troubleshooting

### "Authentication Required"
- Verify `API Key`, `Client ID`, `Client Secret`, and `Refresh Token` in Settings
- Ensure credentials match (from same Enphase app in Developer Portal)

### "Rate Limit Exceeded"
- Wait 60 seconds before retrying
- Cache reduces frequency of API calls
- Consider spacing out refreshes when monitoring multiple systems

### "Network error: cancelled"
- Caused by overlapping refresh requests
- App now uses detached tasks to prevent cancellation
- Pull-to-refresh checks if fetch is already in progress

### No Data
- Ensure systems are reporting to Enlighten
- Verify system IDs are correct (check Enlighten URLs)
- Check API credentials are active in Developer Portal

## Future Work

- **In-app OAuth flow** (obtain refresh token inside app)
- **Historical queries** (day/month/year)
- **Charts** for trend visualization
- **Background refresh** with notifications
- **Widgets** and Apple Watch support
- **Export data** to CSV

## Related Projects

If you use a companion CLI tool to obtain OAuth refresh tokens, keep its instructions with that project. This repository does not include the OAuth CLI.

## License

Personal utility project — modify for your own use.
