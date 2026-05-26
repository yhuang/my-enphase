#if DEBUG
import Foundation

// Exports today's raw API responses and the current SiteMetrics as test fixtures.
// Output lands in the app's Documents directory under test-data/<date>/.
// Copy that folder into My Enphase Tests/test-data/ to activate integration tests.
struct FixtureRecorder {

    private static let isoFormatter = ISO8601DateFormatter()

    static func record(config: AppConfig, metrics: SiteMetrics) {
        let dateStr = String(isoFormatter.string(from: metrics.timestamp).prefix(10))

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destDir = documents.appendingPathComponent("test-data/\(dateStr)")

        Task.detached {
            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                DebugLogger.log("❌ FixtureRecorder: could not create directory — \(error)")
                return
            }

            extractAPIFixtures(config: config, to: destDir)
            writeExpectedValues(metrics: metrics, date: dateStr, to: destDir)

            let path = destDir.path
            DebugLogger.log("✅ FixtureRecorder: fixtures saved to \(path)")
            // Print unconditionally so the path appears in Xcode's console regardless of
            // whether debug logging is routed elsewhere.
            print("📂 Test fixtures exported to:\n\(path)")
        }
    }

    // MARK: - Private

    private static func extractAPIFixtures(config: AppConfig, to destDir: URL) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cacheURL = cacheDir.appendingPathComponent("enphase_cache.json")

        guard let cacheData = try? Data(contentsOf: cacheURL),
              let raw = try? JSONSerialization.jsonObject(with: cacheData) as? [String: [String: Any]]
        else {
            DebugLogger.log("⚠️ FixtureRecorder: could not read Cache from disk")
            return
        }

        for system in config.systems {
            let endpoints: [(name: String, fragment: String)] = [
                ("production",  "telemetry/production_meter"),
                ("consumption", "telemetry/consumption_meter"),
                ("battery",     "telemetry/battery"),
                ("grid_import", "energy_import_telemetry"),
                ("grid_export", "energy_export_telemetry"),
            ]

            for ep in endpoints {
                guard let (url, entry) = raw.first(where: {
                    $0.key.contains("systems/\(system.id)/\(ep.fragment)")
                }) else {
                    DebugLogger.log("⚠️ FixtureRecorder: no cache entry for \(ep.name) [\(system.id)]")
                    continue
                }

                // Cache serialises Data as base64; decode it to recover the raw JSON bytes.
                guard let base64 = entry["data"] as? String,
                      let responseData = Data(base64Encoded: base64)
                else {
                    DebugLogger.log("⚠️ FixtureRecorder: bad data field for \(url)")
                    continue
                }

                let dest = destDir.appendingPathComponent("\(ep.name)_\(system.id).json")
                do {
                    if let obj = try? JSONSerialization.jsonObject(with: responseData),
                       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted) {
                        try pretty.write(to: dest)
                    } else {
                        try responseData.write(to: dest)
                    }
                    DebugLogger.log("✅ FixtureRecorder: wrote \(dest.lastPathComponent)")
                } catch {
                    DebugLogger.log("❌ FixtureRecorder: could not write \(dest.lastPathComponent) — \(error)")
                }
            }
        }
    }

    // MARK: - Expected values (typed Codable structs keep format in sync with TestHelpers)

    private struct ExpectedValues: Encodable {
        let date: String
        let site: ExpectedSiteValues
        let systems: [ExpectedSystemValues]
    }

    private struct ExpectedSiteValues: Encodable {
        let productionToday: Double
        let consumptionToday: Double
        let gridImportToday: Double
        let gridExportToday: Double
        let netFlowToday: Double

        enum CodingKeys: String, CodingKey {
            case productionToday  = "production_today"
            case consumptionToday = "consumption_today"
            case gridImportToday  = "grid_import_today"
            case gridExportToday  = "grid_export_today"
            case netFlowToday     = "net_flow_today"
        }
    }

    private struct ExpectedSystemValues: Encodable {
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

    private static func writeExpectedValues(metrics: SiteMetrics, date: String, to destDir: URL) {
        let systemValues = metrics.systems.map { system in
            ExpectedSystemValues(
                id: system.id,
                productionToday: system.productionToday,
                consumptionToday: system.consumptionToday,
                batterySOC: system.batterySOC ?? 0,
                gridImportToday: system.gridImportToday ?? 0,
                gridExportToday: system.gridExportToday ?? 0,
                batteryChargedToday: system.batteryChargedToday ?? 0,
                batteryDischargedToday: system.batteryDischargedToday ?? 0,
                netFlowToday: system.netFlowToday ?? 0
            )
        }

        let payload = ExpectedValues(
            date: date,
            site: ExpectedSiteValues(
                productionToday: metrics.productionToday,
                consumptionToday: metrics.consumptionToday,
                gridImportToday: metrics.gridImportToday ?? 0,
                gridExportToday: metrics.gridExportToday ?? 0,
                netFlowToday: metrics.netFlowToday ?? 0
            ),
            systems: systemValues
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else {
            DebugLogger.log("❌ FixtureRecorder: could not encode expected_values")
            return
        }

        let dest = destDir.appendingPathComponent("expected_values.json")
        do {
            try data.write(to: dest)
            DebugLogger.log("✅ FixtureRecorder: wrote expected_values.json")
        } catch {
            DebugLogger.log("❌ FixtureRecorder: could not write expected_values.json — \(error)")
        }
    }
}
#endif
