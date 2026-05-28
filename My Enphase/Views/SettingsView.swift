//
//  SettingsView.swift
//  My Enphase
//
//  Configuration and settings screen
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var siteDataService: SiteDataService
    @Environment(\.dismiss) var dismiss


    @State private var apiKey = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var refreshToken = ""
    @State private var showingAddSystem = false

    var body: some View {
        NavigationStack {
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
                    ForEach(configManager.config.systems) { system in
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
                                configManager.removeSystem(id: system.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Button {
                        showingAddSystem = true
                    } label: {
                        Label("Add System", systemImage: "plus.circle.fill")
                    }
                }
                .headerProminence(.increased)

                Section {
                    Button("Clear Cache") {
                        // Clear report cache synchronously first so the next fetch
                        // doesn't serve stale data while the HTTP cache clear is pending.
                        siteDataService.clearReportCache()
                        Task { await Cache.shared.clearCache() }
                    }

                    Button("Clear All Data", role: .destructive) {
                        configManager.clearConfig()
                        siteDataService.clearReportCache()
                        Task { await Cache.shared.clearCache() }
                        loadCurrentConfig()
                    }
                }

                #if DEBUG
                Section(header: Text("Developer")) {
                    Button("Export Test Fixtures") {
                        guard let metrics = siteDataService.metrics else { return }
                        FixtureRecorder.record(config: configManager.config, metrics: metrics)
                    }
                    .disabled(siteDataService.metrics == nil)
                    .foregroundColor(siteDataService.metrics == nil ? .secondary : .blue)

                    if let metrics = siteDataService.metrics {
                        Text("Will record \(metrics.systems.count) system(s) for \(Self.isoPrefix(from: metrics.timestamp))")
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
                        // Only persist credentials if all four fields are non-empty,
                        // preventing accidental erasure when a user taps Done without
                        // intending to change credentials.
                        if credentialsAreComplete {
                            saveConfiguration()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddSystem) {
                AddSystemView(onSave: { id, name in
                    configManager.addSystem(id: id, name: name)
                    showingAddSystem = false
                })
            }
            .onAppear {
                loadCurrentConfig()
            }
        }
    }

    private var credentialsAreComplete: Bool {
        !apiKey.isEmpty && !clientID.isEmpty && !clientSecret.isEmpty && !refreshToken.isEmpty
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

    #if DEBUG
    private static let isoFormatter = ISO8601DateFormatter()

    private static func isoPrefix(from date: Date) -> String {
        String(isoFormatter.string(from: date).prefix(10))
    }
    #endif
}

// MARK: - Add System View

struct AddSystemView: View {
    let onSave: (_ id: String, _ name: String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var systemID = ""
    @State private var systemName = ""


    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("System Information")) {
                    TextField("System ID", text: $systemID)
                        .keyboardType(.numberPad)

                    TextField("System Name", text: $systemName)
                }

                Section {
                    Button("Add System") {
                        guard isInputValid else { return }
                        onSave(systemID, systemName)
                        dismiss()
                    }
                    .disabled(!isInputValid)
                }
            }
            .navigationTitle("Add System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        systemID = ""
                        systemName = ""
                        dismiss()
                    }
                }
            }
        }
    }

    private var isInputValid: Bool {
        !systemID.isEmpty && !systemName.isEmpty && Int(systemID) != nil
    }
}

#Preview {
    SettingsView(configManager: ConfigManager(), siteDataService: SiteDataService())
}
