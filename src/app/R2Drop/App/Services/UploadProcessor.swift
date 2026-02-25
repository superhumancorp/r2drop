// R2Drop/App/Services/UploadProcessor.swift
// Periodically invokes the Rust upload engine to process pending jobs.
// Gets credentials from Config + Keychain for the active account.
// The Rust runner handles: recovery, retry with backoff, multipart upload,
// progress tracking, and history recording.
// Polling interval: 3 seconds. Safety timeout: 60 seconds per cycle.

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

    /// Timestamp when processing started — used for safety timeout.
    private var processingStartTime: Date?

    /// Safety timeout: if a processing cycle takes longer than this, reset isProcessing.
    /// Prevents the processor from getting permanently stuck.
    private let processingTimeout: TimeInterval = 60.0

    // MARK: - Lifecycle

    /// Start polling the queue for pending upload jobs.
    func start() {
        // Always log credentials status on start so we can diagnose upload issues.
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
        // Safety timeout: if previous cycle exceeded timeout, force-reset
        if isProcessing, let start = processingStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > processingTimeout {
                NSLog("R2Drop UploadProcessor: safety timeout after %.0fs — resetting isProcessing", elapsed)
                isProcessing = false
                processingStartTime = nil
            } else {
                return // Still within timeout, skip this cycle
            }
        }

        guard !isProcessing else { return }
        isProcessing = true
        processingStartTime = Date()

        // Get active account credentials — log each failure path so we can diagnose
        guard let config = try? ConfigManager.load() else {
            NSLog("R2Drop UploadProcessor: failed to load config")
            isProcessing = false
            processingStartTime = nil
            return
        }
        guard let activeName = config.activeAccount else {
            // Not an error for first-time users. Only log once per minute.
            #if DEBUG
            R2Log.upload.debug("UploadProcessor: no activeAccount set in config (accounts=\(config.accounts.count))")
            #endif
            isProcessing = false
            processingStartTime = nil
            return
        }
        guard let account = config.accounts.first(where: { $0.name == activeName }) else {
            NSLog("R2Drop UploadProcessor: activeAccount '%@' not found in config", activeName)
            isProcessing = false
            processingStartTime = nil
            return
        }
        guard !account.accountId.isEmpty else {
            NSLog("R2Drop UploadProcessor: account '%@' has empty accountId", activeName)
            isProcessing = false
            processingStartTime = nil
            return
        }
        guard let token = try? KeychainManager().getToken(account: activeName) else {
            NSLog("R2Drop UploadProcessor: no Keychain token for account '%@'", activeName)
            isProcessing = false
            processingStartTime = nil
            return
        }

        // Run the Rust FFI call on a background thread to avoid blocking the main actor.
        // The Rust engine internally uses block_on() which blocks the calling thread.
        let accountId = account.accountId
        let client = self.r2Client
        Task.detached { [weak self] in
            do {
                let completed = try client.processQueue(
                    accountId: accountId,
                    token: token,
                    accountName: activeName
                )
                #if DEBUG
                if completed > 0 {
                    await MainActor.run {
                        R2Log.upload.debug("UploadProcessor: processed \(completed) jobs")
                    }
                }
                #endif
            } catch {
                NSLog("R2Drop UploadProcessor: processQueue error: %@", "\(error)")
                #if DEBUG
                await MainActor.run {
                    R2Log.upload.error("UploadProcessor: processQueue failed: \(error)")
                }
                #endif
            }
            await MainActor.run {
                self?.isProcessing = false
                self?.processingStartTime = nil
            }
        }
    }
}
