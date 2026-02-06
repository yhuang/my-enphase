//
//  ConfigManager.swift
//  Enphase Monitor App
//
//  Configuration management with UserDefaults persistence
//

import Foundation
import Combine

class ConfigManager: ObservableObject {
    private let configKey = "enphase_app_config"
    
    @Published var config: AppConfig {
        didSet {
            saveConfig()
        }
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
    
    func isConfigured() -> Bool {
        return !config.api.apiKey.isEmpty &&
               !config.api.clientID.isEmpty &&
               !config.api.clientSecret.isEmpty &&
               !config.api.refreshToken.isEmpty &&
               !config.systems.isEmpty
    }
    
    func updateAPIConfig(
        apiKey: String,
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) {
        config.api.apiKey = apiKey
        config.api.clientID = clientID
        config.api.clientSecret = clientSecret
        config.api.refreshToken = refreshToken
    }
    
    func addSystem(id: String, name: String) {
        let newSystem = SystemConfig(id: id, name: name)
        config.systems.append(newSystem)
    }
    
    func removeSystem(at index: Int) {
        guard index < config.systems.count else { return }
        config.systems.remove(at: index)
    }
    
    func clearConfig() {
        config = .empty
    }
}
