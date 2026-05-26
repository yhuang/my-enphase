//
//  ReportStatsView.swift
//  My Enphase
//
//  Report stats component displaying last updated timestamp
//

import SwiftUI

struct ReportStatsView: View {
    let timestamp: Date
    let isFromCache: Bool

    // Static so the formatter is created once for the lifetime of the app.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            Text(String(repeating: "=", count: reportLineWidth))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(AppColors.brandOrange)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                // Both labels are the same width so the timestamp column aligns.
                Text(isFromCache ? "Cached:  " : "Updated: ")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)

                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            Text(String(repeating: "=", count: reportLineWidth))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(AppColors.brandOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .padding(.leading, 16)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

#Preview {
    ReportStatsView(timestamp: Date(), isFromCache: false)
}
