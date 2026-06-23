// Packages/R2Core/Sources/R2Core/QueueManager.swift
// Swift interface to the persistent upload queue (queue.db).
// Uses direct SQLite3 access so both the main app and Finder extension
// can read/write the shared database via App Groups.
// Schema matches r2-core/src/queue.rs exactly.

import Foundation

/// A job to insert into the upload queue.
/// Batch insert callers use this to avoid one SQLite transaction per file.
public struct UploadJobDraft: Equatable, Sendable {
    public var filePath: String
    public var r2Key: String
    public var bucket: String
    public var accountName: String
    public var totalBytes: UInt64
    public var status: UploadStatus
    public var errorMessage: String?

    public init(
        filePath: String,
        r2Key: String,
        bucket: String,
        accountName: String,
        totalBytes: UInt64 = 0,
        status: UploadStatus = .pending,
        errorMessage: String? = nil
    ) {
        self.filePath = filePath
        self.r2Key = r2Key
        self.bucket = bucket
        self.accountName = accountName
        self.totalBytes = totalBytes
        self.status = status
        self.errorMessage = errorMessage
    }
}

// MARK: - QueueManager

/// Manages the persistent upload queue backed by SQLite.
/// The queue.db file is shared between the main app and Finder extension
/// via the App Groups container.
public final class QueueManager {
    private let db: SQLiteConnection

    /// Open (or create) the queue database at the given path.
    public init(path: String) throws {
        db = try SQLiteConnection(path: path)
        try createTable()
    }

    /// Open the queue database in the default config directory.
    public convenience init() throws {
        let dir = ConfigManager.configDir()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        try self.init(path: dir.appendingPathComponent("queue.db").path)
    }

