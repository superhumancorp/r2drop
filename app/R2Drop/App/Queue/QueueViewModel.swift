// R2Drop/App/Queue/QueueViewModel.swift
// Polls queue.db every 1.5 seconds to get fresh upload job data.
// Tracks per-job upload speeds by comparing bytes between polls.
// Provides pause/resume/cancel actions and aggregate statistics.

import AppKit
import Foundation
import R2Core

private struct QueueDropBuildResult: Sendable {
    let isDirectory: Bool
    let drafts: [UploadJobDraft]
}

private struct QueueDropInsertResult: Sendable {
    let insertedCount: Int
    let containsDirectory: Bool
}

@MainActor
final class QueueViewModel: ObservableObject {

    // MARK: - Published State

    /// All active jobs (pending, uploading, paused, failed). Sorted by ID ascending.
    @Published var jobs: [UploadJob] = []

    /// Per-job upload speed in bytes/second. Keyed by job ID.
    @Published private(set) var jobSpeeds: [Int64: Double] = [:]

    // MARK: - Private

    private var timer: Timer?
    private var previousBytes: [Int64: UInt64] = [:]
    /// Jobs the user asked to cancel while they were actively uploading.
    /// We first pause them, then delete once they are no longer uploading to
    /// avoid deleting rows that the Rust runner is still updating.
    private var pendingCancelDeletes: Set<Int64> = []
    private let pollInterval: TimeInterval = 0.5
    private let largeBacklogDisplayLimit = 200

    // MARK: - Lifecycle

