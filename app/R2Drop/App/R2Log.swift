// R2Drop/App/R2Log.swift
// Debug-only logging utility for R2Drop.
// All log output is compiled out in Release builds via #if DEBUG.
// Uses os.Logger for structured logging with subsystem filtering.

import os

// MARK: - R2Log

/// Lightweight debug logger. All methods are no-ops in Release builds.
/// Usage: `R2Log.debug("message")` or `R2Log.error("something failed: \(err)")`
///
/// Logs can be viewed in Console.app by filtering subsystem "com.superhumancorp.r2drop".
/// Categories: app, menubar, service, upload, network, config, keychain, bridge, ui
enum R2Log {

    // MARK: - Subsystem

    private static let subsystem = "com.superhumancorp.r2drop"

    // MARK: - Loggers (one per category for Console.app filtering)

    static let app      = Logger(subsystem: subsystem, category: "app")
    static let menubar  = Logger(subsystem: subsystem, category: "menubar")
    static let service  = Logger(subsystem: subsystem, category: "service")
    static let upload   = Logger(subsystem: subsystem, category: "upload")
    static let network  = Logger(subsystem: subsystem, category: "network")
    static let config   = Logger(subsystem: subsystem, category: "config")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
    static let bridge   = Logger(subsystem: subsystem, category: "bridge")
    static let ui       = Logger(subsystem: subsystem, category: "ui")

    // MARK: - Convenience (uses "app" category)

    /// Log a debug message. Compiled out in Release builds.
    static func debug(_ message: String) {
        #if DEBUG
        app.debug("\(message, privacy: .public)")
        #endif
    }

    /// Log an info message. Compiled out in Release builds.
    static func info(_ message: String) {
        #if DEBUG
        app.info("\(message, privacy: .public)")
        #endif
    }

    /// Log an error message. Compiled out in Release builds.
    static func error(_ message: String) {
        #if DEBUG
        app.error("\(message, privacy: .public)")
        #endif
    }
}
