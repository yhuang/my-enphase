import XCTest
@testable import My_Enphase

// Unit tests for EnphaseAPIClient's pure calculation functions.
// All tests use synthetic interval data — no network or cache required.

final class CalculationTests: XCTestCase {

    // MARK: - Production (wh_del field)

    func testProductionSumsWhDel() {
        let intervals = [
            makeInterval(whDel: 500),
            makeInterval(whDel: 750),
            makeInterval(whDel: 250),
        ]
        // 1500 Wh → 1.5 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotal(from: intervals, field: \.whDel), 1.5, accuracy: 0.001)
    }

    func testProductionNilTreatedAsZero() {
        let intervals = [
            makeInterval(whDel: 1000),
            makeInterval(whDel: nil),
            makeInterval(whDel: 500),
        ]
        // nil interval contributes 0; total = 1500 Wh → 1.5 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotal(from: intervals, field: \.whDel), 1.5, accuracy: 0.001)
    }

    func testProductionEmptyIntervals() {
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotal(from: [], field: \.whDel), 0.0, accuracy: 0.001)
    }

    // MARK: - Consumption (enwh field)

    func testConsumptionSumsEnwh() {
        let intervals = [
            makeInterval(enwh: 800),
            makeInterval(enwh: 1200),
            makeInterval(enwh: 400),
        ]
        // 2400 Wh → 2.4 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotal(from: intervals, field: \.enwh), 2.4, accuracy: 0.001)
    }

    // MARK: - Grid Import / Export (nested whImported / whExported)

    func testGridImportSumsNestedIntervals() {
        let nested: [[EnergyInterval]] = [
            [makeInterval(whImported: 300), makeInterval(whImported: 400)],
            [makeInterval(whImported: 100), makeInterval(whImported: 200)],
        ]
        // 1000 Wh → 1.0 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotalFromNested(from: nested, field: \.whImported), 1.0, accuracy: 0.001)
    }

    func testGridExportSumsNestedIntervals() {
        let nested: [[EnergyInterval]] = [
            [makeInterval(whExported: 150), makeInterval(whExported: 350)],
        ]
        // 500 Wh → 0.5 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotalFromNested(from: nested, field: \.whExported), 0.5, accuracy: 0.001)
    }

    func testGridImportEmptyNestedArrays() {
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotalFromNested(from: [], field: \.whImported), 0.0, accuracy: 0.001)
        XCTAssertEqual(EnphaseAPIClient.calculateDailyTotalFromNested(from: [[]], field: \.whImported), 0.0, accuracy: 0.001)
    }

    // MARK: - Battery Charge

    func testBatteryChargedSumsChargeEnwh() {
        let intervals = [
            makeInterval(chargeEnergyWh: 500),
            makeInterval(chargeEnergyWh: 750),
            makeInterval(chargeEnergyWh: 250),
        ]
        // 1500 Wh → 1.5 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateBatteryCharged(from: intervals), 1.5, accuracy: 0.001)
    }

    func testBatteryChargedNilChargeIsZero() {
        let intervals = [
            makeInterval(chargeEnergyWh: 1000),
            makeInterval(),                       // no charge data
            makeInterval(chargeEnergyWh: 500),
        ]
        XCTAssertEqual(EnphaseAPIClient.calculateBatteryCharged(from: intervals), 1.5, accuracy: 0.001)
    }

    // MARK: - Battery Discharge

    func testBatteryDischargedSumsDischargeEnwh() {
        let intervals = [
            makeInterval(dischargeEnergyWh: 600),
            makeInterval(dischargeEnergyWh: 400),
        ]
        // 1000 Wh → 1.0 kWh
        XCTAssertEqual(EnphaseAPIClient.calculateBatteryDischarged(from: intervals), 1.0, accuracy: 0.001)
    }
}
