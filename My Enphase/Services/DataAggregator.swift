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
    
    private let cacheTTL: TimeInterval = 60 // 60 seconds
    private let cacheFileURL: URL
    private var currentFetchTask: Task<Void, Never>?
    
    init() {
        // Get cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_report_cache.json")
    }
    
    /// Load cached report from disk if still valid
    private func loadCachedReport() -> (metrics: AggregatedMetrics, timestamp: Date)? {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("💾 No cached report file exists")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let cached = try decoder.decode(CachedReport.self, from: data)
            return (cached.metrics, cached.timestamp)
        } catch {
            print("💾 ❌ Failed to load cached report: \(error)")
            return nil
        }
    }
    
    /// Save report to disk
    private func saveCachedReport(_ metrics: AggregatedMetrics) {
        do {
            let cached = CachedReport(metrics: metrics, timestamp: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cached)
            try data.write(to: cacheFileURL, options: .atomic)
            print("💾 Report saved to disk")
        } catch {
            print("⚠️ Failed to save report to disk: \(error)")
        }
    }
    
    private struct CachedReport: Codable {
        let metrics: AggregatedMetrics
        let timestamp: Date
    }
    
    /// Refresh metrics - checks cache staleness first
    func refreshMetrics(config: AppConfig) async {
        print("🔄 Pull-to-refresh triggered at \(Date())")
        
        // Cancel any existing fetch task
        currentFetchTask?.cancel()
        
        // If already loading, wait for it to complete or cancel
        if isLoading {
            print("⚠️ Already loading, cancelling previous fetch")
            currentFetchTask?.cancel()
            // Give it a moment to cancel
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Check if cached data is still fresh
        if let cached = loadCachedReport() {
            let dataAge = Date().timeIntervalSince(cached.metrics.timestamp)
            print("📦 Found cached data with age: \(String(format: "%.1f", dataAge))s (TTL: \(cacheTTL)s)")
            
            if dataAge < cacheTTL {
                print("📦 ✅ Cache is still fresh - serving cached data without API call")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                }
                return
            } else {
                print("📦 ❌ Cache is STALE - will fetch fresh data from API")
                print("   Data age: \(String(format: "%.1f", dataAge))s >= TTL: \(cacheTTL)s")
            }
        } else {
            print("📦 No cached data found - will fetch fresh data from API")
        }
        
        // Fetch fresh data using a detached task to prevent cancellation
        print("🔄 Starting performFetch in detached task...")
        currentFetchTask = Task.detached { [weak self] in
            guard let self = self else { return }
            await self.performFetch(config: config)
        }
        await currentFetchTask?.value
        print("🔄 performFetch completed")
    }
    
    func fetchMetrics(config: AppConfig) async {
        // Check if we have cached data first
        if let cached = loadCachedReport() {
            let dataAge = Date().timeIntervalSince(cached.metrics.timestamp)
            
            // Check if the actual data timestamp is fresh enough
            if dataAge < cacheTTL {
                print("📦 ✅ Data is fresh (age: \(String(format: "%.1f", dataAge))s < TTL: \(cacheTTL)s) - NO API CALLS")
                await MainActor.run {
                    self.metrics = cached.metrics
                    self.lastUpdated = cached.metrics.timestamp
                }
                return
            } else {
                print("📦 ⚠️ Data is stale (age: \(String(format: "%.1f", dataAge))s >= TTL: \(cacheTTL)s) - clearing cache")
                try? FileManager.default.removeItem(at: cacheFileURL)
            }
        }
        
        print("📦 No valid cached report, fetching fresh data from API")
        await performFetch(config: config)
    }
    
    private func performFetch(config: AppConfig, retryCount: Int = 0) async {
        let maxRetries = 2
        print("🔄 Fetching today's data for \(config.systems.count) systems at \(Date()) (attempt \(retryCount + 1)/\(maxRetries + 1))")
        
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
            
            print("📅 Today's data: \(startDate) to \(endDate) (duration: \(duration)s)")
            
            var systemMetrics: [SystemMetrics] = []
            
            // Fetch data for each system
            for system in config.systems {
                print("📍 Fetching data for system: \(system.name) (\(system.id))")
                
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
                    print("✅ Grid import for \(system.name): \(gridImport) kWh")
                } catch {
                    print("⚠️ Grid import not available for \(system.name): \(error.localizedDescription)")
                }
                
                do {
                    let gridExportIntervals = try await apiClient.fetchGridExportTelemetry(
                        systemID: system.id,
                        startDate: startDate,
                        endDate: endDate,
                        config: config.api
                    )
                    gridExport = apiClient.calculateDailyTotalFromNested(from: gridExportIntervals, field: \.whExported)
                    print("✅ Grid export for \(system.name): \(gridExport) kWh")
                } catch {
                    print("⚠️ Grid export not available for \(system.name): \(error.localizedDescription)")
                }
                
                // Calculate metrics using correct fields per API documentation
                // Production uses 'wh_del' field from production_meter endpoint
                let productionTotal = apiClient.calculateDailyTotal(from: production.intervals, field: \.whDel)
                print("📊 Production: \(production.intervals.count) intervals, total: \(productionTotal) kWh")
                // Consumption uses 'enwh' field from consumption_meter endpoint
                let consumptionTotal = apiClient.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
                print("📊 Consumption: \(consumption.intervals.count) intervals, total: \(consumptionTotal) kWh")
                // Grid import uses 'whImported' field from energy_import_telemetry endpoint
                // Grid export uses 'whExported' field from energy_export_telemetry endpoint
                // Battery charge/discharge from battery endpoint
                let batteryCharged = apiClient.calculateBatteryCharged(from: battery.intervals)
                print("📊 Battery charged: \(battery.intervals.count) intervals, total: \(batteryCharged) kWh")
                let batteryDischarged = apiClient.calculateBatteryDischarged(from: battery.intervals)
                print("📊 Battery discharged: \(batteryDischarged) kWh")
                
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
            let timestamp = Date()
            saveCachedReport(aggregated)
            
            await MainActor.run {
                self.metrics = aggregated
                self.lastUpdated = timestamp
                self.isLoading = false
            }
            
            print("📦 Report cached at \(timestamp)")
            
            print("✅ Fetch completed successfully at \(Date())")
            
        } catch {
            print("❌ Fetch failed at \(Date()): \(error.localizedDescription)")
            
            // Check if this is a cancellation error
            if let urlError = error as? URLError, urlError.code == .cancelled {
                print("⚠️ Request was cancelled - this is likely due to a view update or gesture cancellation")
                // Don't treat cancellation as a hard error - just use cached data if available
                if let fallbackCache = loadCachedReport() {
                    let dataAge = Date().timeIntervalSince(fallbackCache.metrics.timestamp)
                    print("📦 Using cached report after cancellation (data age: \(String(format: "%.1f", dataAge))s)")
                    await MainActor.run {
                        self.metrics = fallbackCache.metrics
                        self.lastUpdated = fallbackCache.metrics.timestamp
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
                    print("⏳ Rate limit hit - waiting \(waitSeconds) seconds before retry (attempt \(retryCount + 1)/\(maxRetries + 1))...")

                    // Wait the specified time
                    try? await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)

                    print("🔄 Retrying fetch after rate limit wait...")
                    await performFetch(config: config, retryCount: retryCount + 1)
                    return
                } else {
                    print("❌ Rate limit retry exhausted after \(maxRetries) attempts")
                }
            }
            
            if let apiError = error as? APIError {
                print("   Error type: \(apiError)")
            }
            
            // For non-rate-limit errors, try to use cached data as fallback
            print("🔍 Attempting to load ANY cached report as fallback...")
            if let fallbackCache = loadCachedReport() {
                let dataAge = Date().timeIntervalSince(fallbackCache.metrics.timestamp)
                print("📦 Using STALE cached report as fallback (data age: \(String(format: "%.1f", dataAge))s)")
                await MainActor.run {
                    self.metrics = fallbackCache.metrics
                    self.lastUpdated = fallbackCache.metrics.timestamp
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
    
    /// Clear cached report
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheFileURL)
        print("📦 Report cache cleared from disk")
    }
}
