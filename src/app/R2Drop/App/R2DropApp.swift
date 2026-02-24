// R2Drop/App/R2DropApp.swift
// Main entry point for the R2Drop macOS menu bar application.
// The menu bar icon is managed by MenuBarController (NSStatusItem) for
// animation and drag-and-drop support — SwiftUI's MenuBarExtra can't do these.
// Shows onboarding on first launch (no accounts configured).
// Supports add account, update token, and log out flows (US-014).
// On launch, validates stored tokens silently from Keychain (FR-003, FR-004).
// Polls the Finder extension's shared queue for new uploads (FR-021).

import SwiftUI
import R2Core

@main
struct R2DropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window opened via "Preferences..." in the menu bar dropdown.
        // The menu bar icon itself is managed by MenuBarController (not MenuBarExtra)
        // because we need icon animation (FR-035) and drag-and-drop (FR-066).
        Settings {
            SettingsView()
        }
    }
}

// MARK: - AppDelegate

/// Handles menu bar setup, first-launch onboarding, token validation,
/// account management flows, and deep link events.
/// SwiftUI's App protocol doesn't support opening arbitrary windows on launch,
/// so we use NSApplicationDelegate for onboarding and account setup sheets.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    /// Menu bar icon controller — owns the NSStatusItem (FR-034).
    private(set) var menuBarController: MenuBarController!

    /// Background service that validates tokens on launch and every 24h (FR-004).
    let tokenValidationService = TokenValidationService()

    /// Polls the Finder extension's shared App Groups queue and transfers
    /// new jobs to the main queue for the Rust engine to process (FR-021).
    let finderQueueBridge = FinderQueueBridge()

    /// Monitors upload state transitions and fires macOS notifications (FR-061, FR-062).
    let uploadMonitor = UploadMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the persistent menu bar icon (FR-034)
        menuBarController = MenuBarController()

        // Start notification service — requests permission and registers categories (FR-061)
        NotificationService.shared.start()

        let hasAccounts = accountsExist()
        // Start polling the Finder extension's shared queue (FR-021)
        finderQueueBridge.start()

        // Start monitoring uploads for notification triggers (FR-062)
        uploadMonitor.start()

        if !hasAccounts {
            showOnboarding()
        } else {
            // FR-003: Retrieve tokens from Keychain and validate on launch
            // FR-004: Start periodic 24h re-validation
            tokenValidationService.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tokenValidationService.stop()
        finderQueueBridge.stop()
        uploadMonitor.stop()
    }

    // MARK: - Deep Links (US-022)

    /// Handle r2drop:// URL scheme invocations from CLI, browser, or other apps.
    /// Delegates to DeepLinkHandler for parsing and routing.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.handle(url, appDelegate: self)
        }
    }

    // MARK: - Onboarding (First Launch)

    /// Present the onboarding carousel as a centered, non-resizable window.
    func showOnboarding() {
        presentOnboardingWindow(mode: .initial, title: "Welcome to R2Drop")
    }

    // MARK: - Add Account (FR-007)

    /// Open the token setup flow (panels 3-5) to add a new account.
    /// Triggered from the menu bar "Add Account..." action.
    func showAddAccount() {
        presentOnboardingWindow(mode: .addAccount, title: "Add Account")
    }

    // MARK: - Update Token (FR-008)

    /// Open the token paste+validate flow for an existing account.
    /// Replaces the Keychain entry and optionally updates bucket config.
    func showUpdateToken(accountName: String) {
        presentOnboardingWindow(
            mode: .updateToken(accountName),
            title: "Update Token — \(accountName)"
        )
    }

    // MARK: - Log Out (FR-009)

    /// Remove an account's Keychain entry and config with a confirmation dialog.
    func logOut(accountName: String) {
        let alert = NSAlert()
        alert.messageText = "Log out of \"\(accountName)\"?"
        alert.informativeText = "This will remove the API token from Keychain and delete the account configuration."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Log Out")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Remove Keychain entry
        let keychainManager = KeychainManager()
        try? keychainManager.deleteToken(account: accountName)

        // Remove from config
        if let manager = try? AccountManager() {
            try? manager.removeAccount(named: accountName)
        }

        // If no accounts remain, show onboarding
        if !accountsExist() {
            tokenValidationService.stop()
            showOnboarding()
        }
    }

    // MARK: - Private

    /// Check whether at least one account is configured in config.toml.
    private func accountsExist() -> Bool {
        do {
            let config = try ConfigManager.load()
            return !config.accounts.isEmpty
        } catch {
            return false
        }
    }

    /// Present an onboarding/setup window with the given mode and title.
    /// Closes any existing onboarding window first.
    private func presentOnboardingWindow(mode: OnboardingMode, title: String) {
        // Close existing window if open
        onboardingWindow?.close()
        onboardingWindow = nil

        let onboardingView = OnboardingWindow(mode: mode, onDismiss: { [weak self] in
            self?.dismissOnboarding()
        })

        let hostingView = NSHostingView(rootView: onboardingView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 400)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    private func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil

        // After any account setup, start periodic token validation if accounts exist
        if accountsExist() {
            tokenValidationService.start()
        }
    }
}
