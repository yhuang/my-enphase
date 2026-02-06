//
//  CombinedReportView.swift
//  Enphase Monitor App
//
//  Combined energy report component
//

import SwiftUI

struct CombinedReportView: View {
    let metrics: AggregatedMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section Header
            VStack(spacing: 2) {
                Text("COMBINED ENERGY REPORT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(repeating: "-", count: 49))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            
            // Metrics
            VStack(spacing: 4) {
                MetricRow(
                    label: "Produced:",
                    value: metrics.productionToday,
                    color: .yellow
                )
                
                MetricRow(
                    label: "Consumed:",
                    value: metrics.consumptionToday,
                    color: .orange
                )
                
                NetFlowRow(
                    label: "Net Energy Flow:",
                    value: metrics.netImportToday
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// MARK: - Metric Row
struct MetricRow: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 123, alignment: .leading)
            
            Text("  ")
            
            Text(String(format: "%.1f kWh", value))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Net Flow Row
struct NetFlowRow: View {
    let label: String
    let value: Double
    
    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 123, alignment: .leading)
            
            Text("  ")
            
            Text(String(format: "%.1f kWh (%@)", abs(value), value >= 0 ? "import" : "export"))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(value >= 0 ? .pink : .cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    CombinedReportView(
        metrics: AggregatedMetrics(
            timestamp: Date(),
            queryDate: Date(),
            queryType: .day,
            productionToday: 33.4,
            consumptionToday: 48.6,
            gridImportToday: 30.6,
            gridExportToday: 11.4,
            netImportToday: 19.2,
            systems: [],
            cacheUsed: false
        )
    )
}
