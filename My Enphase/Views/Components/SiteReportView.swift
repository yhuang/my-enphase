//
//  SiteReportView.swift
//  Enphase Monitor App
//
//  Site-level energy report component
//

import SwiftUI

struct SiteReportView: View {
    let metrics: SiteMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section Header
            VStack(spacing: 2) {
                Text("SITE ENERGY REPORT")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(String(repeating: "-", count: 37))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            
            // Metrics
            VStack(spacing: 4) {
                NetFlowRow(
                    label: "Net Flow:",
                    value: metrics.netFlowToday
                )
                
                MetricRow(
                    label: "Produced:",
                    value: metrics.productionToday,
                    color: .yellow,
                    icon: "sun.max.fill",
                    iconColor: .yellow
                )
                
                MetricRow(
                    label: "Consumed:",
                    value: metrics.consumptionToday,
                    color: .orange,
                    icon: "plug",
                    iconColor: .orange,
                    isCustomIcon: true
                )

                MetricRow(
                    label: "Imported:",
                    value: metrics.gridImportToday,
                    color: AppColors.gridImport,
                    icon: "arrow.down.circle.fill",
                    iconColor: AppColors.gridImport
                )

                MetricRow(
                    label: "Exported:",
                    value: metrics.gridExportToday,
                    color: AppColors.gridExport,
                    icon: "arrow.up.circle.fill",
                    iconColor: AppColors.gridExport
                )
            }
            .padding(.horizontal)
            .padding(.leading, 10)
        }
        .padding(.vertical)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// MARK: - Metric Row
struct MetricRow: View {
    let label: String
    let value: Double
    let color: Color
    var icon: String? = nil
    var iconColor: Color? = nil
    var isCustomIcon: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let icon = icon {
                    if isCustomIcon {
                        Image(icon)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundColor(iconColor ?? .white)
                    } else {
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundColor(iconColor ?? .white)
                    }
                }
            }
            .frame(width: 20, alignment: .center)

            Text(" " + label)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 103, alignment: .leading)

            Text("  ")
                .font(.system(size: 16, design: .monospaced))

            Text(String(format: "%.1f kWh", value))
                .font(.system(size: 16, design: .monospaced))
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
            // Inner block: tightly wraps all content so the background is end-to-end
            HStack(spacing: 0) {
                Image("net-flow")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundColor(value >= 0 ? AppColors.gridImport : AppColors.gridExport)
                    .frame(width: 20, alignment: .center)

                Text(" " + label)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 103, alignment: .leading)

                Text("  ")
                    .font(.system(size: 16, design: .monospaced))

                HStack(spacing: 4) {
                    Text(String(format: "%.1f kWh ", abs(value)))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(value >= 0 ? AppColors.gridImport : AppColors.gridExport)

                    Image(systemName: value >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundColor(value >= 0 ? AppColors.gridImport : AppColors.gridExport)
                }
            }
            .padding(.horizontal, 10) // 1 monospace space character each side
            .padding(.vertical, 2)
            .background(value >= 0 ? AppColors.gridImportBackground : AppColors.gridExportBackground)

            Spacer()
        }
        .padding(.leading, -10) // shift 1 monospace character left
    }
}

#Preview {
    SiteReportView(
        metrics: SiteMetrics(
            timestamp: Date(),
            productionToday: 33.4,
            consumptionToday: 48.6,
            gridImportToday: 30.6,
            gridExportToday: 11.4,
            netFlowToday: 19.2,
            systems: []
        )
    )
}
