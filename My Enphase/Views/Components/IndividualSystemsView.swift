//
//  IndividualSystemsView.swift
//  Enphase Monitor App
//
//  Individual systems report component
//

import SwiftUI

struct IndividualSystemsView: View {
    let systems: [SystemMetrics]
    let queryType: QueryType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            VStack(spacing: 2) {
                Text("INDIVIDUAL SYSTEMS REPORT")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(repeating: "-", count: 49))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            
            // Systems
            ForEach(Array(systems.enumerated()), id: \.element.id) { index, system in
                SystemCardView(
                    index: index + 1,
                    system: system,
                    showBatterySOC: queryType == .day
                )
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 4)
        .padding(.bottom)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// MARK: - System Card View
struct SystemCardView: View {
    let index: Int
    let system: SystemMetrics
    let showBatterySOC: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // System Header
            HStack(spacing: 4) {
                Text("[\(index)]")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.orange)
                
                Text(system.name)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(" (\(system.id))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            // Metrics
            VStack(spacing: 3) {
                SystemMetricRow(
                    label: "Imported",
                    value: system.gridImportToday,
                    color: .pink
                )
                
                SystemMetricRow(
                    label: "Exported",
                    value: system.gridExportToday,
                    color: .cyan
                )
                
                SystemMetricRow(
                    label: "Produced",
                    value: system.productionToday,
                    color: .yellow
                )
                
                SystemNetFlowRow(
                    label: "Net Energy Flow",
                    value: system.netImportedToday
                )
                
                SystemMetricRow(
                    label: "Battery Charged",
                    value: system.batteryChargedToday,
                    color: .green
                )
                
                SystemMetricRow(
                    label: "Battery Discharged",
                    value: system.batteryDischargedToday,
                    color: .green
                )
                
                // Battery SOC (only for day queries)
                if showBatterySOC {
                    HStack(spacing: 0) {
                        Text("Battery Percentage:")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 163, alignment: .leading)
                        
                        Text("  ")
                        
                        Text(String(format: "%d%%", system.batterySOC))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                SystemMetricRow(
                    label: "Total Consumed",
                    value: system.consumptionToday,
                    color: .orange
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
    }
}

// MARK: - System Metric Row
struct SystemMetricRow: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 0) {
            Text(label + ":")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 163, alignment: .leading)
            
            Text("  ")
            
            Text(String(format: "%.1f kWh", value))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - System Net Flow Row
struct SystemNetFlowRow: View {
    let label: String
    let value: Double
    
    var body: some View {
        HStack(spacing: 0) {
            Text(label + ":")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 163, alignment: .leading)
            
            Text("  ")
            
            Text(String(format: "%.1f kWh (%@)", abs(value), value >= 0 ? "import" : "export"))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(value >= 0 ? .pink : .cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    IndividualSystemsView(
        systems: [
            SystemMetrics(
                id: "5525881",
                name: "Right Subpanel",
                productionToday: 14.6,
                consumptionToday: 32.1,
                batterySOC: 63,
                gridImportToday: 23.1,
                gridExportToday: 3.8,
                batteryChargedToday: 8.5,
                batteryDischargedToday: 6.8,
                netImportedToday: 19.3
            ),
            SystemMetrics(
                id: "5392556",
                name: "Left Subpanel",
                productionToday: 18.9,
                consumptionToday: 16.4,
                batterySOC: 74,
                gridImportToday: 7.5,
                gridExportToday: 7.6,
                batteryChargedToday: 8.1,
                batteryDischargedToday: 5.4,
                netImportedToday: -0.1
            )
        ],
        queryType: .day
    )
}
