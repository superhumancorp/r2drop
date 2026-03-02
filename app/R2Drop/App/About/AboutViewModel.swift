// R2Drop/App/About/AboutViewModel.swift
// ViewModel for the About tab (US-021).
// Manages app version info, Sparkle auto-update controls, and external links.
// Uses SPUUpdater from the Sparkle framework for checking GitHub Releases.

import AppKit
import Sparkle

/// Manages About tab state: version info, Sparkle update checks, and external links.
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

    // MARK: - Sparkle

    /// Sparkle updater controller — manages the update lifecycle.
    private let updaterController: SPUStandardUpdaterController

    /// Direct reference to the updater for programmatic access.
    private var updater: SPUUpdater { updaterController.updater }

    // MARK: - Init

    init() {
        // Initialize Sparkle updater (starts automatic checking if enabled in Info.plist)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Load version info from the main bundle
        let bundle = Bundle.main
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        // Sync auto-check state from Sparkle
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        // Format last check date
        if let lastDate = updater.lastUpdateCheckDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            lastCheckDateString = fmt.string(from: lastDate)
        }
    }

    // MARK: - Actions

    /// Toggle automatic update checking (FR-058).
    func toggleAutoCheck(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    /// Trigger a manual update check (FR-058).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)

        // Update the last check date after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if let lastDate = self.updater.lastUpdateCheckDate {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .short
                self.lastCheckDateString = fmt.string(from: lastDate)
            }
        }
    }

    /// Whether the "Check Now" button should be enabled.
    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
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
