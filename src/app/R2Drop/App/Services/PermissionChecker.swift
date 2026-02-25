// R2Drop/App/Services/PermissionChecker.swift
// Detects missing permissions (Notifications) and provides methods to open
// the correct System Settings pane.
// Checks on launch and whenever the app becomes active (user returns from Settings).
// NOTE: Finder Sync Extension does NOT need special permission checks --
// it just needs to be enabled in System Settings > Login Items & Extensions.

import Foundation
import UserNotifications
import AppKit

@MainActor
final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()
    
    @Published var notificationsAuthorized: Bool = true // Assume true until checked
    
    private init() {
        refresh()
        // Re-check every time user returns to the app (e.g., after visiting System Settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    /// Check all permissions. Called on init and when app becomes active.
    @objc func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsAuthorized = (settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional)
            }
        }
    }
    
    /// True if any permission needs attention.
    var hasIssues: Bool {
        !notificationsAuthorized
    }
    
    /// Open System Settings to the Notifications pane for this app.
    func openNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let encoded = bundleId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleId
        let urls = [
            "x-apple.systempreferences:com.apple.preference.notifications?id=\(encoded)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) { return }
        }
    }
}
