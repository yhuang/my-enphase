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
    
    func fetchMetrics(
        config: AppConfig,
        date: Date = Date(),
        queryType: QueryType = .day
    ) async {
        print("🔄 Starting fetch for \(config.systems.count) systems")
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let calendar = Calendar.current
            let startDate: Date
            let endDate: Date
            
            // Calculate date range based on query type
            switch queryType {
            case .day:
                startDate = calendar.startOfDay(for: date)
                // End date should be current time (not tomorrow) to avoid "date in future" errors
                endDate = min(Date(), calendar.date(byAdding: .day, value: 1, to: startDate)!)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: date)
                startDate = calendar.date(from: components)!
                endDate = min(Date(), calendar.date(byAdding: .month, value: 1, to: startDate)!)
            case .year:
                let components = calendar.dateComponents([.year], from: date)
                startDate = calendar.date(from: components)!
                endDate = min(Date(), calendar.date(byAdding: .year, value: 1, to: startDate)!)
            }
            
            var systemMetrics: [SystemMetrics] = []
            
            // Fetch data for each system
            for system in config.systems {
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
                
                let gridImportIntervals = try await apiClient.fetchGridImportTelemetry(
                    systemID: system.id,
                    startDate: startDate,
                    endDate: endDate,
                    config: config.api
                )
                
                let gridExportIntervals = try await apiClient.fetchGridExportTelemetry(
                    systemID: system.id,
                    startDate: startDate,
                    endDate: endDate,
                    config: config.api
                )
                
                // Calculate metrics using correct fields and endpoints
                let productionTotal = apiClient.calculateDailyTotal(from: production.intervals, field: \.whDel)
                let consumptionTotal = apiClient.calculateDailyTotal(from: consumption.intervals, field: \.enwh)
                let gridImport = apiClient.calculateDailyTotalFromNested(from: gridImportIntervals, field: \.enwh)
                let gridExport = apiClient.calculateDailyTotalFromNested(from: gridExportIntervals, field: \.enwh)
                let batteryCharged = apiClient.calculateBatteryCharged(from: battery.intervals)
                let batteryDischarged = apiClient.calculateBatteryDischarged(from: battery.intervals)
                
                // Get latest battery SOC (last interval)
                let batterySOC = battery.intervals.last?.enwh ?? 0
                
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
                timestamp: Date(),
                queryDate: date,
                queryType: queryType,
                productionToday: totalProduction,
                consumptionToday: totalConsumption,
                gridImportToday: totalGridImport,
                gridExportToday: totalGridExport,
                netImportToday: totalNetImport,
                systems: systemMetrics,
                cacheUsed: false
            )
            
            await MainActor.run {
                self.metrics = aggregated
                self.isLoading = false
            }
            
            print("✅ Fetch completed successfully")
            
        } catch {
            print("❌ Fetch failed: \(error.localizedDescription)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}
