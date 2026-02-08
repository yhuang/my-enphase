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
            if statusCode == 401 && message.contains("invalid_client") {
                return "Authentication failed: Client ID and Client Secret don't match.\n\nPlease verify:\n• Client ID is correct\n• Client Secret matches the Client ID\n• Credentials are from the same Enphase app"
            }
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
    let enwh: Double? // Energy values should be Double
}

struct BatterySOC: Codable {
    let percent: Double
    let devicesReporting: Int?
    
    enum CodingKeys: String, CodingKey {
        case percent
        case devicesReporting = "devices_reporting"
    }
}

struct TelemetryInterval: Codable {
    let endAt: Int
    let devicesReporting: Int?
    let whDel: Double?      // Energy values should be Double
    let whRec: Double?      // Energy values should be Double
    let enwh: Double?       // Energy values should be Double
    let whImported: Double? // For grid import endpoints (maps to wh_imported JSON key)
    let whExported: Double? // For grid export endpoints (maps to wh_exported JSON key)
    let soc: BatterySOC?    // Battery state of charge object
    let charge: BatteryMetrics?
    let discharge: BatteryMetrics?
    
    enum CodingKeys: String, CodingKey {
        case endAt = "end_at"
        case devicesReporting = "devices_reporting"
        case whDel = "wh_del"
        case whRec = "wh_rec"
        case enwh
        case whImported = "wh_imported"
        case whExported = "wh_exported"
        case soc
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
    private let session: URLSession
    @Published var currentAccessToken: String?
    private var accessTokenExpiry: Date?
    
    init() {
        // Configure URLSession with proper timeouts and connection limits
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        session.invalidateAndCancel()
    }
    
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
        
        // URL encode the refresh token to handle special characters
        guard let encodedRefreshToken = config.refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        
        // Only send grant_type and refresh_token in body (NOT client_id/client_secret)
        let bodyParams = [
            "grant_type=refresh_token",
            "refresh_token=\(encodedRefreshToken)"
        ].joined(separator: "&")
        
        request.httpBody = bodyParams.data(using: .utf8)
        
        do {
            let (data, response) = try await session.data(for: request)
            
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
        // URL encode the API key to handle special characters
        guard let encodedApiKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        
        // API key must be in URL parameters, not headers
        let separator = endpoint.contains("?") ? "&" : "?"
        let urlString = "\(baseURL)/\(endpoint)\(separator)key=\(encodedApiKey)"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        // Check cache first
        print("🔍 Checking cache for URL: \(urlString.prefix(100))...")
        if let cached = APICache.shared.getCachedResponse(for: urlString) {
            do {
                // Try to decode cached data
                let decoded = try JSONDecoder().decode(T.self, from: cached.data)
                print("✅ Using cached response")
                return decoded
            } catch {
                // Cache contains invalid data - clear it and fetch fresh
                print("⚠️ Cache data invalid, fetching fresh: \(error)")
                APICache.shared.clearCache(for: urlString)
            }
        } else {
            print("🌐 No valid cache, making live API request")
        }
        
        // Make live API request
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await session.data(for: request)
            
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
                    
                    // Store in cache before decoding
                    let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, header in
                        if let key = header.key as? String, let value = header.value as? String {
                            result[key] = value
                        }
                    }
                    APICache.shared.cacheResponse(
                        for: urlString,
                        data: data,
                        statusCode: httpResponse.statusCode,
                        headers: headers
                    )
                    
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
        
        print("📡 Production API: start=\(startTimestamp) (\(startDate)), end=\(endTimestamp) (\(endDate)), duration=\(endTimestamp-startTimestamp)s")
        
        let endpoint = "systems/\(systemID)/telemetry/production_meter?start_at=\(startTimestamp)&end_at=\(endTimestamp)"
        
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
        
        print("📡 Battery API: start=\(startTimestamp), end=\(endTimestamp), duration=\(endTimestamp-startTimestamp)s")
        
        let endpoint = "systems/\(systemID)/telemetry/battery?start_at=\(startTimestamp)&end_at=\(endTimestamp)"
        
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
        
        print("📡 Consumption API: start=\(startTimestamp), end=\(endTimestamp), duration=\(endTimestamp-startTimestamp)s")
        
        let endpoint = "systems/\(systemID)/telemetry/consumption_meter?start_at=\(startTimestamp)&end_at=\(endTimestamp)"
        
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
        
        print("📡 Grid Import API: start=\(startTimestamp), end=\(endTimestamp), duration=\(endTimestamp-startTimestamp)s")
        
        let endpoint = "systems/\(systemID)/energy_import_telemetry?start_at=\(startTimestamp)&end_at=\(endTimestamp)"
        
        struct ImportResponse: Codable {
            let intervals: [[TelemetryInterval]]
        }
        
        let response: ImportResponse = try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
        print("📊 Grid Import Response: \(response.intervals.count) nested arrays, total intervals: \(response.intervals.flatMap { $0 }.count)")
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
        
        print("📡 Grid Export API: start=\(startTimestamp), end=\(endTimestamp), duration=\(endTimestamp-startTimestamp)s")
        
        let endpoint = "systems/\(systemID)/energy_export_telemetry?start_at=\(startTimestamp)&end_at=\(endTimestamp)"
        
        struct ExportResponse: Codable {
            let intervals: [[TelemetryInterval]]
        }
        
        let response: ExportResponse = try await makeRequest(endpoint: endpoint, accessToken: accessToken, apiKey: config.apiKey)
        print("📊 Grid Export Response: \(response.intervals.count) nested arrays, total intervals: \(response.intervals.flatMap { $0 }.count)")
        return response.intervals
    }
    
    // MARK: - Helper Methods
    func calculateDailyTotal(from intervals: [TelemetryInterval], field: KeyPath<TelemetryInterval, Double?>) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval[keyPath: field] ?? 0)
        }
        let kWh = total / 1000.0
        print("  📈 Raw total: \(total) Wh = \(kWh) kWh from \(intervals.count) intervals")
        if intervals.count > 0 {
            let sample = intervals.prefix(3).map { interval -> String in
                let value = interval[keyPath: field] ?? 0
                return "\(value)Wh"
            }.joined(separator: ", ")
            print("  📋 Sample values: \(sample)")
        }
        return kWh
    }
    
    func calculateDailyTotalFromNested(from nestedIntervals: [[TelemetryInterval]], field: KeyPath<TelemetryInterval, Double?>) -> Double {
        let flatIntervals = nestedIntervals.flatMap { $0 }
        let total = calculateDailyTotal(from: flatIntervals, field: field)
        print("📊 Calculated total from \(flatIntervals.count) intervals: \(total) kWh")
        for (idx, interval) in flatIntervals.prefix(3).enumerated() {
            print("  Sample interval \(idx): whImported=\(interval.whImported ?? -1), whExported=\(interval.whExported ?? -1), enwh=\(interval.enwh ?? -1)")
        }
        return total
    }
    
    func calculateBatteryCharged(from intervals: [TelemetryInterval]) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval.charge?.enwh ?? 0)
        }
        return total / 1000.0 // Convert Wh to kWh
    }
    
    func calculateBatteryDischarged(from intervals: [TelemetryInterval]) -> Double {
        let total = intervals.reduce(0) { sum, interval in
            sum + (interval.discharge?.enwh ?? 0)
        }
        return total / 1000.0 // Convert Wh to kWh
    }
}
