// R2Drop/App/Telemetry/TelemetryService.swift
// Main telemetry service — replaces AnalyticsService.
// Wraps PostHog SDK with identity management, common properties, sanitization,
// rate limiting, and error tracking. All telemetry calls are fire-and-forget
// and must never throw or block the UI.

import Foundation
import PostHog
import R2Core
import Security

// MARK: - TelemetryService

/// Central telemetry service for all analytics events.
/// Owns PostHog SDK, session state, common properties, and error tracking.
/// All public methods are safe to call from @MainActor — they never throw.
@MainActor
final class TelemetryService {

    static let shared = TelemetryService()

    // MARK: - PostHog Config

    private static let apiKey = "phc_tyaFmZbyRb9RMbinKc16kWLNmQRwZUlUUIcnvQCdCyU"
    private static let host = "https://us.i.posthog.com"

    // MARK: - Identity

    /// Stable anonymous install ID — persisted in Keychain, survives app updates.
    private(set) var distinctId: String = ""

    /// New UUID each app launch — used as a session identifier.
    private(set) var sessionId: String = UUID().uuidString.lowercased()

    /// Timestamp when the session (app launch) started.
    private(set) var sessionStartTime: Date = Date()

    // MARK: - State

    private var isConfigured = false

    /// Error tracker with anti-spam aggregation.
    let errorTracker = TelemetryErrorTracker()

    /// Rate limiter for event deduplication.
    let rateLimiter = TelemetryRateLimiter()

    // MARK: - Keychain Constants

    private static let keychainService = "com.superhumancorp.r2drop.analytics"
    private static let distinctIdAccount = "distinct_id"

    // MARK: - Init

    private init() {}

    // MARK: - Setup

    /// Initialize PostHog SDK and load/create identity. Call once at app launch.
    func configure() {
        guard !isConfigured else { return }

        // Reset session state for this launch
        sessionId = UUID().uuidString.lowercased()
        sessionStartTime = Date()

        // Load or create the stable distinct_id
        distinctId = loadOrCreateDistinctId()

        // Configure PostHog SDK
        let config = PostHogConfig(apiKey: Self.apiKey, host: Self.host)
        PostHogSDK.shared.setup(config)
        isConfigured = true

        // Read initial telemetry preference
        let prefs = (try? ConfigManager.load()) ?? R2Config()
        setEnabled(prefs.preferences.allowAnonymousTelemetry)

        // Identify this install
        PostHogSDK.shared.identify(distinctId, userProperties: personProperties())

        // Wire error tracker
        errorTracker.emitEvent = { [weak self] event, props in
            self?.track(event, properties: props)
        }
        errorTracker.start()
    }

    // MARK: - Opt-In / Opt-Out

    /// Enable or disable telemetry. Respects user preference.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    // MARK: - Tracking

    /// Track an event with optional custom properties.
    /// Common properties (session_id, app_version, etc.) are automatically merged.
    /// This method never throws — analytics failures must not break the app.
    func track(_ event: String, properties: [String: Any]? = nil) {
        var merged = commonProperties()
        if let properties {
            for (key, value) in properties {
                merged[key] = value
            }
        }
        PostHogSDK.shared.capture(event, properties: merged)
    }

    /// Track an event only if the rate limiter allows it.
    /// Use for events that could fire frequently (e.g. error events with dedup key).
    func trackIfAllowed(_ event: String, dedupeKey: String, properties: [String: Any]? = nil) {
        guard rateLimiter.shouldSend(key: dedupeKey) else { return }
        track(event, properties: properties)
    }

    /// Capture an error with anti-spam protection.
    /// First occurrence → immediate `app_error`. Repeats → aggregated summary.
    func captureError(_ error: Error, context: ErrorContext) {
        errorTracker.captureError(error, context: context)
    }

    /// Force flush all pending events to PostHog.
    func flush() {
        errorTracker.flush()
        PostHogSDK.shared.flush()
    }

    // MARK: - Common Properties

    /// Properties attached to every event automatically.
    private func commonProperties() -> [String: Any] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        return [
            "session_id": sessionId,
            "app_version": version,
            "build_number": build,
            "platform": "macOS",
            "os_version": osVersion,
            "is_debug_build": isDebug,
            "app_process": "main_app"
        ]
    }

    /// Person properties for PostHog identify call. Low-risk metadata only.
    private func personProperties() -> [String: Any] {
        let config = (try? ConfigManager.load()) ?? R2Config()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        return [
            "app_version": version,
            "build_number": build,
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "has_accounts": !config.accounts.isEmpty,
            "account_count": config.accounts.count,
            "hide_dock_icon": config.preferences.hideDockIcon,
            "launch_at_login": config.preferences.launchAtLogin,
            "analytics_opt_in": config.preferences.allowAnonymousTelemetry
        ]
    }

    // MARK: - Identity Management

    /// Load the stable distinct_id from Keychain, or create a new one.
    private func loadOrCreateDistinctId() -> String {
        if let existing = readKeychain(account: Self.distinctIdAccount) {
            return existing
        }
        let newId = UUID().uuidString.lowercased()
        saveKeychain(account: Self.distinctIdAccount, value: newId)
        return newId
    }

    // MARK: - Keychain Helpers

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Shutdown

    /// Call on app termination to flush all pending data.
    func shutdown() {
        errorTracker.stop()
        PostHogSDK.shared.flush()
    }
}
