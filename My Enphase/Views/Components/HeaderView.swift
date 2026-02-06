//
//  HeaderView.swift
//  Enphase Monitor App
//
//  Header component displaying query information
//

import SwiftUI

struct HeaderView: View {
    let timestamp: Date
    let queryDate: Date
    let queryType: QueryType
    let cacheUsed: Bool
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 4) {
            // Top separator
            Text(String(repeating: "=", count: 49))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Title
            Text("ENPHASE MULTI-SYSTEM MONITOR")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .center)
            
            // Bottom separator
            Text(String(repeating: "=", count: 49))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Query Range
            HStack(spacing: 0) {
                Text("Query Range:")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 120, alignment: .leading)
                
                Text(queryRangeText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            
            // Last Updated
            HStack(spacing: 0) {
                Text("Last Updated:")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 120, alignment: .leading)
                
                HStack(spacing: 0) {
                    Text("\(timeFormatter.string(from: timestamp)) ")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                    +
                    Text(cacheUsed ? "(cached)" : "")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Bottom separator
            Text(String(repeating: "=", count: 49))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
    
    private var queryRangeText: String {
        let calendar = Calendar.current
        
        switch queryType {
        case .day:
            let start = calendar.startOfDay(for: queryDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
                .addingTimeInterval(-1)
            
            return """
            \(dateFormatter.string(from: start)) 12:00 AM
                to
            \(dateFormatter.string(from: end))
            """
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: queryDate)
            let start = calendar.date(from: components)!
            
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM yyyy"
            return monthFormatter.string(from: start)
            
        case .year:
            let components = calendar.dateComponents([.year], from: queryDate)
            let start = calendar.date(from: components)!
            
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return yearFormatter.string(from: start)
        }
    }
}

#Preview {
    HeaderView(
        timestamp: Date(),
        queryDate: Date(),
        queryType: .day,
        cacheUsed: false
    )
}
