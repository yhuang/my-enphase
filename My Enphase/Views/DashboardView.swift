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
    /// Incremented on every pull-to-refresh completion (fresh or cached) so
    /// .task(id:) always re-fires and snaps the scroll position back.
    @State private var refreshTrigger = UUID()

    var body: some View {
        // No NavigationStack — this view never pushes a child; the settings screen
        // is a sheet. NavigationStack in iOS 26 auto-promotes top-of-content views
        // into the navigation bar and applies Liquid Glass pill styling to them.
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header bar: full-width, no toolbar styling applied by the OS.
                HStack {
                    Text("ENPHASE SITE MONITOR")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.brandOrange)
                    Spacer()
                    Button(action: {
                        credentialsAtSheetOpen = configManager.config.api
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .frame(height: 44)
                .background(Color.black)

                // Main content area
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ReportStatsView(
                                    timestamp: siteDataService.lastUpdated ?? Date(),
                                    isFromCache: siteDataService.isFromCache
                                )

                                SiteReportView(metrics: metrics)
                                    .id("reportStart")

                                Spacer()
                                    .frame(height: 12)

                                if metrics.systems.count > 1 {
                                    SystemsReportView(systems: metrics.systems)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .refreshable {
                            await siteDataService.refreshMetrics(config: configManager.config)
                            // Always bump the trigger — even cached returns have the
                            // same metrics.timestamp, so we can't rely on that changing.
                            refreshTrigger = UUID()
                        }
                        .background(Color.black)
                        .ignoresSafeArea(edges: .bottom)
                        .task(id: refreshTrigger) {
                            // Fires on first appear and after every refresh (fresh or
                            // cached). 50 ms sleep lets SwiftUI finish layout first.
                            try? await Task.sleep(for: .milliseconds(50))
                            proxy.scrollTo("reportStart", anchor: .top)
                        }
                    }
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
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(configManager: configManager, siteDataService: siteDataService)
        }
        .onChange(of: showingSettings) { _, newValue in
            guard !newValue, configManager.isConfigured else { return }
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

#Preview {
    DashboardView()
}
