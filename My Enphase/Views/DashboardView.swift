//
//  DashboardView.swift
//  Enphase Monitor App
//
//  Main dashboard displaying energy metrics
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct DashboardView: View {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var aggregator = DataAggregator()
    
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Main content area
                if let error = aggregator.error {
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
                            Task {
                                await aggregator.fetchMetrics(config: configManager.config)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    Spacer()
                } else if let metrics = aggregator.metrics {
                    ScrollView {
                        VStack(spacing: 0) {
                            ReportStatsView(timestamp: aggregator.lastUpdated ?? Date())
                            
                            CombinedReportView(metrics: metrics)
                            
                            if metrics.systems.count > 1 {
                                IndividualSystemsView(systems: metrics.systems, queryType: .day)
                            }
                        }
                    }
                    .refreshable {
                        await aggregator.refreshMetrics(config: configManager.config)
                    }
                    .background(Color.black)
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    // Ready state or loading - just show black screen
                    Spacer()
                    if !configManager.isConfigured() {
                        VStack(spacing: 20) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 90))
                                .foregroundColor(Color(hex: "f37320"))
                            
                            Text("My Enphase")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(Color(hex: "06b6de"))
                            
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
            .edgesIgnoringSafeArea(.all)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ENPHASE MULTI-SYSTEM MONITOR")
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(configManager: configManager)
            }
            .onChange(of: showingSettings) { oldValue, newValue in
                // When settings sheet is dismissed, fetch data if configured
                if !newValue && configManager.isConfigured() && aggregator.metrics == nil {
                    Task {
                        await aggregator.fetchMetrics(config: configManager.config)
                    }
                }
            }
            .task {
                // Auto-fetch data when view appears if configured
                if configManager.isConfigured() && aggregator.metrics == nil && !aggregator.isLoading {
                    await aggregator.fetchMetrics(config: configManager.config)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
