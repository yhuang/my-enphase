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
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(repeating: "-", count: 37))
                    .font(.system(size: 16, design: .monospaced))
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
                .padding(.vertical, 1)
            }
        }
        .padding(.top, 4)
        .padding(.bottom)
        .padding(.leading, 16)
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
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.orange)
                
                Text(system.name)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(" (\(system.id))")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            // Metrics
            VStack(spacing: 3) {
                SystemMetricRow(
                    label: "Import",
                    value: system.gridImportToday,
                    color: .pink
                )
                
                SystemMetricRow(
                    label: "Export",
                    value: system.gridExportToday,
                    color: .cyan
                )
                
                SystemMetricRow(
                    label: "Produced",
                    value: system.productionToday,
                    color: .yellow,
                    icon: "sun.max.fill",
                    iconColor: .yellow
                )
                
                SystemNetFlowRow(
                    label: "Net Grid Flow",
                    value: system.netImportedToday
                )
                
                SystemMetricRow(
                    label: "Charged",
                    value: system.batteryChargedToday,
                    color: Color(hex: "7acf38"),
                    icon: "battery.100percent.bolt",
                    iconColor: Color(hex: "7acf38")
                )
                
                SystemMetricRow(
                    label: "Discharged",
                    value: system.batteryDischargedToday,
                    color: Color(hex: "7acf38"),
                    icon: "battery.0percent",
                    iconColor: Color(hex: "7acf38")
                )
                
                // Battery SOC (only for day queries)
                if showBatterySOC {
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.100percent")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "7acf38"))
                            Text("Percent:")
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .frame(width: 163, alignment: .leading)
                        
                        Text("  ")
                        
                        Text(String(format: "%d%%", system.batterySOC))
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(Color(hex: "7acf38"))
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
    }
}

// MARK: - System Metric Row
struct SystemMetricRow: View {
    let label: String
    let value: Double
    let color: Color
    var icon: String? = nil
    var iconColor: Color? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(iconColor ?? .white)
                }
                Text(label + ":")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 163, alignment: .leading)
            
            Text("  ")
            
            Text(String(format: "%.1f kWh", value))
                .font(.system(size: 16, design: .monospaced))
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
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 163, alignment: .leading)
            
            Text("  ")
            
            HStack(spacing: 4) {
                Text(String(format: "%.1f kWh ", abs(value)))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(value >= 0 ? .pink : .cyan)
                
                Image(systemName: value >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(value >= 0 ? .pink : .cyan)
            }
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
