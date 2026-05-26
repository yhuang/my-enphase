//
//  SettingsView.swift
//  Enphase Monitor App
//
//  Configuration and settings screen
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @Environment(\.dismiss) var dismiss
    #if DEBUG
    var currentMetrics: SiteMetrics? = nil
    #endif
    
    @State private var apiKey = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var refreshToken = ""
    @State private var newSystemID = ""
    @State private var newSystemName = ""
    @State private var showingAddSystem = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Credentials")) {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                    
                    TextField("Client ID", text: $clientID)
                        .textContentType(.username)
                    
                    SecureField("Client Secret", text: $clientSecret)
                        .textContentType(.password)
                    
                    SecureField("Refresh Token", text: $refreshToken)
                        .textContentType(.password)
                }
                .headerProminence(.increased)
                
                Section(header: Text("Systems")) {
                    ForEach(Array(configManager.config.systems.enumerated()), id: \.element.id) { index, system in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(system.name)
                                    .font(.headline)
                                Text("ID: \(system.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                configManager.removeSystem(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Button(action: {
                        showingAddSystem = true
                    }) {
                        Label("Add System", systemImage: "plus.circle.fill")
                    }
                }
                .headerProminence(.increased)
                
                Section(header: Text("Configuration")) {
                    HStack {
                        Text("Refresh Interval")
                        Spacer()
                        Text("\(configManager.config.refreshInterval / 60) minutes")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Timezone")
                        Spacer()
                        Text(configManager.config.timezone)
                            .foregroundColor(.secondary)
                    }
                }
                .headerProminence(.increased)
                
                Section {
                    Button("Clear Cache") {
                        // Note: This is handled at SiteDataService level now
                        // Individual API cache is only used as fallback
                        APICache.shared.clearCache()
                    }

                    Button("Clear All Data", role: .destructive) {
                        configManager.clearConfig()
                        APICache.shared.clearCache()
                        loadCurrentConfig()
                    }
                }

                #if DEBUG
                Section(header: Text("Developer")) {
                    Button("Export Test Fixtures") {
                        guard let metrics = currentMetrics else { return }
                        FixtureRecorder.record(config: configManager.config, metrics: metrics)
                    }
                    .disabled(currentMetrics == nil)
                    .foregroundColor(currentMetrics == nil ? .secondary : .blue)

                    if let metrics = currentMetrics {
                        Text("Will record \(metrics.systems.count) system(s) for \(String(ISO8601DateFormatter().string(from: metrics.timestamp).prefix(10)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Load data first, then export fixtures")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Auto-save before closing
                        if !apiKey.isEmpty && !clientID.isEmpty && !clientSecret.isEmpty && !refreshToken.isEmpty {
                            saveConfiguration()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddSystem) {
                AddSystemView(
                    systemID: $newSystemID,
                    systemName: $newSystemName,
                    onSave: {
                        configManager.addSystem(id: newSystemID, name: newSystemName)
                        newSystemID = ""
                        newSystemName = ""
                        showingAddSystem = false
                    }
                )
            }
            .onAppear {
                loadCurrentConfig()
            }
        }
    }
    
    private func loadCurrentConfig() {
        apiKey = configManager.config.api.apiKey
        clientID = configManager.config.api.clientID
        clientSecret = configManager.config.api.clientSecret
        refreshToken = configManager.config.api.refreshToken
    }
    
    private func saveConfiguration() {
        configManager.updateAPIConfig(
            apiKey: apiKey,
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
    }
    
    private func isValid() -> Bool {
        return !apiKey.isEmpty &&
               !clientID.isEmpty &&
               !clientSecret.isEmpty &&
               !refreshToken.isEmpty
    }
}

// MARK: - Add System View
struct AddSystemView: View {
    @Binding var systemID: String
    @Binding var systemName: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("System Information")) {
                    TextField("System ID", text: $systemID)
                        .keyboardType(.numberPad)
                    
                    TextField("System Name", text: $systemName)
                }
                
                Section {
                    Button("Add System") {
                        onSave()
                    }
                    .disabled(systemID.isEmpty || systemName.isEmpty)
                }
            }
            .navigationTitle("Add System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(configManager: ConfigManager())
}
