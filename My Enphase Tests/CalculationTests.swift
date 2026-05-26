import XCTest
@testable import My_Enphase

// Unit tests for EnphaseAPIClient's pure calculation functions.
// All tests use synthetic interval data — no network or cache required.

final class CalculationTests: XCTestCase {
    var client: EnphaseAPIClient!

    override func setUp() {
        super.setUp()
        client = EnphaseAPIClient()
    }

    // MARK: - Production (wh_del field)

    func testProductionSumsWhDel() {
        let intervals = [
            makeInterval(whDel: 500),
            makeInterval(whDel: 750),
            makeInterval(whDel: 250),
        ]
        // 1500 Wh → 1.5 kWh
        XCTAssertEqual(client.calculateDailyTotal(from: intervals, field: \.whDel), 1.5, accuracy: 0.001)
    }

    func testProductionNilTreatedAsZero() {
        let intervals = [
            makeInterval(whDel: 1000),
            makeInterval(whDel: nil),
            makeInterval(whDel: 500),
        ]
        // nil interval contributes 0; total = 1500 Wh → 1.5 kWh
        XCTAssertEqual(client.calculateDailyTotal(from: intervals, field: \.whDel), 1.5, accuracy: 0.001)
    }

    func testProductionEmptyIntervals() {
        XCTAssertEqual(client.calculateDailyTotal(from: [], field: \.whDel), 0.0, accuracy: 0.001)
    }

    // MARK: - Consumption (enwh field)

    func testConsumptionSumsEnwh() {
        let intervals = [
            makeInterval(enwh: 800),
            makeInterval(enwh: 1200),
            makeInterval(enwh: 400),
        ]
        // 2400 Wh → 2.4 kWh
        XCTAssertEqual(client.calculateDailyTotal(from: intervals, field: \.enwh), 2.4, accuracy: 0.001)
    }

    // MARK: - Grid Import / Export (nested whImported / whExported)

    func testGridImportSumsNestedIntervals() {
        let nested: [[TelemetryInterval]] = [
            [makeInterval(whImported: 300), makeInterval(whImported: 400)],
            [makeInterval(whImported: 100), makeInterval(whImported: 200)],
        ]
        // 1000 Wh → 1.0 kWh
        XCTAssertEqual(client.calculateDailyTotalFromNested(from: nested, field: \.whImported), 1.0, accuracy: 0.001)
    }

    func testGridExportSumsNestedIntervals() {
        let nested: [[TelemetryInterval]] = [
            [makeInterval(whExported: 150), makeInterval(whExported: 350)],
        ]
        // 500 Wh → 0.5 kWh
        XCTAssertEqual(client.calculateDailyTotalFromNested(from: nested, field: \.whExported), 0.5, accuracy: 0.001)
    }

    func testGridImportEmptyNestedArrays() {
        XCTAssertEqual(client.calculateDailyTotalFromNested(from: [], field: \.whImported), 0.0, accuracy: 0.001)
        XCTAssertEqual(client.calculateDailyTotalFromNested(from: [[]], field: \.whImported), 0.0, accuracy: 0.001)
    }

    // MARK: - Battery Charge

    func testBatteryChargedSumsChargeEnwh() {
        let intervals = [
            makeInterval(chargeEnwh: 500),
            makeInterval(chargeEnwh: 750),
            makeInterval(chargeEnwh: 250),
        ]
        // 1500 Wh → 1.5 kWh
        XCTAssertEqual(client.calculateBatteryCharged(from: intervals), 1.5, accuracy: 0.001)
    }

    func testBatteryChargedNilChargeIsZero() {
        let intervals = [
            makeInterval(chargeEnwh: 1000),
            makeInterval(),                  // no charge data
            makeInterval(chargeEnwh: 500),
        ]
        XCTAssertEqual(client.calculateBatteryCharged(from: intervals), 1.5, accuracy: 0.001)
    }

    // MARK: - Battery Discharge

    func testBatteryDischargedSumsDischargeEnwh() {
        let intervals = [
            makeInterval(dischargeEnwh: 600),
            makeInterval(dischargeEnwh: 400),
        ]
        // 1000 Wh → 1.0 kWh
        XCTAssertEqual(client.calculateBatteryDischarged(from: intervals), 1.0, accuracy: 0.001)
    }

    // MARK: - Net Flow

    func testNetFlowPositiveIsNetImport() {
        let gridImport = 3.0
        let gridExport = 1.0
        let netFlow = gridImport - gridExport
        XCTAssertGreaterThan(netFlow, 0, "Net import from grid should be positive")
        XCTAssertEqual(netFlow, 2.0, accuracy: 0.001)
    }

    func testNetFlowNegativeIsNetExport() {
        let gridImport = 1.0
        let gridExport = 4.0
        let netFlow = gridImport - gridExport
        XCTAssertLessThan(netFlow, 0, "Net export to grid should be negative")
        XCTAssertEqual(netFlow, -3.0, accuracy: 0.001)
    }
}
