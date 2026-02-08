//
//  Enphase_Monitor_AppApp.swift
//  Enphase Monitor App
//
//  Created by Jimmy Huang on 2/5/26.
//

import SwiftUI

@main
struct Enphase_Monitor_AppApp: App {
    init() {
        // Set black background for launch screen
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.backgroundColor = .black
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
