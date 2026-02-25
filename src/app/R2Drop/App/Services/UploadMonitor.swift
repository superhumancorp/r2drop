// R2Drop/App/Services/UploadMonitor.swift
// Polls queue.db to detect upload state transitions and trigger notifications.
// Tracks which jobs were previously seen in each status so it can detect
// when a job transitions to completed, failed, or paused.
// Separate from QueueViewModel to keep UI polling decoupled from notification logic.

import Foundation
import R2Core

// MARK: - UploadMonitor

/// Monitors the upload queue for state transitions and fires notifications.
/// Detects: completed uploads (single + batch), failed uploads, and paused uploads.
@MainActor
final class UploadMonitor {

    private var timer: Timer?
    private let pollInterval: TimeInterval = 3.0

    /// Job IDs that were actively uploading or pending on the previous poll.
    /// Used to detect transitions to completed/failed.
    private var previousActiveIds: Set<Int64> = []

    /// Job IDs we've already notified about (to avoid duplicate notifications).
    private var notifiedCompleteIds: Set<Int64> = []
    private var notifiedFailedIds: Set<Int64> = []

    /// Track whether we were previously online (for paused-by-network detection).
    private var hadActiveUploads = false

    // MARK: - Lifecycle

    func start() {
        #if DEBUG
        R2Log.upload.debug("UploadMonitor: start")
        #endif
        // Seed the initial state so we don't fire notifications for pre-existing jobs
        seedInitialState()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        #if DEBUG
        R2Log.upload.debug("UploadMonitor: stop")
        #endif
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    /// Capture current job IDs so we don't notify on app launch for old state.
    private func seedInitialState() {
        guard let qm = try? QueueManager() else { return }
        let allJobs = (try? qm.listAllJobs()) ?? []

        previousActiveIds = Set(
            allJobs.filter { $0.status == .uploading || $0.status == .pending }
                   .map { $0.id }
        )

        // Mark all currently completed/failed as already notified
        notifiedCompleteIds = Set(
            allJobs.filter { $0.status == .completed }.map { $0.id }
        )
        notifiedFailedIds = Set(
            allJobs.filter { $0.status == .failed }.map { $0.id }
        )

        hadActiveUploads = !previousActiveIds.isEmpty
        #if DEBUG
        R2Log.upload.debug("UploadMonitor: seedInitialState active=\(self.previousActiveIds.count) completed=\(self.notifiedCompleteIds.count) failed=\(self.notifiedFailedIds.count)")
        #endif
    }

    /// Check for state transitions and fire notifications.
    private func poll() {
        guard let qm = try? QueueManager() else { return }
        let allJobs = (try? qm.listAllJobs()) ?? []

        let currentActiveIds = Set(
            allJobs.filter { $0.status == .uploading || $0.status == .pending }
                   .map { $0.id }
        )

        // Detect newly completed jobs: were active before, now completed
        let completedJobs = allJobs.filter { job in
            job.status == .completed
            && previousActiveIds.contains(job.id)
            && !notifiedCompleteIds.contains(job.id)
        }

        // Detect newly failed jobs: were active before, now failed
        let failedJobs = allJobs.filter { job in
            job.status == .failed
            && previousActiveIds.contains(job.id)
            && !notifiedFailedIds.contains(job.id)
        }

        // Detect paused-by-network: had active uploads, now all paused
        let pausedJobs = allJobs.filter { $0.status == .paused }
        let wasPaused = hadActiveUploads
            && currentActiveIds.isEmpty
            && !pausedJobs.isEmpty
            && completedJobs.isEmpty

        // Fire notifications
        let service = NotificationService.shared

        if completedJobs.count == 1, let job = completedJobs.first {
            // Single upload completed — include URL from history if available
            let url = lookupURL(for: job)
            service.notifyUploadComplete(fileName: fileNameFromPath(job.filePath), url: url)

            // P0: upload_completed
            TelemetryService.shared.track("upload_completed", properties: [
                "job_id": job.id,
                "size_bucket": TelemetrySanitizer.sizeBucket(job.totalBytes),
                "account_name_hash": TelemetrySanitizer.hash(job.accountName),
                "bucket_hash": TelemetrySanitizer.hash(job.bucket),
                "used_custom_domain_url": url?.contains("r2.cloudflarestorage.com") == false
            ])

            #if DEBUG
            R2Log.upload.debug("UploadMonitor: notified single upload complete")
            #endif
        } else if completedJobs.count > 1 {
            // Batch completed
            service.notifyBatchComplete(count: completedJobs.count)

            // P0: upload_batch_completed
            let totalBytes = completedJobs.reduce(UInt64(0)) { $0 + $1.totalBytes }
            TelemetryService.shared.track("upload_batch_completed", properties: [
                "count": completedJobs.count,
                "total_bytes": TelemetrySanitizer.sizeBucket(totalBytes)
            ])

            #if DEBUG
            R2Log.upload.debug("UploadMonitor: notified batch complete count=\(completedJobs.count)")
            #endif
        }

        for job in failedJobs {
            let error = job.errorMessage ?? "Unknown error"
            service.notifyUploadFailed(
                fileName: fileNameFromPath(job.filePath),
                error: error,
                jobId: job.id
            )

            // P0: upload_failed
            TelemetryService.shared.track("upload_failed", properties: [
                "job_id": job.id,
                "error_type": String(describing: type(of: error)),
                "error_message_hash": TelemetrySanitizer.errorHash(error)
            ])
        }
        #if DEBUG
        if !failedJobs.isEmpty {
            R2Log.upload.debug("UploadMonitor: notified failed uploads count=\(failedJobs.count)")
        }
        #endif

        if wasPaused {
            service.notifyUploadPaused()
            #if DEBUG
            R2Log.upload.debug("UploadMonitor: notified uploads paused")
            #endif
        }

        // Update tracking state
        for job in completedJobs { notifiedCompleteIds.insert(job.id) }
        for job in failedJobs { notifiedFailedIds.insert(job.id) }
        previousActiveIds = currentActiveIds
        hadActiveUploads = !currentActiveIds.isEmpty

        // Prune old notified IDs to avoid unbounded growth
        // Keep only IDs that still exist in the database
        let allIds = Set(allJobs.map { $0.id })
        notifiedCompleteIds = notifiedCompleteIds.intersection(allIds)
        notifiedFailedIds = notifiedFailedIds.intersection(allIds)
    }

    // MARK: - Helpers

    /// Extract the file name from a full path.
    private func fileNameFromPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Look up the R2 URL for a completed job from history.db.
    /// Returns the custom domain URL if configured, otherwise the raw R2 URL.
    private func lookupURL(for job: UploadJob) -> String? {
        guard let hm = try? HistoryManager() else { return nil }
        let entries = (try? hm.listEntries()) ?? []
        // Find the most recent history entry matching this job's key and bucket
        let match = entries.first { $0.r2Key == job.r2Key && $0.bucket == job.bucket && $0.accountName == job.accountName }
        return match?.url
    }
}
