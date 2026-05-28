//
//  SiteDataService.swift
//  My Enphase
//
//  Fetches today's Interval Data for each System at the Site, aggregates per-System
//  totals into SiteMetrics, and manages the Cache and API Budget cooldown.
//

import Foundation
import Combine

// Shared cooldown window: matches the HTTP cache TTL in Cache.swift.
// Changing one without the other would allow stale-but-fresh-looking data.
let apiCooldownTTL: TimeInterval = 60

@MainActor
final class SiteDataService: ObservableObject {
    private let apiClient = EnphaseAPIClient()

    @Published var isLoading = false
    @Published var error: Error?
    @Published var metrics: SiteMetrics?
    @Published var lastUpdated: Date?
    @Published var isFromCache = false

    private let cacheFileURL: URL
    private var currentFetchTask: Task<Void, Never>?
    private var inMemoryCache: (metrics: SiteMetrics, timestamp: Date)?

    // Persisted across cold starts so the API Budget cooldown survives app restarts.
    private var lastAPICallTimestamp: Double {
        get { UserDefaults.standard.double(forKey: "lastAPICallTimestamp") }
        set { UserDefaults.standard.set(newValue, forKey: "lastAPICallTimestamp") }
    }

    private var lastAPICallTime: Date? {
        let t = lastAPICallTimestamp
        return t > 0 ? Date(timeIntervalSinceReferenceDate: t) : nil
    }

