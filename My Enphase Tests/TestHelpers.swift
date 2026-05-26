import XCTest
@testable import My_Enphase

// MARK: - Tolerance assertion (mirrors sister project: 10% or 0.1 kWh, whichever is larger)

func assertMetric(
    _ actual: Double,
    matches expected: Double,
    label: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    let tolerance = max(abs(expected) * 0.10, 0.1)
    XCTAssertEqual(
        actual, expected, accuracy: tolerance,
        "\(label): got \(String(format: "%.3f", actual)) kWh, expected \(String(format: "%.3f", expected)) kWh (±\(String(format: "%.3f", tolerance)) kWh)",
        file: file, line: line
    )
}

// MARK: - Fixture file types

struct FixtureExpectedValues: Decodable {
    let date: String
    let site: FixtureExpectedSiteMetrics
    let systems: [FixtureExpectedSystemMetrics]
}

struct FixtureExpectedSiteMetrics: Decodable {
    let productionToday: Double
    let consumptionToday: Double
    let gridImportToday: Double
    let gridExportToday: Double
    let netFlowToday: Double

    enum CodingKeys: String, CodingKey {
        case productionToday    = "production_today"
        case consumptionToday   = "consumption_today"
        case gridImportToday    = "grid_import_today"
        case gridExportToday    = "grid_export_today"
        case netFlowToday       = "net_flow_today"
    }
}

struct FixtureExpectedSystemMetrics: Decodable {
    let id: String
    let productionToday: Double
    let consumptionToday: Double
    let batterySOC: Int
    let gridImportToday: Double
    let gridExportToday: Double
    let batteryChargedToday: Double
    let batteryDischargedToday: Double
    let netFlowToday: Double

    enum CodingKeys: String, CodingKey {
        case id
        case productionToday        = "production_today"
        case consumptionToday       = "consumption_today"
        case batterySOC             = "battery_soc"
        case gridImportToday        = "grid_import_today"
        case gridExportToday        = "grid_export_today"
        case batteryChargedToday    = "battery_charged_today"
        case batteryDischargedToday = "battery_discharged_today"
        case netFlowToday           = "net_flow_today"
    }
}

// MARK: - Fixture loading helpers

func loadFixture<T: Decodable>(_ filename: String, as type: T.Type) throws -> T {
    let bundle = Bundle(for: CalculationTests.self)
    guard let url = bundle.url(forResource: filename, withExtension: nil) else {
        throw XCTSkip("Fixture not found: \(filename) — run Settings > Export Test Fixtures first")
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(type, from: data)
}

// MARK: - EnergyInterval builders

func makeInterval(whDel: Double? = nil, enwh: Double? = nil,
                  whImported: Double? = nil, whExported: Double? = nil,
                  chargeEnwh: Double? = nil, dischargeEnwh: Double? = nil,
                  socPercent: Double? = nil) -> EnergyInterval {
    EnergyInterval(
        endAt: 0,
        devicesReporting: 1,
        whDel: whDel,
        whRec: nil,
        enwh: enwh,
        whImported: whImported,
        whExported: whExported,
        soc: socPercent.map { BatterySOC(percent: $0, devicesReporting: 1) },
        charge: chargeEnwh.map { BatteryMetrics(enwh: $0) },
        discharge: dischargeEnwh.map { BatteryMetrics(enwh: $0) }
    )
}
