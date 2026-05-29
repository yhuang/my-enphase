//
//  EnphaseAPIClient.swift
//  My Enphase
//
//  API Client for Enphase Enlighten Cloud API v4
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case authenticationRequired
    case apiBudgetExhausted(waitSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, let message):
            if statusCode == 401 {
                if message == "invalid_client" {
                    return "Authentication failed: Client ID and Client Secret don't match.\n\nPlease verify:\n• Client ID is correct\n• Client Secret matches the Client ID\n• Credentials are from the same Enphase app"
                } else {
                    return "Authentication failed (HTTP 401). Please check your API credentials and refresh token."
                }
            }
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "Data decoding error: \(error.localizedDescription)"
        case .authenticationRequired:
            return "Authentication required. Please configure OAuth credentials."
        case .apiBudgetExhausted(let waitSeconds):
            return "API Budget exhausted. Please wait \(waitSeconds) seconds."
        }
    }
}

// MARK: - API Response Models

// Energy reading nested inside a battery interval (charge or discharge).
struct BatteryEnergyReading: Codable {
    let energyWh: Double?

    enum CodingKeys: String, CodingKey {
        case energyWh = "enwh"
    }
}

struct BatterySOC: Codable {
    let percent: Double
    let devicesReporting: Int?

    enum CodingKeys: String, CodingKey {
        case percent
        case devicesReporting = "devices_reporting"
    }
}

struct EnergyInterval: Codable {
    let endAt: Int?
    let whDel: Double?
    let enwh: Double?
    let whImported: Double?
    let whExported: Double?
    let soc: BatterySOC?
    let charge: BatteryEnergyReading?
    let discharge: BatteryEnergyReading?

    enum CodingKeys: String, CodingKey {
        case endAt = "end_at"
        case whDel = "wh_del"
        case enwh
        case whImported = "wh_imported"
        case whExported = "wh_exported"
        case soc
        case charge
        case discharge
    }
}

struct IntervalDataResponse: Codable {
    let systemId: Int
    let granularity: String?
    let totalDevices: Int?
    let startAt: Int?
    let endAt: Int?
    let items: String?
    let intervals: [EnergyInterval]

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

// MARK: - OAuth Response
struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    // Enphase may omit refreshToken in the response; retain the existing token if nil.
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// MARK: - API Client

final class EnphaseAPIClient {
    private let baseURL = "https://api.enphaseenergy.com/api/v4"
    private let session: URLSession
    private var currentAccessToken: String?
    private var accessTokenExpiry: Date?

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init() {
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
        if let token = currentAccessToken,
           let expiry = accessTokenExpiry,
           expiry > Date().addingTimeInterval(60) {
            return token
        }

        guard let url = URL(string: config.tokenURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(config.clientID):\(config.clientSecret)"
        if let credentialsData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        guard let encodedRefreshToken = config.refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.authenticationRequired
        }

        let bodyParams = ["grant_type=refresh_token", "refresh_token=\(encodedRefreshToken)"].joined(separator: "&")
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

            let tokenResponse = try Self.decoder.decode(OAuthTokenResponse.self, from: data)
            currentAccessToken = tokenResponse.accessToken
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            return tokenResponse.accessToken
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - API Requests

    private func makeRequest<T: Decodable>(endpoint: String, accessToken: String, apiKey: String) async throws -> T {
        guard let encodedApiKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }

        let separator = endpoint.contains("?") ? "&" : "?"
        let urlString = "\(baseURL)/\(endpoint)\(separator)key=\(encodedApiKey)"

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        DebugLogger.log("🔍 Checking cache for URL: \(urlString.prefix(100))...")
        if let cached = await Cache.shared.getCachedResponse(for: urlString) {
            do {
                let decoded = try Self.decoder.decode(T.self, from: cached.data)
                DebugLogger.log("✅ Using cached response")
                return decoded
            } catch {
                DebugLogger.log("⚠️ Cache data invalid, fetching fresh: \(error)")
                await Cache.shared.clearCache(for: urlString)
            }
        } else {
            DebugLogger.log("🌐 No valid cache, making live API request")
        }

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
                    if let jsonString = String(data: data, encoding: .utf8) {
                        DebugLogger.log("📥 API Response: \(jsonString.prefix(500))")
                    }
                    let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, header in
                        if let key = header.key as? String, let value = header.value as? String {
                            result[key] = value
                        }
                    }
                    await Cache.shared.cacheResponse(for: urlString, data: data, statusCode: httpResponse.statusCode, headers: headers)
                    return try Self.decoder.decode(T.self, from: data)
                } catch {
                    DebugLogger.log("❌ Decoding error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        DebugLogger.log("📄 Raw JSON: \(jsonString)")
                    }
                    throw APIError.decodingError(error)
                }
            case 401:
                // Extract the JSON "error" field for specific error-code matching in errorDescription.
                let errorCode: String
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["error"] as? String {
                    errorCode = code
                } else {
                    errorCode = String(data: data, encoding: .utf8) ?? "Authentication failed"
                }
                throw APIError.httpError(statusCode: 401, message: errorCode)
            case 429:
                let retryAfter: Int
                if let raw = httpResponse.allHeaderFields["Retry-After"] as? String, let parsed = Int(raw) {
                    retryAfter = parsed
                } else {
                    retryAfter = 60
                }
                throw APIError.apiBudgetExhausted(waitSeconds: retryAfter)
            default:
                let rawMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let cleanMessage: String
                if rawMessage.contains("<!DOCTYPE html>") || rawMessage.contains("<html") {
                    cleanMessage = "Server returned error (HTTP \(httpResponse.statusCode))"
                } else {
                    cleanMessage = rawMessage.count > 200 ? String(rawMessage.prefix(200)) + "..." : rawMessage
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: cleanMessage)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Interval Data Fetch Helpers

