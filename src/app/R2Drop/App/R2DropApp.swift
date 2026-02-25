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
import R2Bridge

// MARK: - Notification Names

extension Notification.Name {
    /// Fired when accounts are added, updated, or removed.
    /// AccountsViewModel observes this to refresh its data.
    static let r2dropAccountsDidChange = Notification.Name("r2dropAccountsDidChange")

    /// Fired when the upload queue changes (new job, resume, retry).
    /// UploadProcessor observes this to immediately process instead of waiting for its 3s timer.
    static let r2dropQueueDidChange = Notification.Name("r2dropQueueDidChange")
}
@main
struct R2DropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI is managed via custom NSWindow (AppDelegate.openSettingsWindow).
        // We keep an empty Settings scene so SwiftUI's body requirement compiles.
        Settings {
            EmptyView()
        }
        // Override Cmd+, to open our custom glass-styled NSWindow
        // instead of the SwiftUI Settings scene (which shows a blank window).
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    AppDelegate.openSettingsWindow(reason: "cmd_comma")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
    /// Global accessor so ViewModels can reach AppDelegate without fragile NSApp.delegate cast.
    /// The @NSApplicationDelegateAdaptor wrapper can cause `NSApp.delegate as? AppDelegate` to fail.
    static weak var shared: AppDelegate?
    private var onboardingWindow: NSWindow?
    /// Manually managed preferences window — replaces broken SwiftUI Settings scene.
    /// sendAction(showSettingsWindow:) doesn't work on recent macOS versions,
    /// so we create and manage the NSWindow ourselves, same pattern as onboarding.
    private static var settingsWindow: NSWindow?
    /// Menu bar icon controller — owns the NSStatusItem (FR-034).
    private(set) var menuBarController: MenuBarController!

    /// Background service that validates tokens on launch and every 24h (FR-004).
    let tokenValidationService = TokenValidationService()

    /// Polls the Finder extension's shared App Groups queue and transfers
    /// new jobs to the main queue for the Rust engine to process (FR-021).
    let finderQueueBridge = FinderQueueBridge()

    /// Monitors upload state transitions and fires macOS notifications (FR-061, FR-062).
    let uploadMonitor = UploadMonitor()

    /// Periodically invokes the Rust engine to process pending upload jobs.
    let uploadProcessor = UploadProcessor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
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
        // Initialize Rust audit logging (FR-067) — rolling file to ~/.r2drop/logs/
        let logResult = R2Client.initLogging(
            maxLogFiles: UInt16(config.preferences.maxLogFiles),
            maxLogFileSizeMb: UInt16(config.preferences.maxLogFileSizeMb)
        )
        #if DEBUG
        R2Log.app.debug("r2_init_logging result: \(logResult)")
        #endif
        NSApp.setActivationPolicy(config.preferences.hideDockIcon ? .accessory : .regular)
        #if DEBUG
        R2Log.app.debug("Activation policy: \(config.preferences.hideDockIcon ? ".accessory" : ".regular")")
        #endif

        // Initialize PostHog telemetry (respects user's telemetry preference)
        TelemetryService.shared.configure()

        // P0: app_launch — enhanced with account info
        let activationPolicy = config.preferences.hideDockIcon ? "accessory" : "regular"
        TelemetryService.shared.track("app_launch", properties: [
            "has_accounts": accountsExist(),
            "activation_policy": activationPolicy,
            "hide_dock_icon": config.preferences.hideDockIcon,
            "account_count": config.accounts.count
        ])
        let hasAccounts = accountsExist()
        #if DEBUG
        R2Log.app.debug("Accounts exist: \(hasAccounts)")
        #endif
        // Start polling the Finder extension's shared queue (FR-021)
        finderQueueBridge.start()

        // Start monitoring uploads for notification triggers (FR-062)
        uploadMonitor.start()

        // Start the Rust upload engine processor — picks up pending jobs and uploads them.
        uploadProcessor.start()

        // P0: app_services_started — confirm all background services initialized
        TelemetryService.shared.track("app_services_started", properties: [
            "started_notification_service": true,
            "started_finder_bridge": true,
            "started_upload_monitor": true,
            "started_upload_processor": true
        ])

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
            Self.openSettingsWindow(reason: "launch")
        }

        // Cmd+, is handled by CommandGroup(replacing: .appSettings) in the body scene.
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        R2Log.app.debug("applicationWillTerminate — stopping services")
        #endif
        // Flush telemetry before shutdown
        TelemetryService.shared.shutdown()
        tokenValidationService.stop()
        finderQueueBridge.stop()
        uploadMonitor.stop()
        uploadProcessor.stop()
    }

    /// Prevent app from quitting when Settings window (or any window) is closed.
    /// Menu bar apps must stay running — the user quits via the dropdown Quit item.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Deep Links (US-022)

    /// Handle incoming URLs from deep links and file-open events (including Dock drops).
    /// `r2drop://` URLs are routed to DeepLinkHandler; `file://` URLs are queued for upload.
    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        R2Log.app.debug("URLs received: \(urls.map { $0.absoluteString })")
        #endif

        // P0: app_open_urls_received
        let fileURLs = urls.filter(\.isFileURL)
        let deeplinks = urls.filter { !$0.isFileURL }
        TelemetryService.shared.track("app_open_urls_received", properties: [
            "url_count": urls.count,
            "file_url_count": fileURLs.count,
            "deeplink_count": deeplinks.count
        ])
        if !fileURLs.isEmpty {
            handleIncomingUploadURLs(fileURLs)
        }

        for url in urls where !url.isFileURL {
            _ = DeepLinkHandler.handle(url, appDelegate: self)
        }
    }

    /// Legacy NSApplicationDelegate callback used by Finder/Dock in some open-file flows.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        handleIncomingUploadURLs(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    /// Single-file variant of the open-file callback.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleIncomingUploadURLs([URL(fileURLWithPath: filename)])
        return true
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
        Self.openSettingsWindow(reason: "post_logout")
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

    /// Queue files/folders dropped onto the Dock icon or opened via Finder.
    /// Reuses the menu bar upload flow so confirmation, exclusions, and folder recursion
    /// stay consistent with drag-and-drop on the status item.
    private func handleIncomingUploadURLs(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        // P0: dock_files_received
        let hasDirectory = fileURLs.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false }
        TelemetryService.shared.track("dock_files_received", properties: [
            "file_count": fileURLs.count,
            "contains_directory": hasDirectory
        ])

        menuBarController?.queueUserSelectedURLs(fileURLs)
    }
    /// Present an onboarding/setup window with the given mode and title.
    /// Closes any existing onboarding window first.
    private func presentOnboardingWindow(mode: OnboardingMode, title: String) {
        #if DEBUG
        R2Log.app.debug("presentOnboardingWindow: mode=\(String(describing: mode)), title=\(title)")
        #endif

        // P0: onboarding_presented
        let modeStr: String = {
            switch mode {
            case .initial: return "initial"
            case .addAccount: return "add_account"
            case .updateToken: return "update_token"
            }
        }()
        TelemetryService.shared.track("onboarding_presented", properties: [
            "onboarding_mode": modeStr
        ])
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

        // Notify all observers that accounts have changed (e.g., AccountsViewModel)
        // so the Settings window refreshes without needing to close and reopen.
        NotificationCenter.default.post(name: .r2dropAccountsDidChange, object: nil)

        // Show the Settings window so user sees the main app after onboarding
        Self.openSettingsWindow(reason: "post_onboarding")
    }

    // MARK: - Settings Window Helper

    /// Open the Settings/Preferences window as a manually managed NSWindow.
    /// The SwiftUI `Settings` scene + `sendAction(showSettingsWindow:)` approach
    /// is broken on macOS 14+ (logs "Please use SettingsLink" and does nothing).
    /// This creates a real NSWindow wrapping SettingsView, same pattern as onboarding.
    static func openSettingsWindow(reason: String = "unknown") {
        // P0: settings_window_opened
        TelemetryService.shared.track("settings_window_opened", properties: [
            "reason": reason
        ])

        // If the window already exists and is visible, just bring it to front
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.title = "R2Drop Settings"
        window.center()
        window.isReleasedWhenClosed = false

        // Wrap activation in async so menu bar dropdown dismisses first.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        settingsWindow = window
    }


}
