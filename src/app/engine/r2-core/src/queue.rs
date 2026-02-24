// r2-core/src/queue.rs — Persistent upload queue backed by SQLite
// Stores upload jobs in ~/.r2drop/queue.db with WAL mode for concurrent
// read/write access from both the main app and the Finder extension.

use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;
use thiserror::Error;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum QueueError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),

    #[error("invalid status transition: {from} -> {to}")]
    InvalidTransition { from: String, to: String },

    #[error("job not found: {0}")]
    NotFound(i64),
}

// ---------------------------------------------------------------------------
// Job status enum
// ---------------------------------------------------------------------------

/// Possible states for an upload job.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobStatus {
    Pending,
    Uploading,
    Paused,
    Completed,
    Failed,
}

impl JobStatus {
    /// Convert from the string stored in SQLite.
    pub fn parse_status(s: &str) -> Option<Self> {
        match s {
            "pending" => Some(Self::Pending),
            "uploading" => Some(Self::Uploading),
            "paused" => Some(Self::Paused),
            "completed" => Some(Self::Completed),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }

    /// String representation stored in SQLite.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Uploading => "uploading",
            Self::Paused => "paused",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }

    /// Check whether transitioning from `self` to `target` is allowed.
    /// Valid transitions:
    ///   pending   → uploading
    ///   uploading → completed | failed | paused
    ///   paused    → uploading
    ///   failed    → pending  (retry)
    pub fn can_transition_to(&self, target: Self) -> bool {
        matches!(
            (self, target),
            (Self::Pending, Self::Uploading)
                | (Self::Uploading, Self::Completed)
                | (Self::Uploading, Self::Failed)
                | (Self::Uploading, Self::Paused)
                | (Self::Paused, Self::Uploading)
                | (Self::Failed, Self::Pending)
        )
    }
}

impl std::fmt::Display for JobStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

// ---------------------------------------------------------------------------
// QueueJob — one row in the queue table
// ---------------------------------------------------------------------------

/// A single upload job stored in the queue database.
#[derive(Debug, Clone)]
pub struct QueueJob {
    pub id: i64,
    pub file_path: String,
    pub r2_key: String,
    pub bucket: String,
    pub account_name: String,
    pub status: JobStatus,
    pub bytes_uploaded: u64,
    pub total_bytes: u64,
    /// Multipart upload ID (from R2). Present only during active multipart uploads.
    pub upload_id: Option<String>,
    pub error_message: Option<String>,
    /// Number of times this job has been retried after failure (FR-029).
    pub retry_count: u32,
    pub created_at: String,
    pub updated_at: String,
}

// ---------------------------------------------------------------------------
// QueueDb — wrapper around a SQLite connection
// ---------------------------------------------------------------------------

/// Persistent upload queue backed by SQLite.
/// Uses WAL journal mode so the Finder extension can insert jobs while
/// the main app reads and processes them concurrently.
pub struct QueueDb {
    conn: Connection,
}