    /// Open the queue database in the App Groups shared container.
    /// Use this from the Finder extension.
    public convenience init(appGroup: String) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            throw SQLiteError.open("App Group container not found: \(appGroup)")
        }
        try self.init(path: containerURL.appendingPathComponent("queue.db").path)
    }

    // MARK: - CRUD Operations

    /// Insert a new upload job. Returns the auto-generated row ID.
    public func insertJob(
        filePath: String,
        r2Key: String,
        bucket: String,
        accountName: String,
        totalBytes: UInt64 = 0
    ) throws -> Int64 {
        try db.run(
            """
            INSERT INTO jobs (file_path, r2_key, bucket, account_name, status, total_bytes)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            """,
            params: [filePath, r2Key, bucket, accountName, UploadStatus.pending.rawValue, totalBytes]
        )
        return db.lastInsertRowId()
    }

    /// Insert multiple upload jobs in a single SQLite transaction.
    /// Returns the number of inserted rows.
    @discardableResult
    public func insertJobs(_ jobs: [UploadJobDraft]) throws -> Int {
        guard !jobs.isEmpty else { return 0 }

        try db.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            var inserted = 0
            for job in jobs {
                inserted += try db.run(
                    """
                    INSERT INTO jobs (
                        file_path, r2_key, bucket, account_name,
                        status, total_bytes, error_message
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                    """,
                    params: [
                        job.filePath,
                        job.r2Key,
                        job.bucket,
                        job.accountName,
                        job.status.rawValue,
                        job.totalBytes,
                        job.errorMessage
                    ]
                )
            }
            try db.execute("COMMIT")
            return inserted
        } catch {
            _ = try? db.execute("ROLLBACK")
            throw error
        }
    }

    /// Fetch a single job by ID. Returns nil if not found.
    public func getJob(id: Int64) throws -> UploadJob? {
        let rows = try db.query(
            """
            SELECT id, file_path, r2_key, bucket, account_name, status,
                   bytes_uploaded, total_bytes, upload_id, error_message,
                   created_at, updated_at
            FROM jobs WHERE id = ?1
            """,
            params: [id]
        )
        return rows.first.map { rowToJob($0) }
    }

    /// List all jobs with a given status.
    public func listJobs(status: UploadStatus) throws -> [UploadJob] {
        let rows = try db.query(
            """
            SELECT id, file_path, r2_key, bucket, account_name, status,
                   bytes_uploaded, total_bytes, upload_id, error_message,
                   created_at, updated_at
            FROM jobs WHERE status = ?1 ORDER BY id ASC
            """,
            params: [status.rawValue]
        )
        return rows.map { rowToJob($0) }
    }

    /// List all jobs (any status), ordered by most recent first.
    public func listAllJobs() throws -> [UploadJob] {
        let rows = try db.query(
            """
            SELECT id, file_path, r2_key, bucket, account_name, status,
                   bytes_uploaded, total_bytes, upload_id, error_message,
                   created_at, updated_at
            FROM jobs ORDER BY id DESC
            """
        )
        return rows.map { rowToJob($0) }
    }

    /// Update a job's status.
    public func updateStatus(
        id: Int64,
        status: UploadStatus,
        errorMessage: String? = nil,
        uploadId: String? = nil
    ) throws {
        try db.run(
            """
            UPDATE jobs SET status = ?1, error_message = ?2, upload_id = ?3,
                           updated_at = datetime('now')
            WHERE id = ?4
            """,
            params: [status.rawValue, errorMessage, uploadId, id]
        )
    }

    /// Update bytes uploaded (progress tracking).
    public func updateProgress(id: Int64, bytesUploaded: UInt64) throws {
        try db.run(
            """
            UPDATE jobs SET bytes_uploaded = ?1, updated_at = datetime('now')
            WHERE id = ?2
            """,
            params: [bytesUploaded, id]
        )
    }

    /// Delete a job by ID. Returns true if a row was deleted.
    @discardableResult
    public func deleteJob(id: Int64) throws -> Bool {
        let changed = try db.run(
            "DELETE FROM jobs WHERE id = ?1",
            params: [id]
        )
        return changed > 0
    }

    /// Delete jobs matching one status. Returns the number of rows deleted.
    @discardableResult
    public func deleteJobs(status: UploadStatus) throws -> Int {
        try deleteJobs(statuses: [status])
    }

    /// Delete jobs matching any of the provided statuses.
    /// Use this for queue-level cleanup; active `.uploading` rows should not be
    /// included because the Rust runner may still be updating them.
    @discardableResult
    public func deleteJobs(statuses: [UploadStatus]) throws -> Int {
        guard !statuses.isEmpty else { return 0 }
        let placeholders = statuses.indices.map { "?\($0 + 1)" }.joined(separator: ", ")
        return try db.run(
            "DELETE FROM jobs WHERE status IN (\(placeholders))",
            params: statuses.map(\.rawValue)
        )
    }

    /// Reset all failed jobs so the runner can process them again.
    /// Returns the number of rows moved back to pending.
    @discardableResult
    public func retryFailedJobs() throws -> Int {
        try db.run(
            """
            UPDATE jobs
            SET status = ?1,
                retry_count = 0,
                bytes_uploaded = 0,
                upload_id = NULL,
                error_message = NULL,
                updated_at = datetime('now')
            WHERE status = ?2
            """,
            params: [UploadStatus.pending.rawValue, UploadStatus.failed.rawValue]
        )
    }

    // MARK: - Private

    private func createTable() throws {
        try db.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id             INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path      TEXT    NOT NULL,
                r2_key         TEXT    NOT NULL,
                bucket         TEXT    NOT NULL,
                account_name   TEXT    NOT NULL,
                status         TEXT    NOT NULL DEFAULT 'pending',
                bytes_uploaded INTEGER NOT NULL DEFAULT 0,
                total_bytes    INTEGER NOT NULL DEFAULT 0,
                upload_id      TEXT,
                error_message  TEXT,
                retry_count    INTEGER NOT NULL DEFAULT 0,
                created_at     TEXT    NOT NULL DEFAULT (datetime('now')),
                updated_at     TEXT    NOT NULL DEFAULT (datetime('now'))
            )
            """
        )
    }

    /// Map a raw SQLite row to an UploadJob model.
    private func rowToJob(_ row: SQLiteConnection.Row) -> UploadJob {
        UploadJob(
            id: row[0] as? Int64 ?? 0,
            filePath: row[1] as? String ?? "",
            r2Key: row[2] as? String ?? "",
            bucket: row[3] as? String ?? "",
            accountName: row[4] as? String ?? "",
            status: UploadStatus(rawValue: row[5] as? String ?? "pending") ?? .pending,
            bytesUploaded: UInt64(row[6] as? Int64 ?? 0),
            totalBytes: UInt64(row[7] as? Int64 ?? 0),
            uploadId: row[8] as? String,
            errorMessage: row[9] as? String,
            createdAt: row[10] as? String ?? "",
            updatedAt: row[11] as? String ?? ""
        )
    }

    // MARK: - Retry Support

    /// Reset retry_count to 0 for a job so the Rust engine will process it again.
    /// Called when user manually retries a failed upload (FR-039).
    public func resetRetryCount(id: Int64) throws {
        try db.run(
            """
            UPDATE jobs SET retry_count = 0, updated_at = datetime('now')
            WHERE id = ?1
            """,
            params: [id]
        )
    }
}
