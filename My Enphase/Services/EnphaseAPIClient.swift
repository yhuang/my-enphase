//
//  EnphaseAPIClient.swift
//  Enphase Monitor App
//
//  API Client for Enphase Enlighten Cloud API v4
//

import Foundation
import Combine

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case authenticationRequired
    case rateLimitExceeded(waitSeconds: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "Data decoding error: \(error.localizedDescription)"
        case .authenticationRequired:
            return "Authentication required. Please configure OAuth credentials."
        case .rateLimitExceeded(let waitSeconds):
            return "API rate limit exceeded. Please wait \(waitSeconds) seconds."
        }
    }
}

// MARK: - API Response Models
struct BatteryMetrics: Codable {
    let enwh: Int?
}

struct TelemetryInterval: Codable {
    let endAt: Int
    let devicesReporting: Int?
    let whDel: Int?
    let whRec: Int?
    let enwh: Int?
    let charge: BatteryMetrics?
    let discharge: BatteryMetrics?
    
    enum CodingKeys: String, CodingKey {
        case endAt = "end_at"
        case devicesReporting = "devices_reporting"
        case whDel = "wh_del"
        case whRec = "wh_rec"
        case enwh
        case charge
        case discharge
    }
}

struct TelemetryResponse: Codable {
    let systemId: Int
    let granularity: String?
    let totalDevices: Int?
    let startAt: Int?
    let endAt: Int?
    let items: String?
    let intervals: [TelemetryInterval]
    
    enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case granularity
        case totalDevices = "total_devices"
        case startAt = "start_at"
        case endAt = "end_at"
        case items
        case intervals
    }
}

struct EnergyLifetimeResponse: Codable {
    let systemId: String
    let startDate: String
    let production: [Int]
    
    enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case startDate = "start_date"
        case production
    }
}

// MARK: - OAuth Response
struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - API Client
class EnphaseAPIClient: ObservableObject {
    private let baseURL = "https://api.enphaseenergy.com/api/v4"
    @Published var currentAccessToken: String?
    private var accessTokenExpiry: Date?
    
    // MARK: - OAuth Token Management
    func refreshAccessToken(using config: APIConfig) async throws -> String {
        // Check if we have a valid cached token
        if let token = currentAccessToken,
           let expiry = accessTokenExpiry,
           expiry > Date().addingTimeInterval(60) { // 1 minute buffer
            return token
        }
        
        guard let url = URL(string: config.authorizationURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Basic Authentication: base64(client_id:client_secret)
        let credentials = "\(config.clientID):\(config.clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
        
        // Only send grant_type and refresh_token in body (NOT client_id/client_secret)
        let bodyParams = [
            "grant_type=refresh_token",
            "refresh_token=\(config.refreshToken)"
        ].joined(separator: "&")
        
        request.httpBody = bodyParams.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            
            // Cache the token
            await MainActor.run {
                self.currentAccessToken = tokenResponse.accessToken
                self.accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            }
            
            return tokenResponse.accessToken
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - API Requests
    private func makeRequest<T: Decodable>(
        endpoint: String,
        accessToken: String,
        apiKey: String
    ) async throws -> T {
        // API key must be in URL parameters, not headers
        let separator = endpoint.contains("?") ? "&" : "?"
        let urlString = "\(baseURL)/\(endpoint)\(separator)key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200:
                do {
                    // Debug: Print the raw response
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📥 API Response: \(jsonString.prefix(500))")
                    }
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    print("❌ Decoding error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📄 Raw JSON: \(jsonString)")
                    }
                    throw APIError.decodingError(error)
                }
            case 401:
                throw APIError.authenticationRequired
            case 429:
                // Rate limit exceeded
                let waitSeconds = 60 // Default wait time
                throw APIError.rateLimitExceeded(waitSeconds: waitSeconds)
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Fetch System Telemetry
    func fetchTelemetry(
        systemID: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> TelemetryResponse {
        let accessToken = try await refreshAccessToken(using: config)
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        let endpoint = "systems/\(systemID)/telemetry/production_meter?start_at=\(startTimestamp)&end_at=\(endTimestamp)&granularity=15mins"
        
        return try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
    }
    
    // MARK: - Fetch Battery Data
    func fetchBatteryTelemetry(
        systemID: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> TelemetryResponse {
        let accessToken = try await refreshAccessToken(using: config)
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        let endpoint = "systems/\(systemID)/telemetry/battery?start_at=\(startTimestamp)&end_at=\(endTimestamp)&granularity=15mins"
        
        return try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
    }
    
    // MARK: - Fetch Energy Consumption
    func fetchConsumptionTelemetry(
        systemID: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> TelemetryResponse {
        let accessToken = try await refreshAccessToken(using: config)
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        let endpoint = "systems/\(systemID)/telemetry/consumption_meter?start_at=\(startTimestamp)&end_at=\(endTimestamp)&granularity=15mins"
        
        return try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
    }
    
    // MARK: - Fetch Grid Import
    func fetchGridImportTelemetry(
        systemID: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> [[TelemetryInterval]] {
        let accessToken = try await refreshAccessToken(using: config)
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        let endpoint = "systems/\(systemID)/energy_import_telemetry?start_at=\(startTimestamp)&end_at=\(endTimestamp)&granularity=15mins"
        
        struct ImportResponse: Codable {
            let intervals: [[TelemetryInterval]]
        }
        
        let response: ImportResponse = try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
        return response.intervals
    }
    
    // MARK: - Fetch Grid Export
    func fetchGridExportTelemetry(
        systemID: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> [[TelemetryInterval]] {
        let accessToken = try await refreshAccessToken(using: config)
        
        let startTimestamp = Int(startDate.timeIntervalSince1970)
        let endTimestamp = Int(endDate.timeIntervalSince1970)
        
        let endpoint = "systems/\(systemID)/energy_export_telemetry?start_at=\(startTimestamp)&end_at=\(endTimestamp)&granularity=15mins"
        
        struct ExportResponse: Codable {
            let intervals: [[TelemetryInterval]]
        }
        
        let response: ExportResponse = try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
        return response.intervals
    }
    
    // MARK: - Helper Methods
    func calculateDailyTotal(from intervals: [TelemetryInterval], field: KeyPath<TelemetryInterval, Int?>) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval[keyPath: field] ?? 0)
        }
        return Double(total) / 1000.0 // Convert Wh to kWh
    }
    
    func calculateDailyTotalFromNested(from nestedIntervals: [[TelemetryInterval]], field: KeyPath<TelemetryInterval, Int?>) -> Double {
        let flatIntervals = nestedIntervals.flatMap { $0 }
        return calculateDailyTotal(from: flatIntervals, field: field)
    }
    
    func calculateBatteryCharged(from intervals: [TelemetryInterval]) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval.charge?.enwh ?? 0)
        }
        return Double(total) / 1000.0 // Convert Wh to kWh
    }
    
    func calculateBatteryDischarged(from intervals: [TelemetryInterval]) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval.discharge?.enwh ?? 0)
        }
        return Double(total) / 1000.0 // Convert Wh to kWh
    }
}
