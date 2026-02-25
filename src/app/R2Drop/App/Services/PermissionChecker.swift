// R2Drop/App/Services/PermissionChecker.swift
// Detects missing permissions (Finder Sync Extension, Notifications) and
// provides methods to open the correct System Settings pane.
// Checks on launch and whenever the app becomes active (user returns from Settings).

import Foundation
import UserNotifications
import AppKit

@MainActor
final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()
    
    @Published var finderExtensionEnabled: Bool = false
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
        // Finder Sync Extension — check via private API
        finderExtensionEnabled = checkFinderExtensionEnabled()
        
        // Notifications — async callback
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsAuthorized = (settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional)
            }
        }
    }
    
    /// True if any permission needs attention.
    var hasIssues: Bool {
        !finderExtensionEnabled || !notificationsAuthorized
    }
    
    /// Check if Finder Sync Extension is enabled.
    /// Uses private API: FIFinderSyncController.isExtensionEnabled (macOS 10.10+).
    private func checkFinderExtensionEnabled() -> Bool {
        // Try to use the private API if available
        if let finderSyncClass = NSClassFromString("FIFinderSyncController") as? NSObject.Type {
            if let isEnabled = finderSyncClass.value(forKey: "isExtensionEnabled") as? Bool {
                return isEnabled
            }
        }
        // Fallback: assume disabled if we can't check
        return false
    }
    
    /// Open the system sheet for managing Finder extensions.
    func openFinderExtensionSettings() {
        // Use private API to show Finder Sync extension management
        if let finderSyncClass = NSClassFromString("FIFinderSyncController") as? NSObject.Type {
            if finderSyncClass.responds(to: Selector(("showExtensionManagementInterface"))) {
                finderSyncClass.perform(Selector(("showExtensionManagementInterface")))
                return
            }
        }
        // Fallback: open System Settings to Extensions pane
        openSystemSettingsExtensions()
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
    
    /// Open System Settings to the Extensions pane.
    private func openSystemSettingsExtensions() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.extensions",
            "x-apple.systempreferences:com.apple.Extensions-Settings.extension"
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) { return }
        }
    }
}
