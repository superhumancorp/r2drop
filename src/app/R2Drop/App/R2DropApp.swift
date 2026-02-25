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
        #if DEBUG
        R2Log.app.debug("applicationDidFinishLaunching")
        #endif
        // Create the persistent menu bar icon (FR-034)
        // Pass self so MenuBarController has a direct AppDelegate reference
        // instead of relying on NSApp.delegate cast (which can fail with SwiftUI).
        menuBarController = MenuBarController(appDelegate: self)
        #if DEBUG
        R2Log.app.debug("MenuBarController created")
        #endif

        // Start notification service — requests permission and registers categories (FR-061)
        NotificationService.shared.start()

        // Apply dock icon visibility from config.
        // Default is .regular (dock icon visible). If user set hide_dock_icon = true,
        // switch to .accessory (menu bar only).
        let config = (try? ConfigManager.load()) ?? R2Config()
        NSApp.setActivationPolicy(config.preferences.hideDockIcon ? .accessory : .regular)
        #if DEBUG
        R2Log.app.debug("Activation policy: \(config.preferences.hideDockIcon ? ".accessory" : ".regular")")
        #endif

        let hasAccounts = accountsExist()
        #if DEBUG
        R2Log.app.debug("Accounts exist: \(hasAccounts)")
        #endif
        // Start polling the Finder extension's shared queue (FR-021)
        finderQueueBridge.start()

        // Start monitoring uploads for notification triggers (FR-062)
        uploadMonitor.start()

        #if DEBUG
        // Always show onboarding in debug mode for UI development/testing
        let shouldShowOnboarding = true
        #else
        let shouldShowOnboarding = !hasAccounts
        #endif

        if shouldShowOnboarding {
            // Bug 1 fix: Actually call showOnboarding() (was empty block)
            showOnboarding()
        } else {
            // FR-003: Retrieve tokens from Keychain and validate on launch
            // FR-004: Start periodic 24h re-validation
            tokenValidationService.start()
        }

        // Always open Settings window on launch so the user sees something.
        // Need a longer delay — SwiftUI's Settings scene isn't ready immediately.
        // 0.5s gives the scene graph time to register the Settings window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.openSettingsWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        R2Log.app.debug("applicationWillTerminate — stopping services")
        #endif
        tokenValidationService.stop()
        finderQueueBridge.stop()
        uploadMonitor.stop()
    }

    /// Prevent app from quitting when Settings window (or any window) is closed.
    /// Menu bar apps must stay running — the user quits via the dropdown Quit item.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Deep Links (US-022)

    /// Handle r2drop:// URL scheme invocations from CLI, browser, or other apps.
    /// Delegates to DeepLinkHandler for parsing and routing.
    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        R2Log.app.debug("Deep link received: \(urls.map { $0.absoluteString })")
        #endif
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
        #if DEBUG
        R2Log.app.debug("logOut: \(accountName)")
        #endif
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

        // Bug 6 fix: After logout, always navigate to Accounts tab so user sees the change.
        // If no accounts remain, also show onboarding.
        if !accountsExist() {
            tokenValidationService.stop()
            showOnboarding()
        }
        SelectedTabStore.shared.requestedTab = .accounts
        Self.openSettingsWindow()
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
        #if DEBUG
        R2Log.app.debug("presentOnboardingWindow: mode=\(String(describing: mode)), title=\(title)")
        #endif
        // Close existing window if open
        onboardingWindow?.close()
        onboardingWindow = nil

        let onboardingView = OnboardingWindow(mode: mode, onDismiss: { [weak self] in
            self?.dismissOnboarding()
        })

        let hostingView = NSHostingView(rootView: onboardingView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // Keep window opaque so the Settings window doesn't bleed through.
        // The SwiftUI .ultraThinMaterial inside the view blurs our own Background-1.png
        // texture layer — not the windows behind the app. This gives frosted glass
        // appearance without transparency artifacts.
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.title = title
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        // Wrap activation in async so menu bar dropdown dismisses first.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

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

    // MARK: - Settings Window Helper

    /// Open the Settings/Preferences window reliably across macOS versions.
    /// macOS 13 uses showPreferencesWindow:, macOS 14+ uses showSettingsWindow:.
    /// We try to find an existing Settings window first, then fall back to selectors.
    static func openSettingsWindow() {
        // Bug 3 fix: Always use sendAction (simpler, more reliable).
        // The window-search heuristic was fragile — sendAction works on all versions.
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        // Activate async so the menu bar dropdown has time to dismiss first.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