    private func prepareTimestamps(startDate: Date, endDate: Date) -> (start: Int, end: Int) {
        (Int(startDate.timeIntervalSince1970), Int(endDate.timeIntervalSince1970))
    }

    private struct GridIntervalResponse: Codable {
        let intervals: [[EnergyInterval]]
    }

    // Single private helper that all five public fetch methods delegate to.
    private func fetchIntervalResponse(
        systemID: String,
        endpointPath: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> IntervalDataResponse {
        let accessToken = try await refreshAccessToken(using: config)
        let (start, end) = prepareTimestamps(startDate: startDate, endDate: endDate)
        DebugLogger.log("📡 \(endpointPath): start=\(start), end=\(end), duration=\(end - start)s")
        return try await makeRequest(
            endpoint: "systems/\(systemID)/\(endpointPath)?start_at=\(start)&end_at=\(end)",
            accessToken: accessToken,
            apiKey: config.apiKey
        )
    }

    private func fetchNestedIntervals(
        systemID: String,
        endpointPath: String,
        startDate: Date,
        endDate: Date,
        config: APIConfig
    ) async throws -> [[EnergyInterval]] {
        let accessToken = try await refreshAccessToken(using: config)
        let (start, end) = prepareTimestamps(startDate: startDate, endDate: endDate)
        DebugLogger.log("📡 \(endpointPath): start=\(start), end=\(end), duration=\(end - start)s")
        let response: GridIntervalResponse = try await makeRequest(
            endpoint: "systems/\(systemID)/\(endpointPath)?start_at=\(start)&end_at=\(end)",
            accessToken: accessToken,
            apiKey: config.apiKey
        )
        return response.intervals
    }

    // MARK: - Public Fetch Methods

    func fetchProductionIntervalData(systemID: String, startDate: Date, endDate: Date, config: APIConfig) async throws -> IntervalDataResponse {
        try await fetchIntervalResponse(systemID: systemID, endpointPath: "telemetry/production_meter", startDate: startDate, endDate: endDate, config: config)
    }

    func fetchBatteryIntervalData(systemID: String, startDate: Date, endDate: Date, config: APIConfig) async throws -> IntervalDataResponse {
        try await fetchIntervalResponse(systemID: systemID, endpointPath: "telemetry/battery", startDate: startDate, endDate: endDate, config: config)
    }

    func fetchConsumptionIntervalData(systemID: String, startDate: Date, endDate: Date, config: APIConfig) async throws -> IntervalDataResponse {
        try await fetchIntervalResponse(systemID: systemID, endpointPath: "telemetry/consumption_meter", startDate: startDate, endDate: endDate, config: config)
    }

    func fetchGridImportIntervalData(systemID: String, startDate: Date, endDate: Date, config: APIConfig) async throws -> [[EnergyInterval]] {
        let intervals = try await fetchNestedIntervals(systemID: systemID, endpointPath: "energy_import_telemetry", startDate: startDate, endDate: endDate, config: config)
        DebugLogger.log("📊 Grid Import: \(intervals.count) nested arrays, \(intervals.flatMap { $0 }.count) intervals total")
        return intervals
    }

    func fetchGridExportIntervalData(systemID: String, startDate: Date, endDate: Date, config: APIConfig) async throws -> [[EnergyInterval]] {
        let intervals = try await fetchNestedIntervals(systemID: systemID, endpointPath: "energy_export_telemetry", startDate: startDate, endDate: endDate, config: config)
        DebugLogger.log("📊 Grid Export: \(intervals.count) nested arrays, \(intervals.flatMap { $0 }.count) intervals total")
        return intervals
    }

    // MARK: - Calculation Helpers

    static func calculateDailyTotal(from intervals: [EnergyInterval], field: KeyPath<EnergyInterval, Double?>) -> Double {
        let totalWh = intervals.reduce(0.0) { $0 + ($1[keyPath: field] ?? 0) }
        let kWh = totalWh / 1000.0
        DebugLogger.log("  📈 Raw total: \(totalWh) Wh = \(kWh) kWh from \(intervals.count) intervals")
        return kWh
    }

    static func calculateDailyTotalFromNested(from nestedIntervals: [[EnergyInterval]], field: KeyPath<EnergyInterval, Double?>) -> Double {
        let flat = nestedIntervals.flatMap { $0 }
        let total = calculateDailyTotal(from: flat, field: field)
        DebugLogger.log("📊 Calculated total from \(flat.count) intervals: \(total) kWh")
        return total
    }

    static func calculateBatteryCharged(from intervals: [EnergyInterval]) -> Double {
        intervals.reduce(0.0) { $0 + ($1.charge?.energyWh ?? 0) } / 1000.0
    }

    static func calculateBatteryDischarged(from intervals: [EnergyInterval]) -> Double {
        intervals.reduce(0.0) { $0 + ($1.discharge?.energyWh ?? 0) } / 1000.0
    }
}
