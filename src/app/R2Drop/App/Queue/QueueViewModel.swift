// R2Drop/App/Queue/QueueViewModel.swift
// Polls queue.db every 1.5 seconds to get fresh upload job data.
// Tracks per-job upload speeds by comparing bytes between polls.
// Provides pause/resume/cancel actions and aggregate statistics.

import Foundation
import R2Core

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
    private let pollInterval: TimeInterval = 1.5

    // MARK: - Lifecycle

    func start() {
        #if DEBUG
        R2Log.ui.debug("QueueViewModel: start")
        #endif
        poll() // Immediate first poll
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
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
        let allJobs = (try? qm.listAllJobs()) ?? []

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

        self.jobs = visible
        self.jobSpeeds = newSpeeds
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
        guard let qm = try? QueueManager() else { return }
        try? qm.updateStatus(id: job.id, status: .paused)
        poll()
    }

    func resumeJob(_ job: UploadJob) {
        #if DEBUG
        R2Log.ui.debug("QueueViewModel: resumeJob id=\(job.id)")
        #endif
        guard let qm = try? QueueManager() else { return }
        try? qm.updateStatus(id: job.id, status: .pending)
        poll()
    }

    func cancelJob(_ job: UploadJob) {
        #if DEBUG
        R2Log.ui.debug("QueueViewModel: cancelJob id=\(job.id)")
        #endif
        guard let qm = try? QueueManager() else { return }
        try? qm.deleteJob(id: job.id)
        poll()
    }

    // MARK: - Drag-and-Drop Upload

    /// Queue a file dropped onto the Uploads tab for upload.
    /// Uses the active account's config for bucket, path, and credentials.
    func queueDroppedFile(_ url: URL) {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let activeName = config.activeAccount,
              let account = config.accounts.first(where: { $0.name == activeName }) else {
            #if DEBUG
            R2Log.ui.debug("QueueViewModel: queueDroppedFile — no active account")
            #endif
            return
        }

        guard let qm = try? QueueManager() else { return }
        let name = url.lastPathComponent
        let r2Key = account.path.isEmpty ? name : "\(account.path)/\(name)"
        let size = fileSize(url)

        _ = try? qm.insertJob(
            filePath: url.path,
            r2Key: r2Key,
            bucket: account.bucket,
            accountName: account.name,
            totalBytes: size
        )
        #if DEBUG
        R2Log.ui.debug("QueueViewModel: queued dropped file \(name) (\(size) bytes)")
        #endif
        poll() // Refresh immediately
    }

    /// Get the file size in bytes.
    private func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64 ?? 0
    }

    // MARK: - Browse URL (FR-040)

    /// Construct the Cloudflare R2 dashboard URL for a job's bucket.
    func browseURL(for job: UploadJob) -> URL? {
        let config = (try? ConfigManager.load()) ?? R2Config()
        guard let account = config.accounts.first(where: { $0.name == job.accountName }),
              !account.accountId.isEmpty else {
            // Fallback: open generic R2 dashboard
            return URL(string: "https://dash.cloudflare.com/")
        }
        let urlStr = "https://dash.cloudflare.com/\(account.accountId)/r2/default/buckets/\(job.bucket)"
        return URL(string: urlStr)
    }
}
