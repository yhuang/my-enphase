//
//  EnphaseModels.swift
//  Enphase Monitor App
//
//  Data models for Enphase energy metrics
//

import Foundation

// MARK: - Query Types
enum QueryType: String, Codable {
    case day
    case month
    case year
}

// MARK: - System Metrics
struct SystemMetrics: Identifiable, Codable {
    let id: String
    let name: String
    let productionToday: Double
    let consumptionToday: Double
    let batterySOC: Int
    let gridImportToday: Double
    let gridExportToday: Double
    let batteryChargedToday: Double
    let batteryDischargedToday: Double
    let netImportedToday: Double
    
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
        case netImportedToday = "net_imported_today"
    }
}

// MARK: - Aggregated Metrics
struct AggregatedMetrics: Codable {
    let timestamp: Date
    let queryDate: Date
    let queryType: QueryType
    let productionToday: Double
    let consumptionToday: Double
    let gridImportToday: Double
    let gridExportToday: Double
    let netImportToday: Double
    let systems: [SystemMetrics]
    let cacheUsed: Bool
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case queryDate = "query_date"
        case queryType = "query_type"
        case productionToday = "production_today"
        case consumptionToday = "consumption_today"
        case gridImportToday = "grid_import_today"
        case gridExportToday = "grid_export_today"
        case netImportToday = "net_import_today"
        case systems
        case cacheUsed = "cache_used"
    }
}

// MARK: - Configuration Models
struct SystemConfig: Identifiable, Codable {
    let id: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

struct APIConfig: Codable {
    var apiKey: String
    var clientID: String
    var clientSecret: String
    var refreshToken: String
    var authorizationURL: String
    var redirectURI: String
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case authorizationURL = "authorization_url"
        case redirectURI = "redirect_uri"
    }
    
    static var empty: APIConfig {
        APIConfig(
            apiKey: "",
            clientID: "",
            clientSecret: "",
            refreshToken: "",
            authorizationURL: "https://api.enphaseenergy.com/oauth/token",
            redirectURI: "enphase-monitor://callback"
        )
    }
}

struct AppConfig: Codable {
    var api: APIConfig
    var systems: [SystemConfig]
    var refreshInterval: Int
    var timezone: String
    
    enum CodingKeys: String, CodingKey {
        case api
        case systems
        case refreshInterval = "refresh_interval"
        case timezone
    }
    
    static var empty: AppConfig {
        AppConfig(
            api: .empty,
            systems: [],
            refreshInterval: 3600,
            timezone: "US/Pacific"
        )
    }
}
