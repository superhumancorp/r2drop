// R2Drop/App/Services/UploadProcessor.swift
// Periodically invokes the Rust upload engine to process pending jobs.
// Gets credentials from Config + Keychain for the active account.
// The Rust runner handles: recovery, retry with backoff, multipart upload,
// progress tracking, and history recording.
// Polling interval: 3 seconds.

import Foundation
import R2Core
import R2Bridge

@MainActor
final class UploadProcessor {

    private var timer: Timer?
    private let r2Client = R2Client()
    private let pollInterval: TimeInterval = 3.0

    /// Guard against re-entrant processing if a previous cycle is still running.
    private var isProcessing = false

    // MARK: - Lifecycle

    /// Start polling the queue for pending upload jobs.
    func start() {
        // Always log credentials status on start so we can diagnose upload issues.
        // This runs even in release builds because upload failures are user-facing.
        let config = (try? ConfigManager.load()) ?? R2Config()
        let hasToken: Bool = {
            guard let name = config.activeAccount else { return false }
            return (try? KeychainManager().getToken(account: name)) != nil
        }()
        NSLog("R2Drop UploadProcessor: start (activeAccount=%@, hasToken=%d, accounts=%d)",
              config.activeAccount ?? "nil", hasToken ? 1 : 0, config.accounts.count)
        #if DEBUG
        R2Log.upload.debug("UploadProcessor: start")
        #endif
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.processQueue() }
        }
        // Run immediately on start too
        processQueue()
    }

    /// Stop polling.
    func stop() {
        #if DEBUG
        R2Log.upload.debug("UploadProcessor: stop")
        #endif
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    /// Invoke the Rust engine to process all pending jobs for the active account.
    /// Credentials come from config.toml (account metadata) + Keychain (token).
    private func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Get active account credentials — log each failure path so we can diagnose
        guard let config = try? ConfigManager.load() else {
            NSLog("R2Drop UploadProcessor: failed to load config")
            return
        }
        guard let activeName = config.activeAccount else {
            NSLog("R2Drop UploadProcessor: no activeAccount set in config (accounts=%d)", config.accounts.count)
            return
        }
        guard let account = config.accounts.first(where: { $0.name == activeName }) else {
            NSLog("R2Drop UploadProcessor: activeAccount '%@' not found in config", activeName)
            return
        }
        guard !account.accountId.isEmpty else {
            NSLog("R2Drop UploadProcessor: account '%@' has empty accountId", activeName)
            return
        }
        guard let token = try? KeychainManager().getToken(account: activeName) else {
            NSLog("R2Drop UploadProcessor: no Keychain token for account '%@'", activeName)
            return
        }

        do {
            let completed = try r2Client.processQueue(
                accountId: account.accountId,
                token: token,
                accountName: activeName
            )
            #if DEBUG
            if completed > 0 {
                R2Log.upload.debug("UploadProcessor: processed \(completed) jobs")
            }
            #endif
        } catch {
            #if DEBUG
            R2Log.upload.error("UploadProcessor: processQueue failed: \(error)")
            #endif
        }
    }
}
