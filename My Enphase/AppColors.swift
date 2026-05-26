//
//  AppColors.swift
//  My Enphase
//
//  Centralised color palette for the entire app.
//

import SwiftUI

// MARK: - Color(hex:) initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            assertionFailure("Invalid hex color string: '\(hex)' — must be 3, 6, or 8 hex digits")
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App palette
enum AppColors {
    // Grid Import (energy drawn from the utility grid)
    static let gridImport           = Color(hex: "FF50B1")
    static let gridImportBackground = Color(hex: "010364")

    // Grid Export (energy pushed to the utility grid)
    static let gridExport           = Color(hex: "00DBD9")
    static let gridExportBackground = Color(hex: "720066")

    // Individual metric categories
    static let production  = Color.yellow
    static let consumption = Color.orange
    static let battery     = Color(hex: "7acf38")

    // Brand / splash colors
    static let brandOrange = Color(hex: "f37320")
    static let brandBlue   = Color(hex: "06b6de")
}
