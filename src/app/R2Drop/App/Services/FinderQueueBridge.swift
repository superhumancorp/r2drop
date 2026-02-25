// R2Drop/App/Services/FinderQueueBridge.swift
// Bridges uploads from the Finder extension to the main app's upload queue.
// The Finder extension writes jobs to the App Groups shared container queue.db.
// This service polls that database, transfers new jobs to ~/.r2drop/queue.db
// (where the Rust engine processes them), and deletes them from the shared DB.
// Polling interval: 2 seconds.

import Foundation
import R2Bridge
import R2Core

@MainActor
final class FinderQueueBridge {

    private var pollTimer: Timer?

    /// Start polling the App Groups queue for new jobs.
    func start() {
        #if DEBUG
        R2Log.service.debug("FinderQueueBridge: start")
        #endif
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.transferPendingJobs() }
        }
        // Run immediately on start too
        transferPendingJobs()
    }

    /// Stop polling.
    func stop() {
        #if DEBUG
        R2Log.service.debug("FinderQueueBridge: stop")
        #endif
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Transfer Logic

    /// Check the shared App Groups queue.db for pending jobs,
    /// copy them to the main queue.db, and delete from shared DB.
    /// Checks for conflicts with existing R2 objects before transferring (FR-065).
    private func transferPendingJobs() {
        // Open the shared (Finder extension) queue
        guard let sharedQM = try? QueueManager(
            appGroup: R2CoreConstants.appGroup
        ) else {
            NSLog("R2Drop FinderQueueBridge: failed to open shared App Groups queue.db")
            return
        }

        // Open the main app queue
        guard let mainQM = try? QueueManager() else {
            NSLog("R2Drop FinderQueueBridge: failed to open main queue.db")
            return
        }

        // Get all pending jobs from the shared queue
        guard let sharedJobs = try? sharedQM.listJobs(status: .pending),
              !sharedJobs.isEmpty else { return }

        #if DEBUG
        R2Log.service.debug("FinderQueueBridge: transferPendingJobs found \(sharedJobs.count) jobs")
        #endif

        // Transfer each job with conflict checking
        for job in sharedJobs {
            do {
                var r2Key = job.r2Key

                // Check for conflicts if we can get account credentials
                if let resolution = checkConflict(job: job) {
                    switch resolution {
                    case .skip:
                        // User chose to skip — delete from shared queue, don't transfer
                        try sharedQM.deleteJob(id: job.id)
                        #if DEBUG
                        R2Log.service.debug("FinderQueueBridge: job \(job.id) skipped due to conflict")
                        #endif
                        continue
                    case .rename:
                        r2Key = ConflictManager.renamedKey(job.r2Key)
                        #if DEBUG
                        R2Log.service.debug("FinderQueueBridge: job \(job.id) renamed")
                        #endif
                    case .overwrite:
                        break // Transfer as-is
                    }
                }

                _ = try mainQM.insertJob(
                    filePath: job.filePath,
                    r2Key: r2Key,
                    bucket: job.bucket,
                    accountName: job.accountName,
                    totalBytes: job.totalBytes
                )
                try sharedQM.deleteJob(id: job.id)
                #if DEBUG
                R2Log.service.debug("FinderQueueBridge: job \(job.id) transferred successfully")
                #endif
            } catch {
                #if DEBUG
                R2Log.service.error("FinderQueueBridge: Failed to transfer job \(job.id): \(error)")
                #endif
                NSLog("R2Drop: Failed to transfer job \(job.id): \(error)")
            }
        }
    }

    /// Check if an R2 object already exists for this job and resolve the conflict.
    /// Returns nil if no conflict, or the user's choice if conflict detected.
    private func checkConflict(job: UploadJob) -> ConflictChoice? {
        // Get account credentials from config + Keychain
        guard let config = try? ConfigManager.load(),
              let account = config.accounts.first(where: { $0.name == job.accountName }),
              !account.accountId.isEmpty,
              let token = try? KeychainManager().getToken(account: account.name) else { return nil }

        // Check if object exists via FFI
        let client = R2Client()
        guard let info = try? client.headObjectSync(
            accountId: account.accountId, token: token,
            bucket: job.bucket, key: job.r2Key
        ) else { return nil }

        // Object exists — check "Apply to all" or show dialog
        if let stored = ConflictManager.shared.storedChoice() {
            return stored
        }

        let fileName = URL(fileURLWithPath: job.filePath).lastPathComponent
        let objInfo = ExistingObjectInfo(
            contentLength: info.contentLength,
            lastModified: info.lastModifiedDate
        )
        let result = ConflictDialog.show(
            fileName: fileName, localSize: job.totalBytes, existingInfo: objInfo
        )
        ConflictManager.shared.recordChoice(result.choice, applyToAll: result.applyToAll)
        return result.choice
    }
}
