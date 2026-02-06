//
//  DashboardView.swift
//  Enphase Monitor App
//
//  Main dashboard displaying energy metrics
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var aggregator = DataAggregator()
    
    @State private var showingSettings = false
    @State private var selectedDate = Date()
    @State private var queryType: QueryType = .day
    
    var body: some View {
        NavigationView {
            VStack {
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
                                await aggregator.fetchMetrics(
                                    config: configManager.config,
                                    date: selectedDate,
                                    queryType: queryType
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    Spacer()
                } else if let metrics = aggregator.metrics {
                    ScrollView {
                        VStack(spacing: 0) {
                            HeaderView(
                                timestamp: metrics.timestamp,
                                queryDate: metrics.queryDate,
                                queryType: metrics.queryType,
                                cacheUsed: metrics.cacheUsed
                            )
                            
                            CombinedReportView(metrics: metrics)
                            
                            if metrics.systems.count > 1 {
                                IndividualSystemsView(
                                    systems: metrics.systems,
                                    queryType: metrics.queryType
                                )
                            }
                        }
                    }
                    .background(Color.black)
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    // Ready state or loading - just show black screen
                    Spacer()
                    if !configManager.isConfigured() {
                        VStack(spacing: 20) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            
                            Text("Welcome to Enphase Monitor")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Tap Settings to configure API credentials")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
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
            .sheet(isPresented: $showingSettings) {
                SettingsView(configManager: configManager)
            }
            .task {
                // Auto-fetch data when view appears if configured
                if configManager.isConfigured() && aggregator.metrics == nil && !aggregator.isLoading {
                    await aggregator.fetchMetrics(
                        config: configManager.config,
                        date: selectedDate,
                        queryType: queryType
                    )
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
