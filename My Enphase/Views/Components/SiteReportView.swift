//
//  SiteReportView.swift
//  My Enphase
//
//  Site-level energy report component
//

import SwiftUI

// MARK: - Shared constants

// Approximate character count that fills the content area at 16pt monospace on a
// standard device. Used for both separator lines and the equals-sign header bars.
let reportLineWidth = 37

// MARK: - Shared section header (used by both SiteReportView and SystemsReportView)

struct ReportSectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(repeating: "-", count: reportLineWidth))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }
}

// MARK: - Shared icon source type

enum IconSource {
    case system(String)
    case asset(String)
}

// MARK: - Site Report View

struct SiteReportView: View {
    let metrics: SiteMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReportSectionHeader(title: "SITE ENERGY REPORT")

            VStack(spacing: 4) {
                NetFlowRow(label: "Net Flow:", value: metrics.netFlowToday)

                MetricRow(label: "Produced:", value: metrics.productionToday,
                          color: AppColors.production, iconSource: .system("sun.max.fill"))

                MetricRow(label: "Consumed:", value: metrics.consumptionToday,
                          color: AppColors.consumption, iconSource: .asset("plug"))

                MetricRow(label: "Imported:", value: metrics.gridImportToday,
                          color: AppColors.gridImport, iconSource: .system("arrow.down.circle.fill"))

                MetricRow(label: "Exported:", value: metrics.gridExportToday,
                          color: AppColors.gridExport, iconSource: .system("arrow.up.circle.fill"))
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
    let value: Double?
    let color: Color
    let iconSource: IconSource?
    var iconColor: Color? = nil

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

            Text(" " + label)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 103, alignment: .leading)

            Text(formatEnergy(value))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(value != nil ? color : .gray)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatEnergy(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f kWh", v)
    }
}

// MARK: - Net Flow Row

struct NetFlowRow: View {
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

            Text(" " + label)
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 103, alignment: .leading)

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
                .padding(.leading, 16)
            } else {
                Text("—")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.leading, 16)
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(value.map { $0 >= 0 ? AppColors.gridImportBackground : AppColors.gridExportBackground } ?? Color.clear)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flowColor: Color {
        guard let value else { return .gray }
        return value >= 0 ? AppColors.gridImport : AppColors.gridExport
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
