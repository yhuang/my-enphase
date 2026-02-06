# Enphase Monitor iOS App

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
- **Net Energy Flow**: Net import/export (positive = import, negative = export)

**Individual System Metrics:**
- **Imported from the Grid**: Energy purchased from utility (kWh)
- **Exported to the Grid**: Energy sold to utility (kWh)
- **Captured from the Sun**: Solar generation (kWh)
- **Net Energy Flow**: Net import/export for this system
- **Charged to Battery**: Energy stored in batteries (kWh)
- **Discharged from Battery**: Energy used from batteries (kWh)
- **Battery Charge Percentage**: Current battery state of charge (day queries only)
- **Total Consumed**: Total consumption for this system (kWh)

## Architecture

The iOS app follows clean architecture principles with separation of concerns:

### Models
- **EnphaseModels.swift**: Core data structures
  - `SystemMetrics`: Per-system energy metrics
  - `AggregatedMetrics`: Combined metrics from all systems
  - `AppConfig`: Application configuration
  - `APIConfig`: API credentials

### Services
- **EnphaseAPIClient.swift**: HTTP client for Enphase Cloud API v4
  - OAuth token management with automatic refresh
  - API endpoint wrappers
  - Error handling and rate limit detection
  
- **DataAggregator.swift**: Multi-system data orchestration
  - Fetches data from all configured systems
  - Aggregates metrics into combined totals
  - Manages loading and error states

- **ConfigManager.swift**: Configuration persistence
  - UserDefaults-based storage
  - API credential management
  - System configuration

### Views
- **DashboardView.swift**: Main screen coordinator
- **SettingsView.swift**: Configuration interface
- **Components/**:
  - `HeaderView.swift`: Query information display
  - `CombinedReportView.swift`: Aggregated metrics
  - `IndividualSystemsView.swift`: Per-system details

## API Rate Limits

The Enphase Cloud API v4 has the following limits:
- **10 requests per minute** per API key
- **1000 requests per month** (free developer plan)

The app respects these limits by:
- Manual refresh (no automatic background polling)
- Cached OAuth tokens (reduces token refresh calls)
- Clear error messages on rate limit (429 status)

**Best Practice**: Query data sparingly, especially when monitoring multiple systems. Each refresh makes 3+ API calls per system.

## Comparison with Go Application

| Feature | Go App | iOS App |
|---------|--------|---------|
| Multi-system monitoring | ✅ | ✅ |
| Historical queries (day/month/year) | ✅ | ✅ |
| OAuth 2.0 authentication | ✅ | ✅ (token management) |
| Automatic refresh | ✅ | ❌ (manual refresh) |
| Response caching | ✅ (disk-based) | ❌ (planned) |
| Test/validation mode | ✅ | ❌ |
| Color customization | ✅ (config file) | ✅ (hardcoded) |
| OAuth setup wizard | ✅ | ❌ (planned) |

## Troubleshooting

### "Authentication Required"
- Verify your API credentials in Settings
- Ensure your refresh token is valid
- Re-run OAuth setup using the Go app if needed

### "Rate Limit Exceeded"
- The API allows 10 calls per minute
- Wait 60 seconds before retrying
- Consider querying less frequently

### "Invalid Response" or Network Errors
- Check your internet connection
- Verify system IDs are correct
- Ensure API credentials are properly configured

### No Data Displayed
- Tap the refresh button to load data
- Check that your systems are reporting to Enlighten
- Try querying a recent historical date

## Future Enhancements

Planned features:
- [ ] In-app OAuth authorization flow
- [ ] Response caching for offline viewing
- [ ] Automatic background refresh with notifications
- [ ] Charts and graphs for historical trends
- [ ] Widget support for home screen
- [ ] Apple Watch companion app
- [ ] Export data to CSV
- [ ] Dark mode color customization

## Related Projects

This iOS app is based on the Go terminal application:
- **Go Application**: `/Users/jimmy.huang/workspace/enphase-monitor`
- **Documentation**: See Go app's README.md for comprehensive API documentation

## License

This is a personal utility project. Use and modify as needed for your own Enphase monitoring needs.