    init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_report_cache.json")
    }

    // MARK: - Cache

    func clearReportCache() {
        inMemoryCache = nil
        let url = cacheFileURL
        Task.detached {
            try? FileManager.default.removeItem(at: url)
        }
        DebugLogger.log("💾 Report cache cleared")
    }

    private func loadCachedReport() async -> (metrics: SiteMetrics, timestamp: Date)? {
        if let cached = inMemoryCache { return cached }

        return await Task.detached { [cacheFileURL] () -> (SiteMetrics, Date)? in
            guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
                DebugLogger.log("💾 No cached report file exists")
                return nil
            }
            do {
                let data = try Data(contentsOf: cacheFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let cached = try decoder.decode(CachedReport.self, from: data)
                return (cached.metrics, cached.timestamp)
            } catch {
                DebugLogger.log("💾 ❌ Failed to load cached report: \(error)")
                return nil
            }
        }.value.map { result in
            inMemoryCache = result
            return result
        }
    }

    private func saveCachedReport(_ metrics: SiteMetrics) {
        let cached = CachedReport(metrics: metrics, timestamp: Date())
        inMemoryCache = (cached.metrics, cached.timestamp)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cached) else {
            DebugLogger.log("⚠️ Failed to encode report for caching")
            return
        }
        guard data.count < reportCacheMaxBytes else {
            DebugLogger.log("⚠️ Report too large (\(data.count) bytes) — not caching to disk")
            return
        }
        let url = cacheFileURL
        Task.detached {
            do {
                try data.write(to: url, options: .atomic)
                DebugLogger.log("💾 Report saved to disk (\(data.count) bytes)")
            } catch {
                DebugLogger.log("⚠️ Failed to save report to disk: \(error)")
            }
        }
    }

    // 5 MB — shared threshold with Cache.swift's disk guard.
    private let reportCacheMaxBytes = 5_000_000

    private struct CachedReport: Codable, Sendable {
        let metrics: SiteMetrics
        let timestamp: Date
    }

    // MARK: - Cooldown

    private func isInCooldown() -> Bool {
        guard let lastCall = lastAPICallTime else { return false }
        return Date().timeIntervalSince(lastCall) < apiCooldownTTL
    }

    private func waitForCooldown() async throws {
        guard let lastCall = lastAPICallTime else { return }
        let waitTime = apiCooldownTTL - Date().timeIntervalSince(lastCall)
        guard waitTime > 0 else { return }
        DebugLogger.log("⏳ No cached data available. Waiting \(String(format: "%.1f", waitTime))s for API Budget cooldown...")
        // Propagates CancellationError so the caller can exit cleanly.
        try await Task.sleep(for: .seconds(waitTime))
    }

    // MARK: - Public fetch interface

    /// Initial load: serve fresh cache immediately; wait out cooldown if no cache exists.
    func fetchMetrics(config: AppConfig) async {
        await _fetchMetrics(config: config, cancelPrevious: false)
    }

    /// Pull-to-refresh: cancel any in-flight fetch; serve stale cache if budget exhausted.
    func refreshMetrics(config: AppConfig) async {
        await _fetchMetrics(config: config, cancelPrevious: true)
    }

    private func _fetchMetrics(config: AppConfig, cancelPrevious: Bool) async {
        DebugLogger.log("🔄 fetchMetrics(cancelPrevious: \(cancelPrevious)) at \(Date())")

        if cancelPrevious {
            currentFetchTask?.cancel()
            await currentFetchTask?.value
            currentFetchTask = nil
        }

        if let cached = await loadCachedReport() {
            let dataAge = Date().timeIntervalSince(cached.metrics.timestamp)
            DebugLogger.log("📦 Found cached data, age: \(String(format: "%.1f", dataAge))s (TTL: \(apiCooldownTTL)s)")

            // Fresh-cache short-circuit applies only to the automatic initial load.
            // An explicit pull-to-refresh (cancelPrevious == true) always proceeds to
            // the API as long as the budget cooldown allows it.
            if !cancelPrevious && dataAge < apiCooldownTTL {
                DebugLogger.log("📦 ✅ Cache is fresh — serving without API call")
                metrics = cached.metrics
                lastUpdated = cached.metrics.timestamp
                isFromCache = true
                return
            } else if isInCooldown() {
                DebugLogger.log("📦 ⏳ Cache stale but API Budget exhausted — serving stale cache")
                metrics = cached.metrics
                lastUpdated = cached.metrics.timestamp
                isFromCache = true
                return
            } else {
                DebugLogger.log("📦 ❌ Cache stale — fetching fresh data")
            }
        } else if isInCooldown() {
            if cancelPrevious {
                DebugLogger.log("📦 No cache and budget exhausted — nothing to show")
                return
            }
            do {
                try await waitForCooldown()
            } catch {
                return // task cancelled during cooldown wait
            }
        }

        isFromCache = false
        isLoading = true  // set before yielding so UI shows spinner immediately
        currentFetchTask = Task { await performFetch(config: config) }
        await currentFetchTask?.value
        currentFetchTask = nil
        DebugLogger.log("🔄 performFetch completed")
    }

    // MARK: - Fetch

    private func performFetch(config: AppConfig) async {
        let maxRetries = 2
        var retryCount = 0

        while retryCount <= maxRetries {
            if retryCount == 0 {
                lastAPICallTimestamp = Date().timeIntervalSinceReferenceDate
            }

            DebugLogger.log("🔄 Fetching data for \(config.systems.count) system(s) (attempt \(retryCount + 1)/\(maxRetries + 1))")
            error = nil

            do {
                let calendar = Calendar.current
                let now = Date()
                let startDate = calendar.startOfDay(for: now)
                DebugLogger.log("📅 Today's data: \(startDate) to \(now)")

                var systemMetrics: [SystemMetrics] = []

                for system in config.systems {
                    DebugLogger.log("📍 Fetching system: \(system.name) (\(system.id))")

                    let production = try await apiClient.fetchProductionIntervalData(
                        systemID: system.id, startDate: startDate, endDate: now, config: config.api)
                    let consumption = try await apiClient.fetchConsumptionIntervalData(
                        systemID: system.id, startDate: startDate, endDate: now, config: config.api)
                    let battery = try await apiClient.fetchBatteryIntervalData(
                        systemID: system.id, startDate: startDate, endDate: now, config: config.api)

                    // Grid endpoints are optional — not all systems expose them.
                    var gridImport: Double? = nil
                    var gridExport: Double? = nil

                    do {
                        let intervals = try await apiClient.fetchGridImportIntervalData(
                            systemID: system.id, startDate: startDate, endDate: now, config: config.api)
                        gridImport = EnphaseAPIClient.calculateDailyTotalFromNested(from: intervals, field: \.whImported)
                        DebugLogger.log("✅ Grid import for \(system.name): \(gridImport.map { String($0) } ?? "nil") kWh")
                    } catch {
                        DebugLogger.log("⚠️ Grid import unavailable for \(system.name): \(error.localizedDescription)")
                    }

                    do {
                        let intervals = try await apiClient.fetchGridExportIntervalData(
                            systemID: system.id, startDate: startDate, endDate: now, config: config.api)
                        gridExport = EnphaseAPIClient.calculateDailyTotalFromNested(from: intervals, field: \.whExported)
                        DebugLogger.log("✅ Grid export for \(system.name): \(gridExport.map { String($0) } ?? "nil") kWh")
                    } catch {
                        DebugLogger.log("⚠️ Grid export unavailable for \(system.name): \(error.localizedDescription)")
                    }

                    let productionTotal   = EnphaseAPIClient.calculateDailyTotal(from: production.intervals, field: \.whDel)
                    let consumptionTotal  = EnphaseAPIClient.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
                    let batteryCharged    = EnphaseAPIClient.calculateBatteryCharged(from: battery.intervals)
                    let batteryDischarged = EnphaseAPIClient.calculateBatteryDischarged(from: battery.intervals)
                    let batterySOC        = battery.intervals.last?.soc.map { Int($0.percent) }

                    let netFlow: Double? = (gridImport != nil || gridExport != nil)
                        ? (gridImport ?? 0) - (gridExport ?? 0)
                        : nil

                    DebugLogger.log("📊 \(system.name): prod=\(productionTotal) cons=\(consumptionTotal) soc=\(batterySOC.map(String.init) ?? "nil")%")

                    systemMetrics.append(SystemMetrics(
                        id: system.id,
                        name: system.name,
                        productionToday: productionTotal,
                        consumptionToday: consumptionTotal,
                        batterySOC: batterySOC,
                        gridImportToday: gridImport,
                        gridExportToday: gridExport,
                        batteryChargedToday: batteryCharged > 0 ? batteryCharged : nil,
                        batteryDischargedToday: batteryDischarged > 0 ? batteryDischarged : nil,
                        netFlowToday: netFlow
                    ))
                }

                let totalProduction  = systemMetrics.reduce(0.0) { $0 + $1.productionToday }
                let totalConsumption = systemMetrics.reduce(0.0) { $0 + $1.consumptionToday }
                let totalGridImport  = systemMetrics.reduce(0.0) { $0 + ($1.gridImportToday ?? 0) }
                let totalGridExport  = systemMetrics.reduce(0.0) { $0 + ($1.gridExportToday ?? 0) }
                let hasGridData = systemMetrics.contains { $0.gridImportToday != nil || $0.gridExportToday != nil }
                let totalNetFlow: Double? = hasGridData ? totalGridImport - totalGridExport : nil

                let aggregated = SiteMetrics(
                    timestamp: now,
                    productionToday: totalProduction,
                    consumptionToday: totalConsumption,
                    gridImportToday: hasGridData ? totalGridImport : nil,
                    gridExportToday: hasGridData ? totalGridExport : nil,
                    netFlowToday: totalNetFlow,
                    systems: systemMetrics
                )

                saveCachedReport(aggregated)
                metrics = aggregated
                lastUpdated = now
                isFromCache = false
                isLoading = false
                DebugLogger.log("✅ Fetch completed at \(Date())")
                return

            } catch {
                DebugLogger.log("❌ Fetch failed: \(error.localizedDescription)")

                if let urlError = error as? URLError, urlError.code == .cancelled {
                    DebugLogger.log("⚠️ Request cancelled")
                    if let fallback = await loadCachedReport() {
                        metrics = fallback.metrics
                        lastUpdated = fallback.metrics.timestamp
                        isFromCache = true
                        self.error = nil
                    }
                    isLoading = false
                    return
                }

                if let apiError = error as? APIError, case .apiBudgetExhausted(let waitSeconds) = apiError, retryCount < maxRetries {
                    DebugLogger.log("⏳ API Budget exhausted — waiting \(waitSeconds)s before retry...")
                    lastAPICallTimestamp = Date().timeIntervalSinceReferenceDate
                    do {
                        try? await Task.sleep(for: .seconds(waitSeconds))
                    } catch {
                        isLoading = false
                        return // task cancelled during wait
                    }
                    retryCount += 1
                    continue
                }

                if retryCount >= maxRetries {
                    DebugLogger.log("❌ API Budget retry exhausted after \(maxRetries) attempts")
                }

                if let fallback = await loadCachedReport() {
                    let dataAge = Date().timeIntervalSince(fallback.metrics.timestamp)
                    DebugLogger.log("📦 Using stale cached report as fallback (age: \(String(format: "%.1f", dataAge))s)")
                    metrics = fallback.metrics
                    lastUpdated = fallback.metrics.timestamp
                    isFromCache = true
                    self.error = nil
                    isLoading = false
                    return
                }

                self.error = error
                isLoading = false
                return
            }
        }
    }
}
