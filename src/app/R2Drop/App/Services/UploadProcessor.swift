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

        // Get active account credentials
        guard let config = try? ConfigManager.load(),
              let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }),
              !account.accountId.isEmpty,
              let token = try? KeychainManager().getToken(account: activeName)
        else { return }

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
