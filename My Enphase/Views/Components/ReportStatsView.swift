//
//  ReportStatsView.swift
//  Enphase Monitor App
//
//  Report stats component displaying last updated timestamp
//

import SwiftUI

struct ReportStatsView: View {
    let timestamp: Date
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 4) {
            Text(String(repeating: "=", count: 37))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Last Updated
            HStack(spacing: 0) {
                Text("Updated:  ")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(timeFormatter.string(from: timestamp))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            Text(String(repeating: "=", count: 37))
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .padding(.leading, 16)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

#Preview {
    ReportStatsView(timestamp: Date())
}
