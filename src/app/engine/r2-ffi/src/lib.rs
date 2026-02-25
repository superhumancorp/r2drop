// r2-ffi/src/lib.rs — C FFI bridge for the Swift macOS app
// Exposes r2-core functionality through extern "C" functions.
// cbindgen generates the r2_ffi.h header from this file.
//
// Memory ownership rules:
//   - Rust-allocated strings (*mut c_char) must be freed with r2_free_string()
//   - C-owned strings passed into FFI functions are borrowed (not freed by Rust)
//   - Status codes: 0 = success, -1 = error (call r2_get_last_error for details)

mod helpers;

use std::os::raw::c_char;

use helpers::{from_c_str, runtime, set_last_error, take_last_error, to_c_string};
use r2_core::{config, history, logging, queue, runner, s3, upload};

// ---------------------------------------------------------------------------
// Progress callback type
// ---------------------------------------------------------------------------

/// C function pointer for upload progress updates.
/// Parameters: bytes_uploaded, total_bytes, speed_bytes_per_sec, eta_seconds
/// Swift passes this when starting uploads to get real-time progress.
/// In C: `typedef void (*R2ProgressCallback)(uint64_t, uint64_t, double, double);`
/// Pass NULL in Swift/C to disable progress reporting.
pub type R2ProgressCallback =
    extern "C" fn(bytes_uploaded: u64, total_bytes: u64, speed_bps: f64, eta_secs: f64);

// ---------------------------------------------------------------------------
// Error handling
// ---------------------------------------------------------------------------

/// Returns the last error message from an FFI call.
/// Caller must free the returned string with `r2_free_string`.
/// Returns null if no error occurred since the last call.
#[no_mangle]
pub extern "C" fn r2_get_last_error() -> *mut c_char {
    match take_last_error() {
        Some(msg) => to_c_string(msg),
        None => std::ptr::null_mut(),
    }
}

/// Frees a string previously allocated by the Rust FFI layer.
///
/// # Safety
/// `ptr` must be a pointer returned by an r2_* function, or null.
#[no_mangle]
pub unsafe extern "C" fn r2_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(unsafe { std::ffi::CString::from_raw(ptr) });
    }
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

/// Initialize the audit logging system with rolling file output (FR-067).
/// Call once at app startup. Subsequent calls are no-ops.
/// `max_log_files` controls how many rotated log files to retain.
/// `max_log_file_size_mb` controls the max size (MB) before startup cleanup.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn r2_init_logging(max_log_files: u16, max_log_file_size_mb: u16) -> i32 {
    match logging::init_logging(max_log_files as usize, max_log_file_size_mb as usize, false) {
        Ok(()) => {
            tracing::info!("r2drop audit logging initialized");
            0
        }
        Err(e) => {
            set_last_error(format!("failed to init logging: {e}"));
            -1
        }
    }
}



// ---------------------------------------------------------------------------
// Network availability (FR-031)
// ---------------------------------------------------------------------------

