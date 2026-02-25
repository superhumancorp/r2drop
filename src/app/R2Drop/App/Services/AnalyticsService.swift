// R2Drop/App/Services/AnalyticsService.swift
// Thin wrapper around PostHog for anonymous telemetry.
// Respects the user's "Allow anonymous telemetry" preference.
// All tracking is opt-out: enabled by default, user can disable in Settings or Onboarding.
// No PII is collected — only anonymous usage events.

import Foundation
import PostHog
import R2Core

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    // PostHog project API key and host
    private static let apiKey = "phc_tyaFmZbyRb9RMbinKc16kWLNmQRwZUlUUIcnvQCdCyU"
    private static let host = "https://us.i.posthog.com"

    private var isConfigured = false

    private init() {}

    // MARK: - Setup

    /// Initialize PostHog SDK. Call once at app launch.
    func configure() {
        guard !isConfigured else { return }
        let config = PostHogConfig(apiKey: Self.apiKey, host: Self.host)
        PostHogSDK.shared.setup(config)
        isConfigured = true

        // Read initial telemetry preference from config.toml
        let prefs = (try? ConfigManager.load()) ?? R2Config()
        setEnabled(prefs.preferences.allowAnonymousTelemetry)
    }

    // MARK: - Opt-In / Opt-Out

    /// Enable or disable telemetry. Reads the user's preference.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    // MARK: - Tracking

    /// Track an event. Only sends if telemetry is enabled (PostHog handles opt-out internally).
    func track(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    /// Track app launch with version info.
    func trackAppLaunch() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        track("app_launched", properties: [
            "version": version,
            "build_number": build,
            "macos_version": osVersion
        ])
    }

    /// Track upload started.
    func trackUploadStarted(fileCount: Int, totalBytes: UInt64, entryPoint: String) {
        track("upload_started", properties: [
            "file_count": fileCount,
            "total_bytes": totalBytes,
            "entry_point": entryPoint
        ])
    }

    /// Track upload completed.
    func trackUploadCompleted(fileCount: Int, totalBytes: UInt64, durationSeconds: Double) {
        track("upload_completed", properties: [
            "file_count": fileCount,
            "total_bytes": totalBytes,
            "duration_seconds": durationSeconds
        ])
    }

    /// Track upload failed.
    func trackUploadFailed(errorCode: String, retryCount: Int) {
        track("upload_failed", properties: [
            "error_code": errorCode,
            "retry_count": retryCount
        ])
    }

    /// Track account added.
    func trackAccountAdded(bucketCount: Int) {
        track("account_added", properties: [
            "bucket_count": bucketCount
        ])
    }

    /// Track settings changed.
    func trackSettingsChanged(settingName: String, newValue: String) {
        track("settings_changed", properties: [
            "setting_name": settingName,
            "new_value": newValue
        ])
    }
}