    func start() {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: start")
        #endif
        poll()  // Immediate first poll
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: stop")
        #endif
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    /// Read queue.db and update published state.
    private func poll() {
        guard let qm = try? QueueManager() else { return }
        var allJobs = (try? qm.listAllJobs()) ?? []

        // Finalize deferred cancels only after the job leaves `uploading`.
        if !pendingCancelDeletes.isEmpty {
            var remaining = Set<Int64>()
            var deletedAny = false
            for id in pendingCancelDeletes {
                if let job = allJobs.first(where: { $0.id == id }), job.status == .uploading {
                    remaining.insert(id)
                    continue
                }
                _ = try? qm.deleteJob(id: id)
                deletedAny = true
            }
            pendingCancelDeletes = remaining
            if deletedAny {
                allJobs = (try? qm.listAllJobs()) ?? allJobs
            }
        }

        // Keep non-completed jobs (pending, uploading, paused, failed)
        // plus recently completed jobs (last 30 seconds) for visual feedback
        let activeJobs = allJobs.filter { $0.status != .completed }
        let recentCompleted = allJobs.filter { $0.status == .completed && isRecent($0) }
        let visible = (activeJobs + recentCompleted).sorted { $0.id < $1.id }

        // Calculate per-job speeds based on bytes delta since last poll
        var newSpeeds: [Int64: Double] = [:]
        for job in visible where job.status == .uploading {
            let prev = previousBytes[job.id] ?? job.bytesUploaded
            let delta = job.bytesUploaded > prev ? job.bytesUploaded - prev : 0
            newSpeeds[job.id] = Double(delta) / pollInterval
        }

        // Update previous bytes for next poll
        var newPrevious: [Int64: UInt64] = [:]
        for job in visible {
            newPrevious[job.id] = job.bytesUploaded
        }

        if self.jobs != visible {
            self.jobs = visible
        }
        if self.jobSpeeds != newSpeeds {
            self.jobSpeeds = newSpeeds
        }
        self.previousBytes = newPrevious
    }

    /// Check if a completed job finished within the last 30 seconds.
    private func isRecent(_ job: UploadJob) -> Bool {
        guard !job.updatedAt.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // SQLite datetime format: "YYYY-MM-DD HH:MM:SS"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(identifier: "UTC")
        guard let date = df.date(from: job.updatedAt) else { return false }
        return Date().timeIntervalSince(date) < 30
    }

    // MARK: - Aggregate Statistics

    /// Average upload speed across all actively uploading jobs.
    var aggregateSpeed: Double {
        let speeds = jobs.filter { $0.status == .uploading }.compactMap { jobSpeeds[$0.id] }
        guard !speeds.isEmpty else { return 0 }
        return speeds.reduce(0, +)
    }

    /// Number of completed jobs (from the visible set).
    var completedCount: Int {
        jobs.filter { $0.status == .completed }.count
    }

    /// Total number of visible jobs.
    var totalCount: Int {
        jobs.count
    }

    /// True if any job is currently uploading.
    var hasActiveUploads: Bool {
        jobs.contains { $0.status == .uploading }
    }

    var failedCount: Int {
        jobs.filter { $0.status == .failed }.count
    }

    var clearableCount: Int {
        jobs.filter { Self.isClearableStatus($0.status) }.count
    }

    var hasLargeBacklog: Bool {
        jobs.count > largeBacklogDisplayLimit
    }

    var displayedJobs: [UploadJob] {
        guard hasLargeBacklog else { return jobs }
        var displayed: [UploadJob] = []
        displayed.reserveCapacity(largeBacklogDisplayLimit)

        for job in jobs where job.status != .failed {
            displayed.append(job)
            if displayed.count == largeBacklogDisplayLimit {
                return displayed
            }
        }

        for job in jobs where job.status == .failed {
            displayed.append(job)
            if displayed.count == largeBacklogDisplayLimit {
                return displayed
            }
        }

        return displayed
    }

    var hiddenJobCount: Int {
        max(0, jobs.count - displayedJobs.count)
    }

    private static func isClearableStatus(_ status: UploadStatus) -> Bool {
        switch status {
        case .pending, .paused, .failed:
            return true
        case .uploading, .completed:
            return false
        }
    }

    // MARK: - Speed Lookup

    /// Get formatted speed string for a job.
    func speed(for job: UploadJob) -> Double {
        jobSpeeds[job.id] ?? 0
    }

    // MARK: - Actions (FR-039)

    func pauseJob(_ job: UploadJob) {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: pauseJob id=\(job.id)")
        #endif
        // P0: queue_pause_requested
        TelemetryService.shared.track(
            "queue_pause_requested",
            properties: [
                "job_id": job.id,
                "status_before": String(describing: job.status),
            ])
        guard let qm = try? QueueManager() else { return }
        try? qm.updateStatus(id: job.id, status: .paused)
        poll()
    }
    func resumeJob(_ job: UploadJob) {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: resumeJob id=\(job.id)")
        #endif
        // P0: queue_resume_requested
        TelemetryService.shared.track(
            "queue_resume_requested",
            properties: [
                "job_id": job.id,
                "status_before": String(describing: job.status),
            ])
        guard let qm = try? QueueManager() else { return }
        // Reset retry_count so the Rust engine gives this job a fresh set of attempts.
        // Without this, jobs that already hit MAX_RETRIES would immediately re-fail.
        try? qm.resetRetryCount(id: job.id)
        try? qm.updateStatus(id: job.id, status: .pending)
        poll()
        // Trigger immediate processing instead of waiting for the 3s timer.
        NotificationCenter.default.post(name: .r2dropQueueDidChange, object: nil)
    }

    func cancelJob(_ job: UploadJob) {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: cancelJob id=\(job.id)")
        #endif
        guard let qm = try? QueueManager() else { return }
        // P0: queue_cancel_requested
        let deferredDelete = job.status == .uploading
        TelemetryService.shared.track(
            "queue_cancel_requested",
            properties: [
                "job_id": job.id,
                "status_before": String(describing: job.status),
                "deferred_delete": deferredDelete,
            ])
        if deferredDelete {
            // Request a pause first so the runner stops after the current chunk.
            // Deleting immediately can race with runner status/progress updates.
            try? qm.updateStatus(id: job.id, status: .paused)
            pendingCancelDeletes.insert(job.id)
            poll()
            return
        }
        pendingCancelDeletes.remove(job.id)
        _ = try? qm.deleteJob(id: job.id)
        poll()
    }

    func retryFailedJobs() {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: retryFailedJobs count=\(self.failedCount)")
        #endif
        guard let qm = try? QueueManager() else { return }
        let requested = failedCount
        let retried = (try? qm.retryFailedJobs()) ?? 0
        TelemetryService.shared.track(
            "queue_bulk_retry_failed_requested",
            properties: [
                "requested_count": requested,
                "retried_count": retried,
            ])
        poll()
        if retried > 0 {
            NotificationCenter.default.post(name: .r2dropQueueDidChange, object: nil)
        }
    }

    func clearFailedJobs() {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: clearFailedJobs count=\(self.failedCount)")
        #endif
        guard let qm = try? QueueManager() else { return }
        let requested = failedCount
        let removed = (try? qm.deleteJobs(status: .failed)) ?? 0
        TelemetryService.shared.track(
            "queue_bulk_clear_failed_requested",
            properties: [
                "requested_count": requested,
                "removed_count": removed,
            ])
        poll()
    }

    func clearInactiveJobs() {
        #if DEBUG
            R2Log.ui.debug("QueueViewModel: clearInactiveJobs count=\(self.clearableCount)")
        #endif
        guard let qm = try? QueueManager() else { return }
        let requested = clearableCount
        let removed = (try? qm.deleteJobs(statuses: [.pending, .paused, .failed])) ?? 0
        pendingCancelDeletes.removeAll()
        TelemetryService.shared.track(
            "queue_bulk_clear_inactive_requested",
            properties: [
                "requested_count": requested,
                "removed_count": removed,
            ])
        poll()
    }

    /// Copy the public URL for a completed upload to the clipboard.
    func copyURL(for job: UploadJob) {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let account = config.accounts.first(where: { $0.name == job.accountName }) else {
            return
        }

        // Build URL: prefer custom domain, fall back to account-based R2 URL.
        // Percent-encode each path segment (spaces → %20, etc.) without encoding
        // the '/' separators between segments (RFC 3986).
        let r2KeyRaw = job.r2Key.hasPrefix("/") ? String(job.r2Key.dropFirst()) : job.r2Key
        let r2Key =
            r2KeyRaw
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        let url: String
        if let domain = account.customDomain, !domain.isEmpty {
            let base = domain.hasSuffix("/") ? String(domain.dropLast()) : domain
            let scheme = base.hasPrefix("http") ? "" : "https://"
            url = "\(scheme)\(base)/\(r2Key)"
        } else if !account.accountId.isEmpty {
            url = "https://\(account.bucket).\(account.accountId).r2.cloudflarestorage.com/\(r2Key)"
        } else {
            url = "https://\(account.bucket).r2.cloudflarestorage.com/\(r2Key)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        // P1: queue_copy_url_clicked
        TelemetryService.shared.track(
            "queue_copy_url_clicked",
            properties: [
                "job_id": job.id,
                "has_custom_domain": account.customDomain != nil
                    && !(account.customDomain?.isEmpty ?? true),
                "surface": "queue",
            ])

        #if DEBUG
            R2Log.ui.debug("QueueViewModel: copyURL job=\(job.id) url=\(url)")
        #endif
    }

    // MARK: - Drag-and-Drop Upload

    /// Queue a file or folder dropped onto the Uploads tab for upload.
    /// If a folder is dropped, recursively enumerates all files and queues them individually.
    /// Uses the active account's config for bucket, path, and credentials.
    func queueDroppedFile(_ url: URL) {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
            let account = config.accounts.first(where: { $0.name == activeName })
        else {
            #if DEBUG
                R2Log.ui.debug("QueueViewModel: queueDroppedFile — no active account")
            #endif

            // P1: upload_no_active_account_blocked
            TelemetryService.shared.track(
                "upload_no_active_account_blocked",
                properties: [
                    "entrypoint": "queue_tab_drag"
                ])

            return
        }

        // Get exclusion patterns from config
        let exclusions = config.preferences.exclusionPatterns
        let accountName = account.name
        let bucket = account.bucket
        let pathPrefix = account.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let droppedName = url.lastPathComponent

        Task {
            [weak self, url, activeName, accountName, bucket, pathPrefix, exclusions, droppedName]
            in
            let result = await Task.detached(priority: .userInitiated) {
                guard let qm = try? QueueManager() else {
                    return QueueDropInsertResult(insertedCount: 0, containsDirectory: false)
                }
                let build = Self.buildUploadJobDrafts(
                    for: url,
                    pathPrefix: pathPrefix,
                    bucket: bucket,
                    accountName: accountName,
                    exclusions: exclusions
                )
                let insertedCount = (try? qm.insertJobs(build.drafts)) ?? 0
                return QueueDropInsertResult(
                    insertedCount: insertedCount,
                    containsDirectory: build.isDirectory
                )
            }.value

            guard let self, result.insertedCount > 0 else { return }

            #if DEBUG
                R2Log.ui.debug("QueueViewModel: queued dropped file(s) from \(droppedName)")
            #endif
            // P1: queue_tab_files_dropped
            TelemetryService.shared.track(
                "queue_tab_files_dropped",
                properties: [
                    "file_count": result.insertedCount,
                    "contains_directory": result.containsDirectory,
                ])

            // P0: upload_enqueue_requested (from queue drop)
            TelemetryService.shared.track(
                "upload_enqueue_requested",
                properties: [
                    "entrypoint": "queue_drop",
                    "file_count": result.insertedCount,
                    "contains_directory": result.containsDirectory,
                    "account_name_hash": TelemetrySanitizer.hash(activeName),
                    "bucket_hash": TelemetrySanitizer.hash(bucket),
                ])
            self.poll()  // Refresh immediately
            // Trigger immediate processing instead of waiting for the 3s timer.
            NotificationCenter.default.post(name: .r2dropQueueDidChange, object: nil)
        }
    }

    private nonisolated static func buildUploadJobDrafts(
        for url: URL,
        pathPrefix: String,
        bucket: String,
        accountName: String,
        exclusions: [String]
    ) -> QueueDropBuildResult {
        let isDirectory =
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        var drafts: [UploadJobDraft] = []

        if isDirectory {
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let baseName = url.lastPathComponent
            while let fileURL = enumerator?.nextObject() as? URL {
                let isFile =
                    (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile
                    ?? false
                guard isFile else { continue }
                let fileName = fileURL.lastPathComponent
                guard !matchesExclusionPattern(fileName, patterns: exclusions) else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                let name = "\(baseName)/\(relativePath)"
                let r2Key = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
                drafts.append(
                    UploadJobDraft(
                        filePath: fileURL.path,
                        r2Key: r2Key,
                        bucket: bucket,
                        accountName: accountName,
                        totalBytes: fileSize(fileURL)
                    ))
            }
        } else {
            let fileName = url.lastPathComponent
            guard !matchesExclusionPattern(fileName, patterns: exclusions) else {
                #if DEBUG
                    R2Log.ui.debug("QueueViewModel: skipped excluded file \(fileName)")
                #endif
                return QueueDropBuildResult(isDirectory: false, drafts: [])
            }
            let r2Key = pathPrefix.isEmpty ? fileName : "\(pathPrefix)/\(fileName)"
            drafts.append(
                UploadJobDraft(
                    filePath: url.path,
                    r2Key: r2Key,
                    bucket: bucket,
                    accountName: accountName,
                    totalBytes: fileSize(url)
                ))
        }

        return QueueDropBuildResult(isDirectory: isDirectory, drafts: drafts)
    }

    /// Get the file size in bytes.
    private nonisolated static func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    /// Check if a filename matches any of the exclusion patterns.
    /// Supports suffix wildcards ("*.tmp"), prefix wildcards ("._*"),
    /// contains wildcards ("foo*bar"), and exact matches ("Thumbs.db").
    private nonisolated static func matchesExclusionPattern(_ filename: String, patterns: [String])
        -> Bool
    {
        for pattern in patterns {
            if pattern.contains("*") {
                if pattern.hasPrefix("*") {
                    // Suffix match: "*.tmp" matches "file.tmp"
                    let suffix = String(pattern.dropFirst())
                    if filename.hasSuffix(suffix) { return true }
                } else if pattern.hasSuffix("*") {
                    // Prefix match: "._*" matches "._DS_Store"
                    let prefix = String(pattern.dropLast())
                    if filename.hasPrefix(prefix) { return true }
                } else {
                    // Contains match: "foo*bar"
                    let parts = pattern.split(separator: "*", maxSplits: 1)
                    if parts.count == 2 {
                        if filename.hasPrefix(String(parts[0]))
                            && filename.hasSuffix(String(parts[1]))
                        {
                            return true
                        }
                    }
                }
            } else {
                // Exact match
                if filename == pattern { return true }
            }
        }
        return false
    }

    // MARK: - Browse URL (FR-040)

    /// Construct the Cloudflare R2 dashboard URL for a job's bucket.
    func browseURL(for job: UploadJob) -> URL? {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let account = config.accounts.first(where: { $0.name == job.accountName }),
            !account.accountId.isEmpty
        else {
            // Fallback: open generic R2 dashboard
            return URL(string: "https://dash.cloudflare.com/")
        }
        let urlStr =
            "https://dash.cloudflare.com/\(account.accountId)/r2/default/buckets/\(job.bucket)"
        return URL(string: urlStr)
    }
}
