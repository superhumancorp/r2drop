// Packages/R2Core/Sources/R2Core/R2Core.swift
// Public re-export of all R2Core types.
// Models, config, queue, and history managers are in separate files.

import Foundation

/// Namespace for R2Core constants.
public enum R2CoreConstants {
    /// Keychain service identifier for R2Drop credentials.
    public static let keychainService = "com.superhumancorp.r2drop"

    /// App Group identifier shared between main app and Finder extension.
    public static let appGroup = "group.com.superhumancorp.r2drop"

    /// URL scheme for deep linking.
    public static let urlScheme = "r2drop"
}
