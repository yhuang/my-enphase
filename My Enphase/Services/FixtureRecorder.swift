#if DEBUG
import Foundation

// Exports today's raw API responses and the current SiteMetrics as test fixtures.
// Output lands in the app's Documents directory under test-data/<date>/.
// Copy that folder into My Enphase Tests/test-data/ to activate integration tests.
struct FixtureRecorder {

    static func record(config: AppConfig, metrics: SiteMetrics) {
        let dateStr = String(ISO8601DateFormatter().string(from: metrics.timestamp).prefix(10))

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destDir = documents.appendingPathComponent("test-data/\(dateStr)")

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            DebugLogger.log("❌ FixtureRecorder: could not create directory — \(error)")
            return
        }

        extractAPIFixtures(config: config, to: destDir)
        writeExpectedValues(metrics: metrics, config: config, date: dateStr, to: destDir)

        DebugLogger.log("✅ FixtureRecorder: fixtures saved to \(destDir.path)")
        print("📂 Test fixtures exported to:\n\(destDir.path)")
    }

    // MARK: - Private

    private static func extractAPIFixtures(config: AppConfig, to destDir: URL) {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cacheURL = cacheDir.appendingPathComponent("enphase_api_cache.json")

        guard let cacheData = try? Data(contentsOf: cacheURL),
              let raw = try? JSONSerialization.jsonObject(with: cacheData) as? [String: [String: Any]]
        else {
            DebugLogger.log("⚠️ FixtureRecorder: could not read APICache from disk")
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

                // The APICache serialises Data as base64; decode it to get the raw JSON bytes.
                guard let base64 = entry["data"] as? String,
                      let responseData = Data(base64Encoded: base64)
                else {
                    DebugLogger.log("⚠️ FixtureRecorder: bad data field for \(url)")
                    continue
                }

                let dest = destDir.appendingPathComponent("\(ep.name)_\(system.id).json")
                do {
                    // Pretty-print for readability
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

    private static func writeExpectedValues(metrics: SiteMetrics, config: AppConfig, date: String, to destDir: URL) {
        var systemValues: [[String: Any]] = []
        for system in metrics.systems {
            systemValues.append([
                "id":                       system.id,
                "production_today":         system.productionToday,
                "consumption_today":        system.consumptionToday,
                "battery_soc":              system.batterySOC,
                "grid_import_today":        system.gridImportToday,
                "grid_export_today":        system.gridExportToday,
                "battery_charged_today":    system.batteryChargedToday,
                "battery_discharged_today": system.batteryDischargedToday,
                "net_flow_today":           system.netFlowToday,
            ])
        }

        let payload: [String: Any] = [
            "date": date,
            "site": [
                "production_today":  metrics.productionToday,
                "consumption_today": metrics.consumptionToday,
                "grid_import_today": metrics.gridImportToday,
                "grid_export_today": metrics.gridExportToday,
                "net_flow_today":    metrics.netFlowToday,
            ],
            "systems": systemValues,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
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
