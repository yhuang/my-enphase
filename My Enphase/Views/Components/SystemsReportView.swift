//
//  SystemsReportView.swift
//  My Enphase
//
//  Per-system energy report component
//

import SwiftUI

struct SystemsReportView: View {
    let systems: [SystemMetrics]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReportSectionHeader(title: "SYSTEMS REPORT")

            ForEach(systems.indices, id: \.self) { i in
                SystemCardView(displayNumber: i + 1, system: systems[i])
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
    let displayNumber: Int
    let system: SystemMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("[\(displayNumber)]")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.orange)

                Text(system.name)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text(" (\(system.id))")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
            }

            // Indented to clear the "[N] " prefix (3 chars × ~9.6pt/char ≈ 29pt → 30pt)
            VStack(spacing: 3) {
                SystemNetFlowRow(label: "Net Flow", value: system.netFlowToday)

                SystemMetricRow(label: "Produced", value: system.productionToday,
                                color: AppColors.production, iconSource: .system("sun.max.fill"))

                SystemMetricRow(label: "Consumed", value: system.consumptionToday,
                                color: AppColors.consumption, iconSource: .asset("plug"))

                SystemMetricRow(label: "Imported", value: system.gridImportToday,
                                color: AppColors.gridImport, iconSource: .system("arrow.down.circle.fill"))

                SystemMetricRow(label: "Exported", value: system.gridExportToday,
                                color: AppColors.gridExport, iconSource: .system("arrow.up.circle.fill"))

                SystemMetricRow(label: "Charged", value: system.batteryChargedToday,
                                color: AppColors.battery, iconSource: .system("battery.100percent.bolt"),
                                iconVerticalScale: 1.50)

                SystemMetricRow(label: "Discharged", value: system.batteryDischargedToday,
                                color: AppColors.battery, iconSource: .system("battery.0percent"),
                                iconVerticalScale: 1.50)

                // SOC is formatted as an integer percentage rather than kWh.
                SystemMetricRow(label: "Percent",
                                valueText: system.batterySOC.map { String(format: "%d%%", $0) },
                                color: AppColors.battery,
                                iconSource: .system("battery.100percent"),
                                iconVerticalScale: 1.50)
            }
            .padding(.leading, 30)
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
    var value: Double? = nil
    var valueText: String? = nil
    let color: Color
    let iconSource: IconSource?
    var iconColor: Color? = nil
    var iconVerticalScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let source = iconSource {
                    switch source {
                    case .system(let name):
                        Image(systemName: name)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .scaleEffect(x: 1.0, y: iconVerticalScale)
                            .foregroundColor(iconColor ?? color)
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundColor(iconColor ?? color)
                    }
                }
            }
            .frame(width: 20, alignment: .center)

            Text(" \(label):")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 143, alignment: .leading)

            Text(displayValue)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(displayColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displayValue: String {
        if let text = valueText { return text }
        guard let v = value else { return "—" }
        return String(format: "%.1f kWh", v)
    }

    private var displayColor: Color {
        if valueText != nil { return color }
        return value != nil ? color : .gray
    }
}

// MARK: - System Net Flow Row

struct SystemNetFlowRow: View {
    let label: String
    let value: Double?

    var body: some View {
        let flowColor = self.flowColor
        HStack(spacing: 0) {
            Image("net-flow")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundColor(flowColor)
                .frame(width: 20, alignment: .center)

            Text(" \(label):")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 143, alignment: .leading)

            if let value {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f kWh ", abs(value)))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(flowColor)

                    Image(systemName: value >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundColor(flowColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("—")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var flowColor: Color {
        guard let value else { return .gray }
        return value >= 0 ? AppColors.gridImport : AppColors.gridExport
    }
}

#Preview {
    SystemsReportView(
        systems: [
            SystemMetrics(
                id: "5525881",
                name: "Main House",
                productionToday: 14.6,
                consumptionToday: 32.1,
                batterySOC: 63,
                gridImportToday: 23.1,
                gridExportToday: 3.8,
                batteryChargedToday: 8.5,
                batteryDischargedToday: 6.8,
                netFlowToday: 19.3
            ),
            SystemMetrics(
                id: "5392556",
                name: "Garage",
                productionToday: 18.9,
                consumptionToday: 16.4,
                batterySOC: 74,
                gridImportToday: 7.5,
                gridExportToday: 7.6,
                batteryChargedToday: 8.1,
                batteryDischargedToday: 5.4,
                netFlowToday: -0.1
            )
        ]
    )
}
