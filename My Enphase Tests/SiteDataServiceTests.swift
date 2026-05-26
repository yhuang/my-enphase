import XCTest
@testable import My_Enphase

// Integration tests that validate the full calculation pipeline against recorded
// fixture data. Tests skip automatically if no fixture date directory exists.
//
// To populate fixtures:
//   1. Run the app with real data until the SITE ENERGY REPORT shows correct values.
//   2. Settings > Export Test Fixtures.
//   3. Copy the exported folder from the app's Documents directory into
//      My Enphase Tests/test-data/<date>/.
//   4. Re-run tests — they will validate against the recorded golden values.

final class SiteDataServiceTests: XCTestCase {
    var client: EnphaseAPIClient!

    override func setUp() {
        super.setUp()
        client = EnphaseAPIClient()
    }

    func testSiteMetricsMatchExpectedValues() throws {
        let (expected, fixtures) = try loadFixtureDate()

        for system in expected.systems {
            let production  = try loadTelemetryResponse(fixtures: fixtures, endpoint: "production",  systemID: system.id)
            let consumption = try loadTelemetryResponse(fixtures: fixtures, endpoint: "consumption", systemID: system.id)
            let battery     = try loadTelemetryResponse(fixtures: fixtures, endpoint: "battery",     systemID: system.id)
            let gridImport  = try loadNestedIntervals  (fixtures: fixtures, endpoint: "grid_import", systemID: system.id)
            let gridExport  = try loadNestedIntervals  (fixtures: fixtures, endpoint: "grid_export", systemID: system.id)

            let productionTotal  = client.calculateDailyTotal(from: production.intervals,  field: \.whDel)
            let consumptionTotal = client.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
            let gridImportTotal  = client.calculateDailyTotalFromNested(from: gridImport,  field: \.whImported)
            let gridExportTotal  = client.calculateDailyTotalFromNested(from: gridExport,  field: \.whExported)
            let batteryCharged   = client.calculateBatteryCharged(from: battery.intervals)
            let batteryDischarged = client.calculateBatteryDischarged(from: battery.intervals)
            let netFlow          = gridImportTotal - gridExportTotal

            assertMetric(productionTotal,   matches: system.productionToday,      label: "[\(system.id)] Production")
            assertMetric(consumptionTotal,  matches: system.consumptionToday,     label: "[\(system.id)] Consumption")
            assertMetric(gridImportTotal,   matches: system.gridImportToday,      label: "[\(system.id)] Grid Import")
            assertMetric(gridExportTotal,   matches: system.gridExportToday,      label: "[\(system.id)] Grid Export")
            assertMetric(batteryCharged,    matches: system.batteryChargedToday,  label: "[\(system.id)] Battery Charge")
            assertMetric(batteryDischarged, matches: system.batteryDischargedToday, label: "[\(system.id)] Battery Discharge")
            assertMetric(netFlow,           matches: system.netFlowToday,         label: "[\(system.id)] Net Flow")
        }
    }

    func testSiteAggregateMatchesExpectedValues() throws {
        let (expected, fixtures) = try loadFixtureDate()

        var totalProduction:   Double = 0
        var totalConsumption:  Double = 0
        var totalGridImport:   Double = 0
        var totalGridExport:   Double = 0

        for system in expected.systems {
            let production  = try loadTelemetryResponse(fixtures: fixtures, endpoint: "production",  systemID: system.id)
            let consumption = try loadTelemetryResponse(fixtures: fixtures, endpoint: "consumption", systemID: system.id)
            let gridImport  = try loadNestedIntervals  (fixtures: fixtures, endpoint: "grid_import", systemID: system.id)
            let gridExport  = try loadNestedIntervals  (fixtures: fixtures, endpoint: "grid_export", systemID: system.id)

            totalProduction  += client.calculateDailyTotal(from: production.intervals,  field: \.whDel)
            totalConsumption += client.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
            totalGridImport  += client.calculateDailyTotalFromNested(from: gridImport,  field: \.whImported)
            totalGridExport  += client.calculateDailyTotalFromNested(from: gridExport,  field: \.whExported)
        }

        let site = expected.site
        assertMetric(totalProduction,              matches: site.productionToday,  label: "[Site] Production")
        assertMetric(totalConsumption,             matches: site.consumptionToday, label: "[Site] Consumption")
        assertMetric(totalGridImport,              matches: site.gridImportToday,  label: "[Site] Grid Import")
        assertMetric(totalGridExport,              matches: site.gridExportToday,  label: "[Site] Grid Export")
        assertMetric(totalGridImport - totalGridExport, matches: site.netFlowToday, label: "[Site] Net Flow")
    }
}

// MARK: - Private fixture loading

private extension SiteDataServiceTests {
    struct FixtureSet {
        let directory: URL
        let expected: FixtureExpectedValues
    }

    // Finds the first date directory under test-data/ that contains expected_values.json,
    // or skips the test if none exists.
    func loadFixtureDate() throws -> (FixtureExpectedValues, URL) {
        let bundle = Bundle(for: type(of: self))
        guard let testDataURL = bundle.url(forResource: "test-data", withExtension: nil) else {
            throw XCTSkip("No test-data/ directory found — run Settings > Export Test Fixtures first")
        }

        let dateDirs = (try? FileManager.default.contentsOfDirectory(
            at: testDataURL, includingPropertiesForKeys: nil
        ).filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent }) ?? []

        guard let dateDir = dateDirs.first else {
            throw XCTSkip("test-data/ is empty — run Settings > Export Test Fixtures first")
        }

        let expectedURL = dateDir.appendingPathComponent("expected_values.json")
        guard FileManager.default.fileExists(atPath: expectedURL.path) else {
            throw XCTSkip("No expected_values.json in \(dateDir.lastPathComponent)")
        }

        let expected = try JSONDecoder().decode(FixtureExpectedValues.self, from: Data(contentsOf: expectedURL))
        return (expected, dateDir)
    }

    func loadTelemetryResponse(fixtures: URL, endpoint: String, systemID: String) throws -> TelemetryResponse {
        let url = fixtures.appendingPathComponent("\(endpoint)_\(systemID).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing fixture: \(endpoint)_\(systemID).json")
        }
        return try JSONDecoder().decode(TelemetryResponse.self, from: Data(contentsOf: url))
    }

    func loadNestedIntervals(fixtures: URL, endpoint: String, systemID: String) throws -> [[TelemetryInterval]] {
        let url = fixtures.appendingPathComponent("\(endpoint)_\(systemID).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing fixture: \(endpoint)_\(systemID).json")
        }
        struct Wrapper: Decodable { let intervals: [[TelemetryInterval]] }
        return try JSONDecoder().decode(Wrapper.self, from: Data(contentsOf: url)).intervals
    }
}
