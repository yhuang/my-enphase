//
//  DebugLogger.swift
//  My Enphase
//
//  Debug-only logging utility to prevent log overflow in production
//

import Foundation

/// Debug-only logging utility
/// Logs only appear in DEBUG builds; production (RELEASE) builds are silent
struct DebugLogger {
    /// Log a debug message (only in DEBUG builds)
    /// - Parameter message: Autoclosure that returns the log message
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
    
    /// Log with custom prefix/emoji
    /// - Parameters:
    ///   - prefix: Emoji or prefix for the log line
    ///   - message: Autoclosure that returns the log message
    static func log(_ prefix: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        print("\(prefix) \(message())")
        #endif
    }
}
