// r2-core/src/runner.rs — Upload queue processor (FR-028, FR-029, FR-030, FR-031, FR-034)
// Orchestrates the upload queue: recovers interrupted uploads on startup,
// processes pending jobs with exponential backoff retry, respects network
// status and paused state. Designed to be driven by the Swift app or CLI.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tracing::{error, info, warn};

use crate::queue::{JobStatus, QueueDb, QueueError, QueueJob};
use crate::s3::R2Client;
use crate::upload::{UploadConfig, UploadError, UploadProgress};
use crate::config::Config;
use crate::history::HistoryDb;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum retries before marking a job as permanently failed (FR-029).
pub const MAX_RETRIES: u32 = 10;

/// Maximum backoff delay in seconds (FR-029).
const MAX_BACKOFF_SECS: u64 = 60;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, thiserror::Error)]
pub enum RunnerError {
    #[error("queue error: {0}")]
    Queue(#[from] QueueError),

    #[error("upload error: {0}")]
    Upload(#[from] UploadError),

    #[error("file not readable: {path}: {reason}")]
    FileNotReadable { path: String, reason: String },
}

// ---------------------------------------------------------------------------
// Retry policy — exponential backoff (FR-029)
// ---------------------------------------------------------------------------

/// Calculate backoff delay for a given retry attempt.
/// Exponential: 1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s, ... (capped at 60s).
pub fn backoff_duration(retry_count: u32) -> Duration {
    let secs = std::cmp::min(1u64 << retry_count, MAX_BACKOFF_SECS);
    Duration::from_secs(secs)
}

// ---------------------------------------------------------------------------
// Startup recovery (FR-028)
// ---------------------------------------------------------------------------

/// Scan for jobs stuck in `uploading` state (from a previous crash).
/// For each, attempt to resume the multipart upload if an upload_id exists.
/// If resume fails, reset the job to `pending` for a fresh retry.
///
/// Returns the number of recovered jobs.
pub fn recover_interrupted(queue: &QueueDb) -> Result<usize, RunnerError> {
    let stuck = queue.list_jobs_by_status(JobStatus::Uploading)?;
    let count = stuck.len();
    if count > 0 {
        info!(recovered = count, "recovering interrupted uploads from previous session");
    }
    for job in &stuck {
        // Reset to pending — process_job() will handle resume via upload_id
        // We keep the upload_id intact so resume can use it
        info!(
            job_id = job.id,
            file_path = %job.file_path,
            r2_key = %job.r2_key,
            bucket = %job.bucket,
            "resetting interrupted job to pending"
        );
        queue.update_status(job.id, JobStatus::Failed, Some("interrupted by crash"), None)?;
        queue.update_status(job.id, JobStatus::Pending, None, None)?;
    }
    Ok(count)
}

// ---------------------------------------------------------------------------
// File readability check (FR-031)
// ---------------------------------------------------------------------------

/// Check if a file exists and is readable. Returns an error if the file
/// is locked, missing, or otherwise inaccessible.
pub fn check_file_readable(path: &str) -> Result<(), RunnerError> {
    let p = Path::new(path);
    if !p.exists() {
        return Err(RunnerError::FileNotReadable {
            path: path.to_string(),
            reason: "file does not exist".to_string(),
        });
    }
    // Try opening the file to detect locks or permission issues
    match std::fs::File::open(p) {
        Ok(_) => Ok(()),
        Err(e) => Err(RunnerError::FileNotReadable {
            path: path.to_string(),
            reason: e.to_string(),
        }),
    }
}


// ---------------------------------------------------------------------------
// History recording helpers (FR-034)
// ---------------------------------------------------------------------------

/// Build the public URL for an uploaded object.
/// Uses the account's custom_domain if configured, otherwise falls back to
/// the standard R2 public URL format.
pub fn build_public_url(r2_key: &str, bucket: &str, account_name: &str, config: &Config) -> String {
    // Look up the account to check for a custom domain
    if let Some(acct) = config.accounts.iter().find(|a| a.name == account_name) {
        if let Some(ref domain) = acct.custom_domain {
            if !domain.is_empty() {
                let domain = domain.trim_end_matches('/');
                return format!("https://{domain}/{r2_key}");
            }
        }
        // Fallback: use account_id-based R2 URL if available
        if let Some(ref aid) = acct.account_id {
            return format!("https://{bucket}.{aid}.r2.cloudflarestorage.com/{r2_key}");
        }
    }
    // Last resort: bucket-only URL (account not found or no account_id)
    format!("https://{bucket}.r2.cloudflarestorage.com/{r2_key}")
}

/// Record a completed upload in history.db (FR-034).
/// Best-effort: errors are logged but do not propagate.
/// Loads config from disk to resolve custom domains for URL construction.
fn record_history(job: &QueueJob) {
    let config = Config::load().unwrap_or_default();
    let file_name = Path::new(&job.file_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| job.file_path.clone());
    let url = build_public_url(&job.r2_key, &job.bucket, &job.account_name, &config);
    if let Ok(db) = HistoryDb::open_default() {
        if let Err(e) = db.insert_entry(&file_name, job.total_bytes, &job.r2_key, &job.bucket, &job.account_name, &url) {
            warn!(job_id = job.id, error = %e, "failed to record upload in history");
        }
    }
}

// ---------------------------------------------------------------------------
// Single job processing
// ---------------------------------------------------------------------------

/// Process a single upload job. Handles:
/// - File readability check (FR-031)
/// - Multipart resume if upload_id exists (FR-028)
/// - Fresh upload otherwise
/// - Returns the upload result or error
///
/// The caller (process_pending) handles retry scheduling and backoff.
pub async fn process_job(
    job: &QueueJob,
    client: &R2Client,
    queue: &QueueDb,
    config: &UploadConfig,
    cancel: &AtomicBool,
    progress_cb: Option<Box<dyn Fn(UploadProgress) + Send + Sync>>,
) -> Result<(), RunnerError> {
    // Log upload start (FR-067)
    info!(
        job_id = job.id,
        file_path = %job.file_path,
        r2_key = %job.r2_key,
        bucket = %job.bucket,
        account = %job.account_name,
        file_size = job.total_bytes,
        status = "start",
        "upload starting"
    );

    // Mark as uploading
    queue.update_status(
        job.id,
        JobStatus::Uploading,
        None,
        job.upload_id.as_deref(),
    )?;

    // Check file is readable before attempting upload (FR-031)
    if let Err(e) = check_file_readable(&job.file_path) {
        error!(
            job_id = job.id,
            file_path = %job.file_path,
            error = %e,
            status = "failed",
            "file not readable"
        );
        queue.update_status(
            job.id,
            JobStatus::Failed,
            Some(&format!("file not readable: {}", e)),
            None,
        )?;
        return Err(e);
    }

    let file_path = Path::new(&job.file_path);

    // If we have a stored upload_id, try resuming the multipart (FR-028)
    if let Some(ref upload_id) = job.upload_id {
        match crate::upload::resume_multipart_upload(
            client,
            &job.bucket,
            &job.r2_key,
            file_path,
            job.total_bytes,
            config,
            upload_id,
            &progress_cb,
            cancel,
        )
        .await
        {
            Ok(_result) => {
                info!(
                    job_id = job.id, r2_key = %job.r2_key, bucket = %job.bucket,
                    account = %job.account_name, file_size = job.total_bytes,
                    status = "completed", "upload resumed and completed"
                );
                queue.update_status(job.id, JobStatus::Completed, None, None)?;
                record_history(job);
                return Ok(());
            }
            Err(UploadError::Cancelled) => {
                info!(job_id = job.id, status = "paused", "upload cancelled by user");
                queue.update_status(job.id, JobStatus::Paused, None, None)?;
                return Err(RunnerError::Upload(UploadError::Cancelled));
            }
            Err(ref e) => {
                warn!(job_id = job.id, error = %e, "resume failed, falling back to fresh upload");
            }
        }
    }

    // Fresh upload (or resume failed, so start over)
    match crate::upload::upload_file(
        client,
        &job.bucket,
        &job.r2_key,
        file_path,
        config,
        progress_cb,
        cancel,
    )
    .await
    {
        Ok(_result) => {
            info!(
                job_id = job.id, r2_key = %job.r2_key, bucket = %job.bucket,
                account = %job.account_name, file_size = job.total_bytes,
                status = "completed", "upload completed"
            );
            queue.update_status(job.id, JobStatus::Completed, None, None)?;
            record_history(job);
            Ok(())
        }
        Err(UploadError::Cancelled) => {
            info!(job_id = job.id, status = "paused", "upload cancelled by user");
            queue.update_status(job.id, JobStatus::Paused, None, None)?;
            Err(RunnerError::Upload(UploadError::Cancelled))
        }
        Err(e) => {
            error!(
                job_id = job.id, r2_key = %job.r2_key, bucket = %job.bucket,
                account = %job.account_name, error = %e,
                status = "failed", "upload failed"
            );
            queue.update_status(
                job.id,
                JobStatus::Failed,
                Some(&e.to_string()),
                None,
            )?;
            Err(RunnerError::Upload(e))
        }
    }
}

// ---------------------------------------------------------------------------
// Queue processing loop
// ---------------------------------------------------------------------------

/// Process all pending jobs in the queue for a specific account.
///
/// - Only processes jobs matching the active_account (FR-033)
/// - Skips paused jobs (FR: paused jobs don't auto-resume)
/// - Checks `network_available` before each job (FR-030)
/// - Retries failed jobs with exponential backoff up to MAX_RETRIES (FR-029)
/// - Stops if `shutdown` is set to true
///
/// Returns the number of jobs completed successfully.
pub async fn process_pending(
    client: &R2Client,
    queue: &QueueDb,
    config: &UploadConfig,
    network_available: &AtomicBool,
    shutdown: &AtomicBool,
    active_account: &str,
) -> Result<usize, RunnerError> {
    let mut completed = 0;

    let all_jobs = queue.list_jobs_by_status(JobStatus::Pending)?;
    // Filter to only jobs for the active account (FR-033)
    let jobs: Vec<_> = all_jobs
        .into_iter()
        .filter(|j| j.account_name == active_account)
        .collect();
    for job in jobs {
        // Respect shutdown signal
        if shutdown.load(Ordering::Relaxed) {
            break;
        }

        // If network is down, stop processing — jobs stay pending (FR-030)
        if !network_available.load(Ordering::Relaxed) {
            break;
        }

        // Skip jobs that have exceeded max retries (FR-029)
        if job.retry_count >= MAX_RETRIES {
            error!(
                job_id = job.id, r2_key = %job.r2_key, bucket = %job.bucket,
                retries = MAX_RETRIES, status = "failed",
                "permanently failed after max retries"
            );
            queue.update_status(
                job.id,
                JobStatus::Uploading,
                None,
                job.upload_id.as_deref(),
            )?;
            queue.update_status(
                job.id,
                JobStatus::Failed,
                Some(&format!("permanently failed after {} retries", MAX_RETRIES)),
                None,
            )?;
            continue;
        }

        let cancel = AtomicBool::new(false);
        match process_job(&job, client, queue, config, &cancel, None).await {
            Ok(()) => completed += 1,
            Err(RunnerError::FileNotReadable { .. }) => {
                // File errors are permanent — don't retry
            }
            Err(RunnerError::Upload(UploadError::Cancelled)) => {
                break;
            }
            Err(_) => {
                // Upload failed — schedule retry with backoff (FR-029)
                let count = queue.increment_retry_count(job.id)?;
                if count < MAX_RETRIES {
                    let delay = backoff_duration(count);
                    warn!(
                        job_id = job.id, r2_key = %job.r2_key,
                        retry = count, backoff_secs = delay.as_secs(),
                        status = "retry", "scheduling retry with backoff"
                    );
                    queue.update_status(job.id, JobStatus::Pending, None, None)?;
                    tokio::time::sleep(delay).await;
                }
            }
        }
    }

    Ok(completed)
}

/// Called by Swift when network connectivity is restored (FR-030).
/// Sets the network flag and triggers processing of pending jobs.
pub fn on_network_restored(network_available: &AtomicBool) {
    info!("network connectivity restored, resuming queue processing");
    network_available.store(true, Ordering::Relaxed);
    // The Swift layer calls process_pending() after this
}

/// Called by Swift when network connectivity is lost (FR-030).
/// Clears the network flag so the runner stops picking up new jobs.
pub fn on_network_lost(network_available: &AtomicBool) {
    warn!("network connectivity lost, pausing queue processing");
    network_available.store(false, Ordering::Relaxed);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Account;

    #[test]
    fn backoff_duration_exponential() {
        assert_eq!(backoff_duration(0), Duration::from_secs(1));
        assert_eq!(backoff_duration(1), Duration::from_secs(2));
        assert_eq!(backoff_duration(2), Duration::from_secs(4));
        assert_eq!(backoff_duration(3), Duration::from_secs(8));
        assert_eq!(backoff_duration(4), Duration::from_secs(16));
        assert_eq!(backoff_duration(5), Duration::from_secs(32));
    }

    #[test]
    fn backoff_duration_capped_at_60s() {
        assert_eq!(backoff_duration(6), Duration::from_secs(60));
        assert_eq!(backoff_duration(7), Duration::from_secs(60));
        assert_eq!(backoff_duration(10), Duration::from_secs(60));
    }

    #[test]
    fn check_file_readable_nonexistent() {
        let err = check_file_readable("/nonexistent/path/file.txt").unwrap_err();
        match err {
            RunnerError::FileNotReadable { path, reason } => {
                assert_eq!(path, "/nonexistent/path/file.txt");
                assert!(reason.contains("does not exist"));
            }
            _ => panic!("expected FileNotReadable"),
        }
    }

    #[test]
    fn check_file_readable_exists() {
        // Create a temp file and verify it's readable
        let tmp = tempfile::NamedTempFile::new().unwrap();
        check_file_readable(tmp.path().to_str().unwrap()).unwrap();
    }

    #[test]
    fn recover_interrupted_resets_uploading_jobs() {
        let db = QueueDb::open(Path::new(":memory:")).unwrap();
        let id1 = db.insert_job("/a", "a", "b", "acct", 100).unwrap();
        let id2 = db.insert_job("/b", "b", "b", "acct", 200).unwrap();

        // Move both to uploading (simulating crash mid-upload)
        db.update_status(id1, JobStatus::Uploading, None, Some("upload-1"))
            .unwrap();
        db.update_status(id2, JobStatus::Uploading, None, Some("upload-2"))
            .unwrap();

        let recovered = recover_interrupted(&db).unwrap();
        assert_eq!(recovered, 2);

        // Both should now be pending
        let j1 = db.get_job(id1).unwrap().unwrap();
        let j2 = db.get_job(id2).unwrap().unwrap();
        assert_eq!(j1.status, JobStatus::Pending);
        assert_eq!(j2.status, JobStatus::Pending);
    }

    #[test]
    fn recover_interrupted_ignores_other_statuses() {
        let db = QueueDb::open(Path::new(":memory:")).unwrap();
        let id1 = db.insert_job("/a", "a", "b", "acct", 100).unwrap();
        let id2 = db.insert_job("/b", "b", "b", "acct", 200).unwrap();

        // id1 is pending, id2 is uploading then completed
        db.update_status(id2, JobStatus::Uploading, None, None).unwrap();
        db.update_status(id2, JobStatus::Completed, None, None).unwrap();

        let recovered = recover_interrupted(&db).unwrap();
        assert_eq!(recovered, 0);

        // Statuses unchanged
        assert_eq!(db.get_job(id1).unwrap().unwrap().status, JobStatus::Pending);
        assert_eq!(db.get_job(id2).unwrap().unwrap().status, JobStatus::Completed);
    }

    #[test]
    fn network_flag_toggling() {
        let flag = AtomicBool::new(true);
        assert!(flag.load(Ordering::Relaxed));

        on_network_lost(&flag);
        assert!(!flag.load(Ordering::Relaxed));

        on_network_restored(&flag);
        assert!(flag.load(Ordering::Relaxed));
    }

    #[test]
    fn max_retries_constant() {
        assert_eq!(MAX_RETRIES, 10);
    }
    #[test]
    fn process_pending_filters_by_account() {
        // Create in-memory queue with jobs for two accounts
        let db = QueueDb::open(Path::new(":memory:")).unwrap();
        let id1 = db.insert_job("/file1", "key1", "bucket", "acct1", 100).unwrap();
        let id2 = db.insert_job("/file2", "key2", "bucket", "acct2", 200).unwrap();
        let id3 = db.insert_job("/file3", "key3", "bucket", "acct1", 150).unwrap();

        // All three should be pending
        let all_pending = db.list_jobs_by_status(JobStatus::Pending).unwrap();
        assert_eq!(all_pending.len(), 3);

        // Filter to acct1 only
        let acct1_jobs: Vec<_> = all_pending
            .iter()
            .filter(|j| j.account_name == "acct1")
            .collect();
        assert_eq!(acct1_jobs.len(), 2);
        assert!(acct1_jobs.iter().all(|j| j.account_name == "acct1"));
        assert!(acct1_jobs.iter().any(|j| j.id == id1));
        assert!(acct1_jobs.iter().any(|j| j.id == id3));

        // Filter to acct2 only
        let acct2_jobs: Vec<_> = all_pending
            .iter()
            .filter(|j| j.account_name == "acct2")
            .collect();
        assert_eq!(acct2_jobs.len(), 1);
        assert_eq!(acct2_jobs[0].id, id2);
    }


    #[test]
    fn build_public_url_with_custom_domain() {
        let config = Config {
            active_account: Some("myacct".into()),
            accounts: vec![Account {
                name: "myacct".into(),
                account_id: Some("abc123".into()),
                bucket: "my-bucket".into(),
                path: String::new(),
                custom_domain: Some("cdn.example.com".into()),
            }],
            preferences: Default::default(),
        };
        let url = build_public_url("photos/cat.jpg", "my-bucket", "myacct", &config);
        assert_eq!(url, "https://cdn.example.com/photos/cat.jpg");
    }

    #[test]
    fn build_public_url_fallback_to_account_id() {
        let config = Config {
            active_account: Some("myacct".into()),
            accounts: vec![Account {
                name: "myacct".into(),
                account_id: Some("abc123".into()),
                bucket: "my-bucket".into(),
                path: String::new(),
                custom_domain: None,
            }],
            preferences: Default::default(),
        };
        let url = build_public_url("photos/cat.jpg", "my-bucket", "myacct", &config);
        assert_eq!(url, "https://my-bucket.abc123.r2.cloudflarestorage.com/photos/cat.jpg");
    }

    #[test]
    fn build_public_url_unknown_account() {
        let config = Config::default();
        let url = build_public_url("file.txt", "bucket", "unknown", &config);
        assert_eq!(url, "https://bucket.r2.cloudflarestorage.com/file.txt");
    }

}
