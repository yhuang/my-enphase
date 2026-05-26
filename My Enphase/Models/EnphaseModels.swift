//
//  EnphaseModels.swift
//  My Enphase
//
//  Data models for Enphase energy metrics
//

import Foundation

// MARK: - System Metrics
struct SystemMetrics: Identifiable, Codable {
    let id: String
    let name: String
    let productionToday: Double
    let consumptionToday: Double
    let batterySOC: Int?
    let gridImportToday: Double?
    let gridExportToday: Double?
    let batteryChargedToday: Double?
    let batteryDischargedToday: Double?
    let netFlowToday: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case productionToday = "production_today"
        case consumptionToday = "consumption_today"
        case batterySOC = "battery_soc"
        case gridImportToday = "grid_import_today"
        case gridExportToday = "grid_export_today"
        case batteryChargedToday = "battery_charged_today"
        case batteryDischargedToday = "battery_discharged_today"
        case netFlowToday = "net_flow_today"
    }
}

// MARK: - Site Metrics
struct SiteMetrics: Codable {
    let timestamp: Date
    let productionToday: Double
    let consumptionToday: Double
    let gridImportToday: Double?
    let gridExportToday: Double?
    let netFlowToday: Double?
    let systems: [SystemMetrics]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case productionToday = "production_today"
        case consumptionToday = "consumption_today"
        case gridImportToday = "grid_import_today"
        case gridExportToday = "grid_export_today"
        case netFlowToday = "net_flow_today"
        case systems
    }
}

// MARK: - Configuration Models
struct SystemConfig: Identifiable, Codable {
    let id: String
    let name: String
}

struct APIConfig: Codable, Equatable {
    var apiKey: String
    var clientID: String
    var clientSecret: String
    var refreshToken: String
    var tokenURL: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case tokenURL = "token_url"
    }

    static var empty: APIConfig {
        APIConfig(
            apiKey: "",
            clientID: "",
            clientSecret: "",
            refreshToken: "",
            tokenURL: "https://api.enphaseenergy.com/oauth/token"
        )
    }
}

struct AppConfig: Codable {
    var api: APIConfig
    var systems: [SystemConfig]

    static var empty: AppConfig {
        AppConfig(api: .empty, systems: [])
    }
}
