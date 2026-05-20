//
//  DataAggregator.swift
//  Enphase Monitor App
//
//  Aggregates energy metrics from multiple Enphase systems
//

import Foundation
import Combine

class DataAggregator: ObservableObject {
    private let apiClient = EnphaseAPIClient()
    
    @Published var isLoading = false
    @Published var error: Error?
    @Published var metrics: AggregatedMetrics?
    @Published var lastUpdated: Date?
    @Published var isFromCache: Bool = false

    private let cacheTTL: TimeInterval = 60 // 60 seconds
    private let cacheFileURL: URL
    private var currentFetchTask: Task<Void, Never>?
    private var inMemoryCache: (metrics: AggregatedMetrics, timestamp: Date)?
    private let saveQueue = DispatchQueue(label: "com.enphase.reportcache", qos: .utility)

    private var lastAPICallTime: Date? {
        get { UserDefaults.standard.object(forKey: "lastAPICallTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastAPICallTime") }
    }
    
    init() {
        // Get cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_report_cache.json")
    }
    
    /// Load cached report — in-memory first, disk fallback for cold starts
    private func loadCachedReport() async -> (metrics: AggregatedMetrics, timestamp: Date)? {
        if let cached = inMemoryCache {
            return cached
        }

        return await Task { [weak self] in
            guard let self else { return nil }
            guard FileManager.default.fileExists(atPath: self.cacheFileURL.path) else {
                DebugLogger.log("💾 No cached report file exists")
                return nil
            }

            do {
                let data = try Data(contentsOf: self.cacheFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let cached = try decoder.decode(CachedReport.self, from: data)
                let result = (cached.metrics, cached.timestamp)
                self.inMemoryCache = result // warm in-memory cache from disk on cold start
                return result
            } catch {
                DebugLogger.log("💾 ❌ Failed to load cached report: \(error)")
                return nil
            }
        }.value
    }
    
    /// Save report to disk (thread-safe with serialization)
    private func saveCachedReport(_ metrics: AggregatedMetrics) {
        // Encode on the calling thread (likely main actor) to avoid concurrency issues
        let cached = CachedReport(metrics: metrics, timestamp: Date())
        inMemoryCache = (cached.metrics, cached.timestamp) // available immediately, before disk write completes
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(cached) else {
            DebugLogger.log("⚠️ Failed to encode report for caching")
            return
        }
        
        // Prevent saving excessively large reports to avoid unbounded disk usage
        guard data.count < 5_000_000 else { // 5 MB safety limit
            DebugLogger.log("⚠️ Report too large (\(data.count) bytes) - not caching to disk")
            return
        }
        
        // Now write to disk on background queue (only I/O happens here)
        saveQueue.async { [weak self, data] in
            guard let self = self else { return }
            do {
                try data.write(to: self.cacheFileURL, options: .atomic)
                DebugLogger.log("💾 Report saved to disk (\(data.count) bytes)")
            } catch {
                DebugLogger.log("⚠️ Failed to save report to disk: \(error)")
            }
        }
    }
    
    private struct CachedReport: Codable, @unchecked Sendable {
        let metrics: AggregatedMetrics
        let timestamp: Date
    }

    private func isInCooldown() -> Bool {
        guard let lastCall = lastAPICallTime else { return false }
        return Date().timeIntervalSince(lastCall) < cacheTTL
    }

    private func waitForCooldown() async {
        guard let lastCall = lastAPICallTime else { return }
        let elapsed = Date().timeIntervalSince(lastCall)
        let waitTime = cacheTTL - elapsed
        guard waitTime > 0 else { return }
        DebugLogger.log("⏳ No cached data available. Waiting \(String(format: "%.1f", waitTime))s for API cooldown to expire...")
        try? await Task.sleep(nanoseconds: UInt64(waitTime) * 1_000_000_000)
    }

    /// Refresh metrics - checks cache staleness first
    func refreshMetrics(config: AppConfig) async {
        DebugLogger.log("🔄 Pull-to-refresh triggered at \(Date())")
        
        // Cancel any existing fetch task and wait for it to complete
        if let existingTask = currentFetchTask {
            DebugLogger.log("⚠️ Cancelling previous fetch task")
            existingTask.cancel()
            await existingTask.value
            currentFetchTask = nil
        }
        
        // Check if cached data is still fresh
        if let cached = await loadCachedReport() {
            let dataAge = Date().timeIntervalSince(cached.metrics.timestamp)
            DebugLogger.log("📦 Found cached data with age: \(String(format: "%.1f", dataAge))s (TTL: \(cacheTTL)s)")
            
            if dataAge < cacheTTL {
                DebugLogger.log("📦 ✅ Cache is still fresh - serving cached data without API call")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                    self.isFromCache = true
                }
                return
            } else if isInCooldown() {
                DebugLogger.log("📦 ⏳ Cache stale but API cooldown active - serving stale cache to avoid 429")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                    self.isFromCache = true
                }
                return
            } else {
                DebugLogger.log("📦 ❌ Cache is STALE - will fetch fresh data from API")
                DebugLogger.log("   Data age: \(String(format: "%.1f", dataAge))s >= TTL: \(cacheTTL)s)")
            }
        } else {
            DebugLogger.log("📦 No cached data found - will fetch fresh data from API")
            if isInCooldown() {
                await waitForCooldown()
            }
        }
        