/// Inform the Rust engine of a network availability change.
/// Called by the Swift NWPathMonitor wrapper when connectivity changes.
/// `available`: true = network is up, false = network is down.
/// Returns 0 on success.
#[no_mangle]
pub extern "C" fn r2_set_network_available(available: bool) -> i32 {
    helpers::set_network_available(available);
    0
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/// Returns the config directory path (~/.r2drop or R2DROP_HOME).
/// Caller must free the returned string with `r2_free_string`.
#[no_mangle]
pub extern "C" fn r2_config_dir() -> *mut c_char {
    match config::config_dir() {
        Ok(path) => to_c_string(path.to_string_lossy().to_string()),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Authentication & account discovery (async → block_on)
// ---------------------------------------------------------------------------

/// Validate an API token against the Cloudflare API.
/// On success, returns a C string containing the token ID (UUID) from the
/// Cloudflare verify response. Caller must free with `r2_free_string`.
/// On failure, returns null (check r2_get_last_error).
///
/// # Safety
/// `token` must be a valid NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn r2_validate_token(token: *const c_char) -> *mut c_char {
    let Some(token) = (unsafe { from_c_str(token) }) else {
        set_last_error("null or invalid token pointer".into());
        return std::ptr::null_mut();
    };
    match runtime().block_on(s3::R2Client::validate_token(token)) {
        Ok(token_id) => to_c_string(token_id),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// List Cloudflare accounts accessible with the given token.
/// Returns a JSON array: [{"id":"...","name":"..."},...]
/// Caller must free the returned string with `r2_free_string`.
///
/// # Safety
/// `token` must be a valid NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn r2_list_accounts(token: *const c_char) -> *mut c_char {
    let Some(token) = (unsafe { from_c_str(token) }) else {
        set_last_error("null or invalid token pointer".into());
        return std::ptr::null_mut();
    };
    match runtime().block_on(s3::R2Client::list_accounts(token)) {
        Ok(accounts) => {
            let json: Vec<serde_json::Value> = accounts
                .iter()
                .map(|a| serde_json::json!({"id": a.id, "name": a.name}))
                .collect();
            to_c_string(serde_json::to_string(&json).unwrap_or_default())
        }
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// List R2 buckets for the given account.
/// Returns a JSON array of bucket name strings: ["bucket-a","bucket-b",...]
/// Caller must free the returned string with `r2_free_string`.
///
/// # Safety
/// `account_id` and `token` must be valid NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn r2_list_buckets(
    account_id: *const c_char,
    token: *const c_char,
) -> *mut c_char {
    let (Some(account_id), Some(token)) =
        (unsafe { from_c_str(account_id) }, unsafe { from_c_str(token) })
    else {
        set_last_error("null or invalid account_id/token pointer".into());
        return std::ptr::null_mut();
    };
    let client = s3::R2Client::new(account_id, token, token, token);
    match runtime().block_on(client.list_buckets()) {
        Ok(buckets) => to_c_string(serde_json::to_string(&buckets).unwrap_or_default()),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

/// Create a new R2 bucket in the given account.
/// Returns 0 on success, -1 on error.
///
/// # Safety
/// All pointer params must be valid NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn r2_create_bucket(
    account_id: *const c_char,
    bucket_name: *const c_char,
    token: *const c_char,
) -> i32 {
    let (Some(account_id), Some(bucket_name), Some(token)) = (
        unsafe { from_c_str(account_id) },
        unsafe { from_c_str(bucket_name) },
        unsafe { from_c_str(token) },
    ) else {
        set_last_error("null or invalid pointer argument".into());
        return -1;
    };
    let client = s3::R2Client::new(account_id, token, token, token);
    match runtime().block_on(client.create_bucket(bucket_name)) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e.to_string());
            -1
        }
    }
}

// ---------------------------------------------------------------------------
// Object operations (async → block_on)
// ---------------------------------------------------------------------------

/// Check if an object exists in R2 and return its metadata as JSON.
/// Returns JSON: {"exists":true,"content_length":1234,"last_modified":"1706..."} or
/// {"exists":false} if the object does not exist.
/// Returns null on error (check r2_get_last_error).
/// Caller must free the returned string with `r2_free_string`.
///
/// # Safety
/// All pointer params must be valid NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn r2_head_object(
    account_id: *const c_char,
    token: *const c_char,
    bucket: *const c_char,
    key: *const c_char,
) -> *mut c_char {
    let (Some(account_id), Some(token), Some(bucket), Some(key)) = (
        unsafe { from_c_str(account_id) },
        unsafe { from_c_str(token) },
        unsafe { from_c_str(bucket) },
        unsafe { from_c_str(key) },
    ) else {
        set_last_error("null or invalid pointer argument".into());
        return std::ptr::null_mut();
    };
    let client = s3::R2Client::new(account_id, token, token, token);
    match runtime().block_on(client.head_object(bucket, key)) {
        Ok(Some(info)) => {
            let json = serde_json::json!({
                "exists": true,
                "content_length": info.content_length,
                "last_modified": info.last_modified,
                "e_tag": info.e_tag,
            });
            to_c_string(serde_json::to_string(&json).unwrap_or_default())
        }
        Ok(None) => to_c_string(r#"{"exists":false}"#.to_string()),
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Queue operations (synchronous SQLite)
// ---------------------------------------------------------------------------

/// Queue a file for upload. Returns the job ID (>0) on success, -1 on error.
/// The file is not uploaded immediately — the runner processes the queue.
///
/// # Safety
/// All pointer params must be valid NUL-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn r2_queue_upload(
    file_path: *const c_char,
    r2_key: *const c_char,
    bucket: *const c_char,
    account_name: *const c_char,
) -> i64 {
    let (Some(file_path), Some(r2_key), Some(bucket), Some(account_name)) = (
        unsafe { from_c_str(file_path) },
        unsafe { from_c_str(r2_key) },
        unsafe { from_c_str(bucket) },
        unsafe { from_c_str(account_name) },
    ) else {
        set_last_error("null or invalid pointer argument".into());
        return -1;
    };

    // Get file size for the queue entry
    let total_bytes = match std::fs::metadata(file_path) {
        Ok(m) => m.len(),
        Err(e) => {
            set_last_error(format!("cannot read file: {e}"));
            return -1;
        }
    };

    let db = match queue::QueueDb::open_default() {
        Ok(db) => db,
        Err(e) => {
            set_last_error(e.to_string());
            return -1;
        }
    };
    match db.insert_job(file_path, r2_key, bucket, account_name, total_bytes) {
        Ok(id) => id,
        Err(e) => {
            set_last_error(e.to_string());
            -1
        }
    }
}

/// Process pending upload jobs for a specific account.
/// Recovers any interrupted uploads, then processes all pending jobs.
/// Returns the number of jobs completed (>= 0) on success, -1 on error.
///
/// # Safety
/// All pointer params must be valid NUL-terminated C strings.
/// `access_key_id` is the token UUID from validate_token.
/// `secret_access_key` is the SHA-256 hash of the API token.
#[no_mangle]
pub unsafe extern "C" fn r2_process_queue(
    account_id: *const c_char,
    access_key_id: *const c_char,
    secret_access_key: *const c_char,
    account_name: *const c_char,
) -> i32 {
    let (Some(account_id), Some(access_key_id), Some(secret_access_key), Some(account_name)) = (
        unsafe { from_c_str(account_id) },
        unsafe { from_c_str(access_key_id) },
        unsafe { from_c_str(secret_access_key) },
        unsafe { from_c_str(account_name) },
    ) else {
        set_last_error("null or invalid pointer argument".into());
        return -1;
    };

    let db = match queue::QueueDb::open_default() {
        Ok(db) => db,
        Err(e) => {
            set_last_error(e.to_string());
            return -1;
        }
    };

    // Recover any interrupted uploads from a previous crash
    if let Err(e) = runner::recover_interrupted(&db) {
        tracing::warn!("failed to recover interrupted uploads: {e}");
    }

    // REST API token is not needed for process_queue (only S3 ops).
    // Pass empty string for the bearer token since uploads use S3 creds only.
    let client = s3::R2Client::new(account_id, "", access_key_id, secret_access_key);
    // Load user preferences from config.toml (FR-006: respect chunk_size_mb, concurrent_uploads)
    let user_config = config::Config::load().unwrap_or_default();
    let config = upload::UploadConfig {
        chunk_size_bytes: (user_config.preferences.chunk_size_mb as usize) * 1024 * 1024,
        concurrency: user_config.preferences.concurrent_uploads as usize,
    };
    let shutdown = std::sync::atomic::AtomicBool::new(false);

    match runtime().block_on(runner::process_pending(
        &client,
        &db,
        &config,
        helpers::network_available(),
        &shutdown,
        account_name,
    )) {
        Ok(completed) => completed as i32,
        Err(e) => {
            set_last_error(e.to_string());
            -1
        }
    }
}

/// Pause an upload job. Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn r2_pause_upload(job_id: i64) -> i32 {
    with_queue_db(|db| db.update_status(job_id, queue::JobStatus::Paused, None, None))
}

/// Resume a paused upload job (transitions to Pending for re-processing).
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn r2_resume_upload(job_id: i64) -> i32 {
    with_queue_db(|db| db.update_status(job_id, queue::JobStatus::Pending, None, None))
}

/// Cancel an upload job by deleting it from the queue.
/// Returns 0 on success (including if already deleted), -1 on error.
#[no_mangle]
pub extern "C" fn r2_cancel_upload(job_id: i64) -> i32 {
    with_queue_db(|db| db.delete_job(job_id).map(|_| ()))
}

/// Reset retry count and re-queue a failed job for manual retry.
/// Transitions status from Failed → Pending and resets retry_count to 0.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn r2_retry_job(job_id: i64) -> i32 {
    with_queue_db(|db| {
        db.reset_retry_count(job_id)?;
        db.update_status(job_id, queue::JobStatus::Pending, None, None)?;
        Ok(())
    })
}

/// Get the current queue status as a JSON array of job objects.
/// Each object: id, file_path, r2_key, bucket, account_name, status,
/// bytes_uploaded, total_bytes, error_message.
/// Caller must free the returned string with `r2_free_string`.
#[no_mangle]
pub extern "C" fn r2_get_queue_status() -> *mut c_char {
    let db = match queue::QueueDb::open_default() {
        Ok(db) => db,
        Err(e) => {
            set_last_error(e.to_string());
            return std::ptr::null_mut();
        }
    };

    // Collect all non-completed jobs across all active statuses
    let mut jobs = Vec::new();
    for status in [
        queue::JobStatus::Pending,
        queue::JobStatus::Uploading,
        queue::JobStatus::Paused,
        queue::JobStatus::Failed,
    ] {
        match db.list_jobs_by_status(status) {
            Ok(list) => jobs.extend(list),
            Err(e) => {
                set_last_error(e.to_string());
                return std::ptr::null_mut();
            }
        }
    }

    let json: Vec<serde_json::Value> = jobs.iter().map(job_to_json).collect();
    to_c_string(serde_json::to_string(&json).unwrap_or_default())
}

/// Get upload history as a JSON array.
/// Each object: id, file_name, file_size, r2_key, bucket, account_name,
/// url, uploaded_at.
/// Caller must free the returned string with `r2_free_string`.
#[no_mangle]
pub extern "C" fn r2_get_history() -> *mut c_char {
    let db = match history::HistoryDb::open_default() {
        Ok(db) => db,
        Err(e) => {
            set_last_error(e.to_string());
            return std::ptr::null_mut();
        }
    };
    match db.list_entries() {
        Ok(entries) => {
            let json: Vec<serde_json::Value> = entries.iter().map(entry_to_json).collect();
            to_c_string(serde_json::to_string(&json).unwrap_or_default())
        }
        Err(e) => {
            set_last_error(e.to_string());
            std::ptr::null_mut()
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Open the default queue DB, run a closure, and return 0/-1 status code.
fn with_queue_db<F>(f: F) -> i32
where
    F: FnOnce(&queue::QueueDb) -> Result<(), queue::QueueError>,
{
    let db = match queue::QueueDb::open_default() {
        Ok(db) => db,
        Err(e) => {
            set_last_error(e.to_string());
            return -1;
        }
    };
    match f(&db) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(e.to_string());
            -1
        }
    }
}

/// Serialize a QueueJob to JSON.
fn job_to_json(job: &queue::QueueJob) -> serde_json::Value {
    serde_json::json!({
        "id": job.id,
        "file_path": job.file_path,
        "r2_key": job.r2_key,
        "bucket": job.bucket,
        "account_name": job.account_name,
        "status": job.status.as_str(),
        "bytes_uploaded": job.bytes_uploaded,
        "total_bytes": job.total_bytes,
        "error_message": job.error_message,
    })
}

/// Serialize a HistoryEntry to JSON.
fn entry_to_json(e: &history::HistoryEntry) -> serde_json::Value {
    serde_json::json!({
        "id": e.id,
        "file_name": e.file_name,
        "file_size": e.file_size,
        "r2_key": e.r2_key,
        "bucket": e.bucket,
        "account_name": e.account_name,
        "url": e.url,
        "uploaded_at": e.uploaded_at,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_dir_returns_non_null() {
        let ptr = r2_config_dir();
        assert!(!ptr.is_null());
        unsafe { r2_free_string(ptr) };
    }

    #[test]
    fn free_string_null_is_safe() {
        unsafe { r2_free_string(std::ptr::null_mut()) };
    }

    #[test]
    fn get_last_error_returns_null_initially() {
        let _ = take_last_error(); // clear any prior error
        let ptr = r2_get_last_error();
        assert!(ptr.is_null());
    }

    #[test]
    fn set_and_get_last_error() {
        set_last_error("test error".into());
        let ptr = r2_get_last_error();
        assert!(!ptr.is_null());
        let msg = unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().unwrap();
        assert_eq!(msg, "test error");
        unsafe { r2_free_string(ptr) };
        // Second call returns null (error consumed)
        let ptr2 = r2_get_last_error();
        assert!(ptr2.is_null());
    }

    #[test]
    fn validate_token_null_returns_null() {
        let ptr = unsafe { r2_validate_token(std::ptr::null()) };
        assert!(ptr.is_null());
        assert!(take_last_error().is_some());
    }

    #[test]
    fn list_accounts_null_returns_null() {
        assert!(unsafe { r2_list_accounts(std::ptr::null()) }.is_null());
        assert!(take_last_error().is_some());
    }

    #[test]
    fn list_buckets_null_returns_null() {
        let ptr = unsafe { r2_list_buckets(std::ptr::null(), std::ptr::null()) };
        assert!(ptr.is_null());
    }

    #[test]
    fn create_bucket_null_returns_error() {
        let r = unsafe { r2_create_bucket(std::ptr::null(), std::ptr::null(), std::ptr::null()) };
        assert_eq!(r, -1);
    }

    #[test]
    fn queue_upload_null_returns_error() {
        let r = unsafe {
            r2_queue_upload(std::ptr::null(), std::ptr::null(), std::ptr::null(), std::ptr::null())
        };
        assert_eq!(r, -1);
    }

    #[test]
    fn head_object_null_returns_null() {
        let ptr = unsafe {
            r2_head_object(
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
            )
        };
        assert!(ptr.is_null());
        assert!(take_last_error().is_some());
    }

    #[test]
    fn progress_callback_type_defined() {
        // Verify the callback type compiles correctly as a C function pointer
        extern "C" fn dummy(_: u64, _: u64, _: f64, _: f64) {}
        let cb: R2ProgressCallback = dummy;
        // Call it to prove it's a real function pointer
        cb(0, 100, 50.0, 2.0);
    }

    #[test]
    fn job_to_json_produces_valid_json() {
        let job = queue::QueueJob {
            id: 42,
            file_path: "/tmp/test.txt".into(),
            r2_key: "test.txt".into(),
            bucket: "my-bucket".into(),
            account_name: "acct1".into(),
            status: queue::JobStatus::Pending,
            bytes_uploaded: 0,
            total_bytes: 1024,
            upload_id: None,
            error_message: None,
            retry_count: 0,
            created_at: "2026-01-01".into(),
            updated_at: "2026-01-01".into(),
        };
        let val = job_to_json(&job);
        assert_eq!(val["id"], 42);
        assert_eq!(val["status"], "pending");
        assert_eq!(val["total_bytes"], 1024);
    }

    #[test]
    fn set_network_available_returns_zero() {
        assert_eq!(r2_set_network_available(true), 0);
        assert_eq!(r2_set_network_available(false), 0);
        assert!(!helpers::network_available().load(std::sync::atomic::Ordering::Relaxed));
        assert_eq!(r2_set_network_available(true), 0);
        assert!(helpers::network_available().load(std::sync::atomic::Ordering::Relaxed));
    }
}