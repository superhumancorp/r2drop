// R2Drop/App/About/AboutViewModel.swift
// ViewModel for the About tab in the Preferences window (US-021).
// Manages app version info and external links.
// App Store/TestFlight builds rely on App Store updates instead of Sparkle.

import AppKit

/// Manages About tab state: version info, update checks, and external links.
@MainActor
final class AboutViewModel: ObservableObject {

    // MARK: - Published Properties

    /// App version string from bundle (e.g. "0.1.0")
    @Published var appVersion: String = ""

    /// Build number from bundle (e.g. "1")
    @Published var buildNumber: String = ""

    /// Whether automatic update checking is enabled (FR-058)
    @Published var automaticallyChecksForUpdates: Bool = true

    /// Formatted timestamp of last update check
    @Published var lastCheckDateString: String = "Never"

    /// Whether a check is currently in progress
    @Published var isCheckingForUpdates: Bool = false

    // MARK: - Init

    init() {
        // Load version info from the main bundle
        let bundle = Bundle.main
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        automaticallyChecksForUpdates = false
        lastCheckDateString = "Managed by App Store"
    }

    // MARK: - Actions

    /// Toggle automatic update checking (FR-058).
    func toggleAutoCheck(_ enabled: Bool) {
        // App Store/TestFlight builds don't manage update checks directly.
        automaticallyChecksForUpdates = false
    }

    /// Trigger a manual update check (FR-058).
    func checkForUpdates() {
        // No-op for App Store/TestFlight builds.
        isCheckingForUpdates = false
    }

    /// Whether the "Check Now" button should be enabled.
    var canCheckForUpdates: Bool {
        false
    }

    // MARK: - Links (FR-056)

    func openPrivacyPolicy() {
        openURL("https://r2drop.com/privacy")
    }

    func openTermsOfService() {
        openURL("https://r2drop.com/terms")
    }

    func openReportIssue() {
        openURL("https://github.com/superhumancorp/r2drop/issues")
    }

    func openDocumentation() {
        openURL("https://docs.r2drop.com")
    }

    func openWebsite() {
        openURL("https://r2drop.com")
    }

    func openDeveloperX() {
        openURL("https://x.com/paulpierre")
    }

    func openDeveloperGitHub() {
        openURL("https://github.com/paulpierre")
    }

    // MARK: - Private

    /// Open a URL in the default browser.
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
