// R2Drop/App/Services/UploadProcessor.swift
// Periodically invokes the Rust upload engine to process pending jobs.
// Gets credentials from Config + Keychain for the active account.
// The Rust runner handles: recovery, retry with backoff, multipart upload,
// progress tracking, and history recording.
// Polling interval: 3 seconds. Safety timeout: 60 seconds per cycle.

import Foundation
import CryptoKit
import R2Core
import R2Bridge

@MainActor
final class UploadProcessor {

    private var timer: Timer?
    /// Observer for immediate queue processing when jobs are added/resumed.
    private var queueObserver: Any?
    private let r2Client = R2Client()
    private let pollInterval: TimeInterval = 3.0

    /// Guard against re-entrant processing if a previous cycle is still running.
    private var isProcessing = false
    /// Currently running detached processing task, if any.
    private var processingTask: Task<Void, Never>?

    /// Timestamp when processing started — used for safety timeout.
    private var processingStartTime: Date?

    /// Safety timeout: if a processing cycle takes longer than this, log a warning.
    /// We intentionally do not force-reset state because the Rust runner may still
    /// be legitimately working (multipart upload, backoff sleep, slow network).
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

        // Listen for queue changes (new job queued, resume, retry) to process immediately
        // instead of waiting for the next 3-second timer tick.
        queueObserver = NotificationCenter.default.addObserver(
            forName: .r2dropQueueDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.processQueue() }
        }
    }

    /// Stop polling.
    func stop() {
        #if DEBUG
        R2Log.upload.debug("UploadProcessor: stop")
        #endif
        if let obs = queueObserver {
            NotificationCenter.default.removeObserver(obs)
            queueObserver = nil
        }
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        processingStartTime = nil
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    /// Invoke the Rust engine to process all pending jobs for the active account.
    /// Credentials come from config.toml (account metadata) + Keychain (token).
    private func processQueue() {
        // Safety timeout: log if a cycle is taking unusually long, but do not
        // clear the guard. Force-resetting can start overlapping Rust runners.
        if isProcessing, let start = processingStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > processingTimeout {
                NSLog("R2Drop UploadProcessor: processing still running after %.0fs (skipping re-entry)", elapsed)
            }
            return
        }

        guard !isProcessing, processingTask == nil else { return }
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
        guard !account.tokenId.isEmpty else {
            NSLog("R2Drop UploadProcessor: account '%@' has no tokenId (S3 Access Key ID). Re-run onboarding to fix.", activeName)
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

        // Derive S3 credentials from the Cloudflare API token:
        // - Access Key ID: token UUID from /user/tokens/verify (stored in config as tokenId)
        // - Secret Access Key: SHA-256 hash of the raw API token
        let accountId = account.accountId
        let accessKeyId = account.tokenId
        let secretAccessKey = sha256Hex(token)
        let client = self.r2Client
        NSLog("R2Drop UploadProcessor: invoking Rust processQueue (account=%@, accountId=%@)", activeName, accountId)
        let task = Task.detached { [weak self] in
            do {
                let completed = try client.processQueue(
                    accountId: accountId,
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    accountName: activeName
                )
                NSLog("R2Drop UploadProcessor: Rust returned completed=%d", completed)
                #if DEBUG
                if completed > 0 {
                    await MainActor.run {
                        R2Log.upload.debug("UploadProcessor: processed \(completed) jobs")
                    }
                }
                #endif
                // Track completed uploads
                if completed > 0 {
                    await MainActor.run {
                        AnalyticsService.shared.trackUploadCompleted(
                            fileCount: Int(completed),
                            totalBytes: 0,  // Rust runner doesn't return byte totals
                            durationSeconds: 0
                        )
                    }
                }
            } catch {
                NSLog("R2Drop UploadProcessor: processQueue error: %@", "\(error)")
                #if DEBUG
                await MainActor.run {
                    R2Log.upload.error("UploadProcessor: processQueue failed: \(error)")
                }
                #endif
                // Track upload failure
                await MainActor.run {
                    AnalyticsService.shared.trackUploadFailed(
                        errorCode: String(describing: error),
                        retryCount: 0
                    )
                }
            }
            await MainActor.run {
                self?.processingTask = nil
                self?.isProcessing = false
                self?.processingStartTime = nil
            }
        }
        processingTask = task
    }

    // MARK: - Helpers

    /// Compute SHA-256 hash of a string and return it as a lowercase hex string.
    /// Used to derive the S3 secret_access_key from the Cloudflare API token.
    private func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
