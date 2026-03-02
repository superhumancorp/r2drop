// R2Drop/App/Services/NotificationService.swift
// Central notification service for upload events (FR-061, FR-062, FR-063).
// Uses UNUserNotificationCenter for macOS notifications.
// Registers actionable categories: Copy URL, Retry, Set up token.
// Plays system sound on upload complete when enabled in preferences.

import Foundation
import UserNotifications
import AppKit
import R2Core

// MARK: - Notification Categories

/// Category identifiers for actionable notifications.
enum NotificationCategory: String {
    case uploadComplete   = "UPLOAD_COMPLETE"
    case uploadFailed     = "UPLOAD_FAILED"
    case uploadPaused     = "UPLOAD_PAUSED"
    case tokenExpired     = "TOKEN_EXPIRED"
}

/// Action identifiers for notification buttons.
enum NotificationAction: String {
    case copyURL     = "COPY_URL"
    case retry       = "RETRY"
    case setupToken  = "SETUP_TOKEN"
}

// MARK: - NotificationService

/// Manages all macOS notifications for R2Drop.
/// Handles permission requests, category registration, notification posting,
/// and user response actions (Copy URL, Retry, Set up token).
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    /// Shared singleton — accessed by AppDelegate and upload tracking.
    static let shared = NotificationService()

    private override init() {
        super.init()
    }

    // MARK: - Setup

    /// Request notification permission and register categories.
    /// Call once from AppDelegate on launch.
    func start() {
        #if DEBUG
        R2Log.service.debug("NotificationService: start")
        #endif
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request permission (FR-061)
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            // P0: notification_permission_requested
            Task { @MainActor in
                TelemetryService.shared.track("notification_permission_requested", properties: [
                    "granted": granted
                ])
            }
            #if DEBUG
            R2Log.service.debug("NotificationService: permission requested granted=\(granted)")
            #endif
        }

        // Register actionable categories (FR-062)
        registerCategories()
    }

    /// Register notification categories with action buttons.
    private func registerCategories() {
        let center = UNUserNotificationCenter.current()

        // "Copy URL" action for successful uploads
        let copyAction = UNNotificationAction(
            identifier: NotificationAction.copyURL.rawValue,
            title: "Copy URL",
            options: .foreground
        )

        // "Retry" action for failed uploads
        let retryAction = UNNotificationAction(
            identifier: NotificationAction.retry.rawValue,
            title: "Retry",
            options: .foreground
        )

        // "Set up token" action for expired tokens
        let setupAction = UNNotificationAction(
            identifier: NotificationAction.setupToken.rawValue,
            title: "Set Up New Token",
            options: .foreground
        )

        let completeCategory = UNNotificationCategory(
            identifier: NotificationCategory.uploadComplete.rawValue,
            actions: [copyAction],
            intentIdentifiers: []
        )

        let failedCategory = UNNotificationCategory(
            identifier: NotificationCategory.uploadFailed.rawValue,
            actions: [retryAction],
            intentIdentifiers: []
        )

        let pausedCategory = UNNotificationCategory(
            identifier: NotificationCategory.uploadPaused.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        let tokenCategory = UNNotificationCategory(
            identifier: NotificationCategory.tokenExpired.rawValue,
            actions: [setupAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            completeCategory, failedCategory, pausedCategory, tokenCategory
        ])
    }

    // MARK: - Post Notifications

    /// Notify that a single upload completed successfully (FR-062).
    /// Plays system sound if enabled in preferences (FR-063).
    func notifyUploadComplete(fileName: String, url: String?) {
        #if DEBUG
        R2Log.service.debug("NotificationService: notifyUploadComplete fileName=\(fileName)")
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body = "\"\(fileName)\" has been uploaded to R2."
        content.categoryIdentifier = NotificationCategory.uploadComplete.rawValue

        // Store URL in userInfo so "Copy URL" action can retrieve it
        if let url = url, !url.isEmpty {
            content.userInfo = ["url": url, "fileName": fileName]
        }

        // P1: notification_upload_complete_shown
        TelemetryService.shared.track("notification_upload_complete_shown", properties: [
            "single_or_batch": "single",
            "count": 1
        ])

        post(content, id: "upload-complete-\(fileName)-\(Date().timeIntervalSince1970)")
        playSoundIfEnabled()
    }

    /// Notify that a batch of uploads completed (FR-062).
    func notifyBatchComplete(count: Int) {
        #if DEBUG
        R2Log.service.debug("NotificationService: notifyBatchComplete count=\(count)")
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Uploads Complete"
        content.body = "\(count) files have been uploaded to R2."
        // No "Copy URL" action for batch — can't copy multiple URLs to clipboard

        // P1: notification_upload_complete_shown (batch)
        TelemetryService.shared.track("notification_upload_complete_shown", properties: [
            "single_or_batch": "batch",
            "count": count
        ])

        post(content, id: "batch-complete-\(Date().timeIntervalSince1970)")
        playSoundIfEnabled()
    }

    /// Notify that an upload failed (FR-062).
    func notifyUploadFailed(fileName: String, error: String, jobId: Int64) {
        #if DEBUG
        R2Log.service.debug("NotificationService: notifyUploadFailed fileName=\(fileName) jobId=\(jobId)")
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Upload Failed"
        content.body = "\"\(fileName)\" failed: \(error)"
        content.categoryIdentifier = NotificationCategory.uploadFailed.rawValue
        content.userInfo = ["jobId": jobId, "fileName": fileName]

        // P1: notification_upload_failed_shown
        TelemetryService.shared.track("notification_upload_failed_shown", properties: [
            "job_id": jobId
        ])

        post(content, id: "upload-failed-\(jobId)")
    }

    /// Notify that uploads paused due to network loss (FR-062).
    func notifyUploadPaused(reason: String = "Network connection lost") {
        #if DEBUG
        R2Log.service.debug("NotificationService: notifyUploadPaused reason=\(reason)")
        #endif
        let content = UNMutableNotificationContent()
        content.title = "Uploads Paused"
        content.body = reason
        content.categoryIdentifier = NotificationCategory.uploadPaused.rawValue

        post(content, id: "upload-paused-\(Date().timeIntervalSince1970)")
    }

    /// Notify that a token has expired (FR-062).
    func notifyTokenExpired(accountName: String) {
        #if DEBUG
        R2Log.service.debug("NotificationService: notifyTokenExpired accountName=\(accountName)")
        #endif
        let content = UNMutableNotificationContent()
        content.title = "R2Drop Token Expired"
        content.body = "Your token for \"\(accountName)\" has expired. Click here to set up a new one."
        content.categoryIdentifier = NotificationCategory.tokenExpired.rawValue
        content.userInfo = ["accountName": accountName]

        // P1: notification_token_expired_shown
        TelemetryService.shared.track("notification_token_expired_shown", properties: [
            "account_name_hash": TelemetrySanitizer.hash(accountName)
        ])

        post(content, id: "token-expired-\(accountName)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification actions when user taps a button.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        Task { @MainActor in
            // P0: notification_action_clicked
            let category = response.notification.request.content.categoryIdentifier
            TelemetryService.shared.track("notification_action_clicked", properties: [
                "action": actionId,
                "category": category
            ])

            switch actionId {
            case NotificationAction.copyURL.rawValue:
                // Copy the R2 URL to clipboard
                #if DEBUG
                R2Log.service.debug("NotificationService: action copyURL")
                #endif
                if let url = userInfo["url"] as? String, !url.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }

            case NotificationAction.retry.rawValue:
                // Re-queue the failed job by resetting its status to pending
                #if DEBUG
                R2Log.service.debug("NotificationService: action retry")
                #endif
                if let jobId = userInfo["jobId"] as? Int64 {
                    retryJob(jobId)
                }

            case NotificationAction.setupToken.rawValue:
                // Open the add-account / token setup flow
                #if DEBUG
                R2Log.service.debug("NotificationService: action setupToken")
                #endif
                if let accountName = userInfo["accountName"] as? String {
                    (NSApp.delegate as? AppDelegate)?.showUpdateToken(accountName: accountName)
                }

            default:
                // Default tap — bring app to front
                NSApp.activate(ignoringOtherApps: true)
            }

            completionHandler()
        }
    }

    /// Show notifications even when app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Private Helpers

    /// Submit a notification request to the notification center.
    private func post(_ content: UNMutableNotificationContent, id: String) {
        // P1: notification_posted
        let idPrefix = String(id.prefix(while: { $0 != "-" }))
        TelemetryService.shared.track("notification_posted", properties: [
            "category": content.categoryIdentifier,
            "id_prefix": idPrefix
        ])

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Play the macOS system sound if the user has "Play sound on upload complete" enabled (FR-063).
    /// Does NOT call beep — the notification itself already has .default sound.
    /// This plays a separate Glass sound only if the user's preference is on.
    private func playSoundIfEnabled() {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard config.preferences.playSound else { return }
        // Use Glass sound instead of beep for a nicer feel
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    /// Reset a failed job back to pending for retry.
    /// Also resets retry_count so the Rust engine gives it fresh attempts.
    private func retryJob(_ jobId: Int64) {
        guard let qm = try? QueueManager() else { return }
        try? qm.resetRetryCount(id: jobId)
        try? qm.updateStatus(id: jobId, status: .pending)
        // Trigger immediate processing instead of waiting for the 3s timer.
        NotificationCenter.default.post(name: .r2dropQueueDidChange, object: nil)
    }
}
