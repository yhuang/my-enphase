//
//  DashboardView.swift
//  My Enphase
//
//  Main dashboard displaying energy metrics
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var siteDataService = SiteDataService()

    @State private var showingSettings = false
    // Snapshot of credentials at sheet-open time; compared on close to detect changes.
    @State private var credentialsAtSheetOpen: APIConfig?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = siteDataService.error {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)

                        Text("Error")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text(error.localizedDescription)
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Retry") {
                            Task { await siteDataService.refreshMetrics(config: configManager.config) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.brandOrange)
                    }
                    Spacer()

                } else if let metrics = siteDataService.metrics {
                    ScrollView {
                        VStack(spacing: 0) {
                            ReportStatsView(
                                timestamp: siteDataService.lastUpdated ?? Date(),
                                isFromCache: siteDataService.isFromCache
                            )
                            SiteReportView(metrics: metrics)
                            Spacer().frame(height: 24)
                            if metrics.systems.count > 1 {
                                SystemsReportView(systems: metrics.systems)
                            }
                        }
                    }
                    .refreshable {
                        await siteDataService.refreshMetrics(config: configManager.config)
                    }
                    .background(Color.black)
                    .ignoresSafeArea(edges: .bottom)

                } else {
                    Spacer()
                    if siteDataService.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppColors.brandOrange)
                    } else if !configManager.isConfigured {
                        VStack(spacing: 20) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 90))
                                .foregroundColor(AppColors.brandOrange)

                            Text("My Enphase")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.brandBlue)

                            Text("Tap Settings to configure API credentials")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ENPHASE SITE MONITOR")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.brandOrange)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        credentialsAtSheetOpen = configManager.config.api
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(configManager: configManager, siteDataService: siteDataService)
            }
            .onChange(of: showingSettings) { _, newValue in
                guard !newValue, configManager.isConfigured else { return }
                // Always re-fetch when credentials changed; otherwise only fetch if no data exists.
                let credentialsChanged = credentialsAtSheetOpen != configManager.config.api
                if credentialsChanged || siteDataService.metrics == nil {
                    Task { await siteDataService.fetchMetrics(config: configManager.config) }
                }
            }
            .task {
                if configManager.isConfigured && siteDataService.metrics == nil && !siteDataService.isLoading {
                    await siteDataService.fetchMetrics(config: configManager.config)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