impl QueueDb {
    /// Open (or create) the queue database at the given path.
    /// Enables WAL mode and creates the jobs table if it doesn't exist.
    pub fn open(path: &Path) -> Result<Self, QueueError> {
        let conn = Connection::open(path)?;
        conn.pragma_update(None, "journal_mode", "wal")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS jobs (
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
            );",
        )?;
        Ok(Self { conn })
    }

    /// Open the default queue database at `~/.r2drop/queue.db`.
    pub fn open_default() -> Result<Self, QueueError> {
        let dir = crate::config::config_dir()
            .map_err(|e| QueueError::Db(rusqlite::Error::InvalidParameterName(e.to_string())))?;
        Self::open(&dir.join("queue.db"))
    }

    /// Insert a new upload job. Returns the auto-generated row ID.
    pub fn insert_job(
        &self,
        file_path: &str,
        r2_key: &str,
        bucket: &str,
        account_name: &str,
        total_bytes: u64,
    ) -> Result<i64, QueueError> {
        self.conn.execute(
            "INSERT INTO jobs (file_path, r2_key, bucket, account_name, total_bytes)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![file_path, r2_key, bucket, account_name, total_bytes as i64],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Fetch a single job by ID. Returns `None` if not found.
    pub fn get_job(&self, id: i64) -> Result<Option<QueueJob>, QueueError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, file_path, r2_key, bucket, account_name, status,
                    bytes_uploaded, total_bytes, upload_id, error_message,
                    retry_count, created_at, updated_at
             FROM jobs WHERE id = ?1",
        )?;
        stmt.query_row(params![id], row_to_job).optional().map_err(Into::into)
    }

    /// Update a job's status, enforcing valid transitions.
    /// Optionally sets error_message (for failed) or upload_id (for uploading).
    pub fn update_status(
        &self,
        id: i64,
        new_status: JobStatus,
        error_message: Option<&str>,
        upload_id: Option<&str>,
    ) -> Result<(), QueueError> {
        let current = self.get_job(id)?.ok_or(QueueError::NotFound(id))?;
        if !current.status.can_transition_to(new_status) {
            return Err(QueueError::InvalidTransition {
                from: current.status.to_string(),
                to: new_status.to_string(),
            });
        }
        self.conn.execute(
            "UPDATE jobs SET status = ?1, error_message = ?2, upload_id = ?3,
                            updated_at = datetime('now')
             WHERE id = ?4",
            params![new_status.as_str(), error_message, upload_id, id],
        )?;
        Ok(())
    }

    /// Update bytes_uploaded for an in-progress job (progress tracking).
    pub fn update_progress(&self, id: i64, bytes_uploaded: u64) -> Result<(), QueueError> {
        let changed = self.conn.execute(
            "UPDATE jobs SET bytes_uploaded = ?1, updated_at = datetime('now')
             WHERE id = ?2",
            params![bytes_uploaded as i64, id],
        )?;
        if changed == 0 {
            return Err(QueueError::NotFound(id));
        }
        Ok(())
    }

    /// List all jobs with a given status.
    pub fn list_jobs_by_status(&self, status: JobStatus) -> Result<Vec<QueueJob>, QueueError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, file_path, r2_key, bucket, account_name, status,
                    bytes_uploaded, total_bytes, upload_id, error_message,
                    retry_count, created_at, updated_at
             FROM jobs WHERE status = ?1 ORDER BY id ASC",
        )?;
        let rows = stmt.query_map(params![status.as_str()], row_to_job)?;
        rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
    }

    /// Increment retry count for a job. Returns the new count.
    pub fn increment_retry_count(&self, id: i64) -> Result<u32, QueueError> {
        self.conn.execute(
            "UPDATE jobs SET retry_count = retry_count + 1, updated_at = datetime('now')
             WHERE id = ?1",
            params![id],
        )?;
        let job = self.get_job(id)?.ok_or(QueueError::NotFound(id))?;
        Ok(job.retry_count)
    }

    /// Reset a failed job's bytes_uploaded so it can be retried fresh.
    /// Does NOT reset retry_count (that's tracked separately).
    pub fn reset_progress(&self, id: i64) -> Result<(), QueueError> {
        let changed = self.conn.execute(
            "UPDATE jobs SET bytes_uploaded = 0, upload_id = NULL,
                            error_message = NULL, updated_at = datetime('now')
             WHERE id = ?1",
            params![id],
        )?;
        if changed == 0 {
            return Err(QueueError::NotFound(id));
        }
        Ok(())
    }

    /// Delete a job by ID. Returns true if a row was actually deleted.
    pub fn delete_job(&self, id: i64) -> Result<bool, QueueError> {
        let changed = self.conn.execute("DELETE FROM jobs WHERE id = ?1", params![id])?;
        Ok(changed > 0)
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Map a SQLite row to a QueueJob struct.
fn row_to_job(row: &rusqlite::Row) -> rusqlite::Result<QueueJob> {
    let status_str: String = row.get(5)?;
    let status = JobStatus::parse_status(&status_str).unwrap_or(JobStatus::Failed);
    let bytes_uploaded: i64 = row.get(6)?;
    let total_bytes: i64 = row.get(7)?;
    let retry_count: i64 = row.get(10)?;

    Ok(QueueJob {
        id: row.get(0)?,
        file_path: row.get(1)?,
        r2_key: row.get(2)?,
        bucket: row.get(3)?,
        account_name: row.get(4)?,
        status,
        bytes_uploaded: bytes_uploaded as u64,
        total_bytes: total_bytes as u64,
        upload_id: row.get(8)?,
        error_message: row.get(9)?,
        retry_count: retry_count as u32,
        created_at: row.get(11)?,
        updated_at: row.get(12)?,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Create an in-memory queue database for testing.
    fn test_db() -> QueueDb {
        QueueDb::open(Path::new(":memory:")).unwrap()
    }

    #[test]
    fn insert_and_get_job() {
        let db = test_db();
        let id = db
            .insert_job("/tmp/test.txt", "test.txt", "my-bucket", "acct1", 1024)
            .unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.file_path, "/tmp/test.txt");
        assert_eq!(job.r2_key, "test.txt");
        assert_eq!(job.bucket, "my-bucket");
        assert_eq!(job.account_name, "acct1");
        assert_eq!(job.status, JobStatus::Pending);
        assert_eq!(job.bytes_uploaded, 0);
        assert_eq!(job.total_bytes, 1024);
        assert!(job.upload_id.is_none());
        assert!(job.error_message.is_none());
        assert_eq!(job.retry_count, 0);
    }

    #[test]
    fn get_nonexistent_returns_none() {
        let db = test_db();
        assert!(db.get_job(999).unwrap().is_none());
    }

    #[test]
    fn status_transition_pending_to_uploading() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        db.update_status(id, JobStatus::Uploading, None, Some("upload-123"))
            .unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.status, JobStatus::Uploading);
        assert_eq!(job.upload_id, Some("upload-123".into()));
    }

    #[test]
    fn status_transition_uploading_to_completed() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        db.update_status(id, JobStatus::Uploading, None, None).unwrap();
        db.update_status(id, JobStatus::Completed, None, None).unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.status, JobStatus::Completed);
    }

    #[test]
    fn status_transition_uploading_to_failed() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        db.update_status(id, JobStatus::Uploading, None, None).unwrap();
        db.update_status(id, JobStatus::Failed, Some("network timeout"), None)
            .unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.status, JobStatus::Failed);
        assert_eq!(job.error_message, Some("network timeout".into()));
    }

    #[test]
    fn status_transition_uploading_to_paused_to_uploading() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        db.update_status(id, JobStatus::Uploading, None, None).unwrap();
        db.update_status(id, JobStatus::Paused, None, None).unwrap();
        db.update_status(id, JobStatus::Uploading, None, None).unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.status, JobStatus::Uploading);
    }

    #[test]
    fn invalid_transition_rejected() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        // pending → completed is not a valid transition
        let err = db
            .update_status(id, JobStatus::Completed, None, None)
            .unwrap_err();
        assert!(matches!(err, QueueError::InvalidTransition { .. }));
    }

    #[test]
    fn update_progress() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 1000).unwrap();
        db.update_progress(id, 500).unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.bytes_uploaded, 500);
    }

    #[test]
    fn update_progress_nonexistent_fails() {
        let db = test_db();
        let err = db.update_progress(999, 100).unwrap_err();
        assert!(matches!(err, QueueError::NotFound(999)));
    }

    #[test]
    fn list_jobs_by_status() {
        let db = test_db();
        db.insert_job("/a", "a", "b", "acct", 100).unwrap();
        db.insert_job("/b", "b", "b", "acct", 200).unwrap();
        let id3 = db.insert_job("/c", "c", "b", "acct", 300).unwrap();
        // Move one to uploading
        db.update_status(id3, JobStatus::Uploading, None, None).unwrap();

        let pending = db.list_jobs_by_status(JobStatus::Pending).unwrap();
        assert_eq!(pending.len(), 2);

        let uploading = db.list_jobs_by_status(JobStatus::Uploading).unwrap();
        assert_eq!(uploading.len(), 1);
        assert_eq!(uploading[0].file_path, "/c");
    }

    #[test]
    fn delete_job() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        assert!(db.delete_job(id).unwrap());
        assert!(db.get_job(id).unwrap().is_none());
        // Deleting again returns false
        assert!(!db.delete_job(id).unwrap());
    }

    #[test]
    fn failed_to_pending_transition_allowed() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        db.update_status(id, JobStatus::Uploading, None, None).unwrap();
        db.update_status(id, JobStatus::Failed, Some("timeout"), None).unwrap();
        // Retry: failed → pending
        db.update_status(id, JobStatus::Pending, None, None).unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.status, JobStatus::Pending);
    }

    #[test]
    fn increment_retry_count() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 100).unwrap();
        assert_eq!(db.increment_retry_count(id).unwrap(), 1);
        assert_eq!(db.increment_retry_count(id).unwrap(), 2);
        assert_eq!(db.increment_retry_count(id).unwrap(), 3);
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.retry_count, 3);
    }

    #[test]
    fn reset_progress_clears_upload_state() {
        let db = test_db();
        let id = db.insert_job("/f", "k", "b", "a", 1000).unwrap();
        db.update_status(id, JobStatus::Uploading, None, Some("upload-abc")).unwrap();
        db.update_progress(id, 500).unwrap();
        db.reset_progress(id).unwrap();
        let job = db.get_job(id).unwrap().unwrap();
        assert_eq!(job.bytes_uploaded, 0);
        assert!(job.upload_id.is_none());
        assert!(job.error_message.is_none());
    }

    #[test]
    fn wal_mode_enabled() {
        // WAL doesn't work with :memory: databases, so use a temp file.
        let tmp = tempfile::tempdir().unwrap();
        let db = QueueDb::open(&tmp.path().join("test.db")).unwrap();
        let mode: String = db
            .conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(mode, "wal");
    }

    #[test]
    fn job_status_display() {
        assert_eq!(JobStatus::Pending.as_str(), "pending");
        assert_eq!(JobStatus::Uploading.as_str(), "uploading");
        assert_eq!(JobStatus::Paused.as_str(), "paused");
        assert_eq!(JobStatus::Completed.as_str(), "completed");
        assert_eq!(JobStatus::Failed.as_str(), "failed");
    }

    #[test]
    fn job_status_from_str() {
        assert_eq!(JobStatus::parse_status("pending"), Some(JobStatus::Pending));
        assert_eq!(JobStatus::parse_status("uploading"), Some(JobStatus::Uploading));
        assert_eq!(JobStatus::parse_status("invalid"), None);
    }
}
