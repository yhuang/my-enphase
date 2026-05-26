//
//  ConfigManager.swift
//  My Enphase
//
//  Configuration management with UserDefaults persistence
//

import Foundation
import Combine

final class ConfigManager: ObservableObject {
    private let configKey = "enphase_app_config"

    @Published var config: AppConfig {
        didSet { saveConfig() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .empty
        }
    }

    private func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }

    var isConfigured: Bool {
        !config.api.apiKey.isEmpty &&
        !config.api.clientID.isEmpty &&
        !config.api.clientSecret.isEmpty &&
        !config.api.refreshToken.isEmpty &&
        !config.systems.isEmpty
    }

    // Assigns all four fields in a single write so didSet fires once.
    func updateAPIConfig(apiKey: String, clientID: String, clientSecret: String, refreshToken: String) {
        var updated = config
        updated.api.apiKey = apiKey
        updated.api.clientID = clientID
        updated.api.clientSecret = clientSecret
        updated.api.refreshToken = refreshToken
        config = updated
    }

    func addSystem(id: String, name: String) {
        config.systems.append(SystemConfig(id: id, name: name))
    }

    func removeSystem(id: String) {
        config.systems.removeAll { $0.id == id }
    }

    func clearConfig() {
        config = .empty
    }
}
