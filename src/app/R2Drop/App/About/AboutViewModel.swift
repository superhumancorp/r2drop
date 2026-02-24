// R2Drop/App/About/AboutViewModel.swift
// ViewModel for the About tab in the Preferences window (US-021).
// Manages app version info, Sparkle auto-update state, and link actions.
// Uses SPUStandardUpdaterController for Sparkle 2.x integration (FR-058).

import AppKit
import Sparkle

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

    // MARK: - Sparkle

    /// Sparkle updater controller — manages the update lifecycle.
    /// `startingUpdater: true` begins automatic checking on init.
    private let updaterController: SPUStandardUpdaterController

    /// Direct access to the updater for programmatic checks.
    private var updater: SPUUpdater { updaterController.updater }

    // MARK: - Init

    init() {
        // Initialize Sparkle. `startingUpdater: true` starts the auto-check cycle.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Load version info from the main bundle
        let bundle = Bundle.main
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        // Sync auto-check preference from Sparkle
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates

        // Format the last check date
        updateLastCheckDate()
    }

    // MARK: - Actions

    /// Toggle automatic update checking (FR-058).
    func toggleAutoCheck(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    /// Trigger a manual update check (FR-058).
    func checkForUpdates() {
        updater.checkForUpdates()
        isCheckingForUpdates = true

        // Sparkle runs the check asynchronously. We update the "last checked"
        // timestamp after a short delay to let the check complete.
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            isCheckingForUpdates = false
            updateLastCheckDate()
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

    // MARK: - Private

    /// Format the last update check date from Sparkle.
    private func updateLastCheckDate() {
        if let date = updater.lastUpdateCheckDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lastCheckDateString = formatter.string(from: date)
        } else {
            lastCheckDateString = "Never"
        }
    }

    /// Open a URL in the default browser.
    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