        // Fetch fresh data using a detached task to prevent cancellation
        DebugLogger.log("🔄 Starting performFetch in detached task...")
        currentFetchTask = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.performFetch(config: config)
        }
        await currentFetchTask?.value
        currentFetchTask = nil  // Clear task reference to prevent memory leak
        DebugLogger.log("🔄 performFetch completed")
    }
    
    func fetchMetrics(config: AppConfig) async {
        // Check if we have cached data first
        if let cached = await loadCachedReport() {
            let dataAge = Date().timeIntervalSince(cached.metrics.timestamp)
            
            // Check if the actual data timestamp is fresh enough
            if dataAge < cacheTTL {
                DebugLogger.log("📦 ✅ Data is fresh (age: \(String(format: "%.1f", dataAge))s < TTL: \(cacheTTL)s) - NO API CALLS")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                    self.isFromCache = true
                }
                return
            } else if isInCooldown() {
                DebugLogger.log("📦 ⏳ Cache stale but API cooldown active - serving stale cache to avoid 429")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                    self.isFromCache = true
                }
                return
            } else {
                DebugLogger.log("📦 ⚠️ Data is stale (age: \(String(format: "%.1f", dataAge))s >= TTL: \(cacheTTL)s) - will fetch fresh data")
            }
        } else if isInCooldown() {
            await waitForCooldown()
        }

        DebugLogger.log("📦 No valid cached report, fetching fresh data from API")
        await performFetch(config: config)
    }
    
    private func performFetch(config: AppConfig, retryCount: Int = 0) async {
        let maxRetries = 2
        if retryCount == 0 {
            lastAPICallTime = Date()
        }
        DebugLogger.log("🔄 Fetching today's data for \(config.systems.count) systems at \(Date()) (attempt \(retryCount + 1)/\(maxRetries + 1))")
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Always fetch today's data (start of day to now)
            let calendar = Calendar.current
            let now = Date()
            let startDate = calendar.startOfDay(for: now)
            let endDate = now
            let duration = Int(endDate.timeIntervalSince(startDate))
            
            DebugLogger.log("📅 Today's data: \(startDate) to \(endDate) (duration: \(duration)s)")
            
            var systemMetrics: [SystemMetrics] = []
            
            // Fetch data for each system
            for system in config.systems {
                DebugLogger.log("📍 Fetching data for system: \(system.name) (\(system.id))")
                
                let production = try await apiClient.fetchTelemetry(
                    systemID: system.id,
                    startDate: startDate,
                    endDate: endDate,
                    config: config.api
                )
                
                let consumption = try await apiClient.fetchConsumptionTelemetry(
                    systemID: system.id,
                    startDate: startDate,
                    endDate: endDate,
                    config: config.api
                )
                
                let battery = try await apiClient.fetchBatteryTelemetry(
                    systemID: system.id,
                    startDate: startDate,
                    endDate: endDate,
                    config: config.api
                )
                
                // Grid import/export may not be available for all systems
                var gridImport: Double = 0
                var gridExport: Double = 0
                
                do {
                    let gridImportIntervals = try await apiClient.fetchGridImportTelemetry(
                        systemID: system.id,
                        startDate: startDate,
                        endDate: endDate,
                        config: config.api
                    )
                    gridImport = apiClient.calculateDailyTotalFromNested(from: gridImportIntervals, field: \.whImported)
                    DebugLogger.log("✅ Grid import for \(system.name): \(gridImport) kWh")
                } catch {
                    DebugLogger.log("⚠️ Grid import not available for \(system.name): \(error.localizedDescription)")
                }
                
                do {
                    let gridExportIntervals = try await apiClient.fetchGridExportTelemetry(
                        systemID: system.id,
                        startDate: startDate,
                        endDate: endDate,
                        config: config.api
                    )
                    gridExport = apiClient.calculateDailyTotalFromNested(from: gridExportIntervals, field: \.whExported)
                    DebugLogger.log("✅ Grid export for \(system.name): \(gridExport) kWh")
                } catch {
                    DebugLogger.log("⚠️ Grid export not available for \(system.name): \(error.localizedDescription)")
                }
                
                // Calculate metrics using correct fields per API documentation
                // Production uses 'wh_del' field from production_meter endpoint
                let productionTotal = apiClient.calculateDailyTotal(from: production.intervals, field: \.whDel)
                DebugLogger.log("📊 Production: \(production.intervals.count) intervals, total: \(productionTotal) kWh")
                // Consumption uses 'enwh' field from consumption_meter endpoint
                let consumptionTotal = apiClient.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
                DebugLogger.log("📊 Consumption: \(consumption.intervals.count) intervals, total: \(consumptionTotal) kWh")
                // Grid import uses 'whImported' field from energy_import_telemetry endpoint
                // Grid export uses 'whExported' field from energy_export_telemetry endpoint
                // Battery charge/discharge from battery endpoint
                let batteryCharged = apiClient.calculateBatteryCharged(from: battery.intervals)
                DebugLogger.log("📊 Battery charged: \(battery.intervals.count) intervals, total: \(batteryCharged) kWh")
                let batteryDischarged = apiClient.calculateBatteryDischarged(from: battery.intervals)
                DebugLogger.log("📊 Battery discharged: \(batteryDischarged) kWh")
                
                // Get latest battery SOC (state of charge percentage) from last interval
                let batterySOC = Int(battery.intervals.last?.soc?.percent ?? 0)
                
                let netImported = gridImport - gridExport
                
                let metric = SystemMetrics(
                    id: system.id,
                    name: system.name,
                    productionToday: productionTotal,
                    consumptionToday: consumptionTotal,
                    batterySOC: batterySOC,
                    gridImportToday: gridImport,
                    gridExportToday: gridExport,
                    batteryChargedToday: batteryCharged,
                    batteryDischargedToday: batteryDischarged,
                    netImportedToday: netImported
                )
                
                systemMetrics.append(metric)
            }
            
            // Aggregate totals
            let totalProduction = systemMetrics.reduce(0) { $0 + $1.productionToday }
            let totalConsumption = systemMetrics.reduce(0) { $0 + $1.consumptionToday }
            let totalGridImport = systemMetrics.reduce(0) { $0 + $1.gridImportToday }
            let totalGridExport = systemMetrics.reduce(0) { $0 + $1.gridExportToday }
            let totalNetImport = totalGridImport - totalGridExport
            
            let aggregated = AggregatedMetrics(
                timestamp: now,
                productionToday: totalProduction,
                consumptionToday: totalConsumption,
                gridImportToday: totalGridImport,
                gridExportToday: totalGridExport,
                netImportToday: totalNetImport,
                systems: systemMetrics
            )
            
            // Save aggregated report to disk
            saveCachedReport(aggregated)
            
            await MainActor.run {
                self.metrics = aggregated
                self.lastUpdated = Date()
                self.isFromCache = false
                self.isLoading = false
            }
            
            DebugLogger.log("📦 Report cached at \(Date())")
            
            DebugLogger.log("✅ Fetch completed successfully at \(Date())")
            
        } catch {
            DebugLogger.log("❌ Fetch failed at \(Date()): \(error.localizedDescription)")
            
            // Check if this is a cancellation error
            if let urlError = error as? URLError, urlError.code == .cancelled {
                DebugLogger.log("⚠️ Request was cancelled - this is likely due to a view update or gesture cancellation")
                // Don't treat cancellation as a hard error - just use cached data if available
                if let fallbackCache = await loadCachedReport() {
                    let dataAge = Date().timeIntervalSince(fallbackCache.metrics.timestamp)
                    DebugLogger.log("📦 Using cached report after cancellation (data age: \(String(format: "%.1f", dataAge))s)")
                    await MainActor.run {
                        self.metrics = fallbackCache.metrics
                        self.lastUpdated = fallbackCache.metrics.timestamp
                        self.isFromCache = true
                        self.isLoading = false
                        self.error = nil
                    }
                    return
                }
            }

            // Check if this is a rate limit error
            if let apiError = error as? APIError,
               case .rateLimitExceeded(let waitSeconds) = apiError {
                if retryCount < maxRetries {
                    DebugLogger.log("⏳ Rate limit hit - waiting \(waitSeconds) seconds before retry (attempt \(retryCount + 1)/\(maxRetries + 1))...")

                    // Wait the specified time
                    try? await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)

                    DebugLogger.log("🔄 Retrying fetch after rate limit wait...")
                    await performFetch(config: config, retryCount: retryCount + 1)
                    return
                } else {
                    DebugLogger.log("❌ Rate limit retry exhausted after \(maxRetries) attempts")
                }
            }
            
            if let apiError = error as? APIError {
                DebugLogger.log("   Error type: \(apiError)")
            }
            
            // For non-rate-limit errors, try to use cached data as fallback
            DebugLogger.log("🔍 Attempting to load ANY cached report as fallback...")
            if let fallbackCache = await loadCachedReport() {
                let dataAge = Date().timeIntervalSince(fallbackCache.metrics.timestamp)
                DebugLogger.log("📦 Using STALE cached report as fallback (data age: \(String(format: "%.1f", dataAge))s)")
                await MainActor.run {
                    self.metrics = fallbackCache.metrics
                    self.lastUpdated = fallbackCache.metrics.timestamp
                    self.isFromCache = true
                    self.isLoading = false
                    self.error = nil  // Clear error since we have cached data
                }
                return
            }
            
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
