//
//  DebugLogger.swift
//  My Enphase
//
//  Debug-only logging utility to prevent log overflow in production
//

import Foundation

struct DebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
}
