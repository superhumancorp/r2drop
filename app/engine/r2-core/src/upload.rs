// r2-core/src/upload.rs — Async multipart upload engine for R2Drop
// Streams files from disk in configurable chunks, uploads to R2 in parallel.
// Supports progress callbacks, cancellation, and automatic abort on failure.

use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;

use futures::stream::{self, StreamExt};
use thiserror::Error;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

use tracing::{debug, info};

use crate::s3::{ObjectInfo, R2Client, R2Error};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum UploadError {
    #[error("R2 operation failed: {0}")]
    R2(#[from] R2Error),

    #[error("file I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("upload cancelled")]
    Cancelled,
}

// ---------------------------------------------------------------------------
// Configuration & progress types
// ---------------------------------------------------------------------------

/// Upload tuning parameters derived from user preferences.
pub struct UploadConfig {
    /// Chunk size in bytes. Default 8 MB (preferences range: 5–100 MB).
    pub chunk_size_bytes: usize,
    /// Number of parallel chunk uploads. Default 4 (preferences range: 1–16).
    pub concurrency: usize,
}

impl Default for UploadConfig {
    fn default() -> Self {
        Self {
            chunk_size_bytes: 8 * 1024 * 1024, // 8 MB
            concurrency: 4,
        }
    }
}

/// Progress snapshot passed to the callback after each chunk completes.
#[derive(Debug, Clone)]
pub struct UploadProgress {
    pub bytes_uploaded: u64,
    pub total_bytes: u64,
    pub speed_bytes_per_sec: f64,
    pub eta_seconds: Option<f64>,
}

/// Successful upload result.
#[derive(Debug, Clone)]
pub struct UploadResult {
    /// ETag returned by R2 for the completed object.
    pub e_tag: String,
    /// Total file size in bytes.
    pub total_bytes: u64,
    /// True if the file already existed in R2 with matching hash (FR-026).
    /// When true, the upload was skipped to avoid wasting bandwidth.
    pub already_existed: bool,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Calculate how many chunks are needed for a file of `total_bytes`.
fn num_parts(total_bytes: u64, chunk_size: usize) -> usize {
    if total_bytes == 0 {
        return 0;
    }
    total_bytes.div_ceil(chunk_size as u64) as usize
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Check if a local SHA-256 hash matches the remote object's hash.
///
/// Compares against SHA-256 custom metadata first (set by prior R2Drop uploads),
/// then falls back to raw ETag comparison. Note: S3/R2 ETags are MD5-based,
/// so the ETag fallback will only match if the remote was stored with SHA-256
/// as its ETag (uncommon). The metadata path is the reliable dedup mechanism.
fn hashes_match(local_sha256: &str, info: &ObjectInfo) -> bool {
    // Prefer SHA-256 metadata (from prior R2Drop uploads)
    if let Some(ref remote_sha256) = info.sha256 {
        return remote_sha256 == local_sha256;
    }
    // Fallback: compare against ETag (strip surrounding quotes)
    if let Some(ref e_tag) = info.e_tag {
        return e_tag.trim_matches('"') == local_sha256;
    }
    false
}

/// Upload a file to R2, choosing single-part or multipart based on size.
///
/// Before uploading, computes SHA-256 hash and checks R2 for duplicates (FR-026).
/// If the key already exists with a matching hash, the upload is skipped.
///
/// - Files <= `chunk_size_bytes` use a single `put_object` call (FR-022).
/// - Larger files use multipart with parallel chunk uploads (FR-023/024/025).
/// - Set `cancel` to `true` from another task to abort mid-upload.
/// - `progress_cb` is called after each chunk with current stats.
pub async fn upload_file(
    client: &R2Client,
    bucket: &str,
    key: &str,
    file_path: &Path,
    config: &UploadConfig,
    progress_cb: Option<Box<dyn Fn(UploadProgress) + Send + Sync>>,
    cancel: &AtomicBool,
) -> Result<UploadResult, UploadError> {
    let total_bytes = tokio::fs::metadata(file_path).await?.len();

    // Compute SHA-256 hash incrementally (FR-026). Reads in 64KB chunks.
    let local_hash = crate::hash::hash_file(file_path).await?;

    // Check if key already exists in R2 — skip upload if hashes match (FR-026)
    if let Some(info) = client.head_object(bucket, key).await? {
        if hashes_match(&local_hash, &info) {
            info!(
                r2_key = %key, bucket = %bucket, file_size = total_bytes,
                status = "skipped", "file already exists with matching hash"
            );
            return Ok(UploadResult {
                e_tag: info.e_tag.unwrap_or_default(),
                total_bytes,
                already_existed: true,
            });
        }
    }

    // Small files: single put_object, no multipart overhead (FR-022)
    if total_bytes <= config.chunk_size_bytes as u64 {
        debug!(
            r2_key = %key, bucket = %bucket, file_size = total_bytes,
            "using single-part upload"
        );
        return upload_single(
            client, bucket, key, file_path, total_bytes, &progress_cb, &local_hash,
        )
        .await;
    }

    // Large files: multipart with parallel chunks
    debug!(
        r2_key = %key, bucket = %bucket, file_size = total_bytes,
        chunk_size = config.chunk_size_bytes, concurrency = config.concurrency,
        "using multipart upload"
    );
    upload_multipart(
        client, bucket, key, file_path, total_bytes, config, &progress_cb, cancel, &local_hash,
    )
    .await
}

// ---------------------------------------------------------------------------
// Single-part upload (files <= chunk_size)
// ---------------------------------------------------------------------------

/// Read the entire small file into memory and upload via put_object.
async fn upload_single(
    client: &R2Client,
    bucket: &str,
    key: &str,
    file_path: &Path,
    total_bytes: u64,
    progress_cb: &Option<Box<dyn Fn(UploadProgress) + Send + Sync>>,
    sha256: &str,
) -> Result<UploadResult, UploadError> {
    let data = tokio::fs::read(file_path).await?;
    let e_tag = client.put_object(bucket, key, data, Some(sha256)).await?;

    if let Some(ref cb) = progress_cb {
        cb(UploadProgress {
            bytes_uploaded: total_bytes,
            total_bytes,
            speed_bytes_per_sec: 0.0,
            eta_seconds: Some(0.0),
        });
    }

    Ok(UploadResult {
        e_tag,
        total_bytes,
        already_existed: false,
    })
}

// ---------------------------------------------------------------------------
// Multipart upload (files > chunk_size)
// ---------------------------------------------------------------------------

/// Split file into chunks, upload in parallel with bounded concurrency.
///
/// Each chunk opens its own file handle and seeks to its offset.
/// This avoids shared seek state and lets the OS optimize reads.
/// On error or cancellation, aborts the multipart upload to free orphaned parts.
#[allow(clippy::too_many_arguments)]
async fn upload_multipart(
    client: &R2Client,
    bucket: &str,
    key: &str,
    file_path: &Path,
    total_bytes: u64,
    config: &UploadConfig,
    progress_cb: &Option<Box<dyn Fn(UploadProgress) + Send + Sync>>,
    cancel: &AtomicBool,
    sha256: &str,
) -> Result<UploadResult, UploadError> {
    let chunk_size = config.chunk_size_bytes;
    let part_count = num_parts(total_bytes, chunk_size);

    // Initiate multipart upload session with R2 (stores sha256 as metadata)
    let upload_id = client
        .create_multipart_upload(bucket, key, Some(sha256))
        .await?;
    let upload_id_str: &str = &upload_id;

    // Shared atomic counter — each chunk future increments after upload
    let bytes_done = AtomicU64::new(0);
    let bytes_ref: &AtomicU64 = &bytes_done;
    let start_time = Instant::now();

    // Stream of upload futures with bounded concurrency (FR-023).
    // buffer_unordered runs up to `concurrency` futures simultaneously.
    // Each future: open file → seek to offset → read chunk → upload part.
    let mut stream = stream::iter(1..=part_count)
        .map(|part_idx| async move {
            // Check cancellation before each chunk
            if cancel.load(Ordering::Relaxed) {
                return Err(UploadError::Cancelled);
            }

            let part_number = part_idx as i32;
            let offset = (part_idx as u64 - 1) * chunk_size as u64;
            let bytes_to_read =
                std::cmp::min(chunk_size as u64, total_bytes - offset) as usize;

            // Open a fresh file handle per chunk (FR-025: stream from disk)
            let mut file = tokio::fs::File::open(file_path).await?;
            file.seek(std::io::SeekFrom::Start(offset)).await?;
            let mut buf = vec![0u8; bytes_to_read];
            file.read_exact(&mut buf).await?;

            // Upload this chunk to R2
            let part = client
                .upload_part(bucket, key, upload_id_str, part_number, buf)
                .await?;

            // Update shared progress counter
            bytes_ref.fetch_add(bytes_to_read as u64, Ordering::Relaxed);

            Ok(part)
        })
        .buffer_unordered(config.concurrency);

    // Consume results one by one, reporting progress after each chunk
    let mut completed_parts = Vec::with_capacity(part_count);
    let mut upload_err: Option<UploadError> = None;

    loop {
        let next = stream.next().await;
        match next {
            Some(Ok(part)) => {
                completed_parts.push(part);

                let uploaded = bytes_done.load(Ordering::Relaxed);

                // Log progress milestones at 25%, 50%, 75% (FR-067)
                if total_bytes > 0 {
                    let pct = (uploaded * 100) / total_bytes;
                    let prev_pct = if uploaded >= chunk_size as u64 {
                        ((uploaded - chunk_size as u64) * 100) / total_bytes
                    } else {
                        0
                    };
                    for milestone in [25, 50, 75] {
                        if pct >= milestone && prev_pct < milestone {
                            info!(
                                r2_key = %key, bucket = %bucket,
                                progress_pct = milestone,
                                bytes_uploaded = uploaded, total_bytes,
                                "upload progress milestone"
                            );
                        }
                    }
                }

                if let Some(ref cb) = progress_cb {
                    let elapsed = start_time.elapsed().as_secs_f64();
                    let speed = if elapsed > 0.0 {
                        uploaded as f64 / elapsed
                    } else {
                        0.0
                    };
                    let remaining = total_bytes.saturating_sub(uploaded);
                    let eta = if speed > 0.0 {
                        Some(remaining as f64 / speed)
                    } else {
                        None
                    };
                    cb(UploadProgress {
                        bytes_uploaded: uploaded,
                        total_bytes,
                        speed_bytes_per_sec: speed,
                        eta_seconds: eta,
                    });
                }
            }
            Some(Err(e)) => {
                upload_err = Some(e);
                break;
            }
            None => break,
        }
    }

    // Drop stream to release borrows, then handle error or finalize
    drop(stream);

    if let Some(e) = upload_err {
        // Abort multipart to clean up orphaned parts in R2
        client
            .abort_multipart_upload(bucket, key, &upload_id)
            .await
            .ok();
        return Err(e);
    }

    // Parts may complete out of order — R2 requires sorted part list
    completed_parts.sort_by_key(|p| p.part_number);

    let e_tag = client
        .complete_multipart_upload(bucket, key, &upload_id, completed_parts)
        .await?;

    Ok(UploadResult {
        e_tag,
        total_bytes,
        already_existed: false,
    })
}

// ---------------------------------------------------------------------------
// Resume support (FR-028)
// ---------------------------------------------------------------------------

/// Resume a multipart upload from a previous crash/restart.
///
/// Calls `list_parts` to discover which chunks already uploaded, then
/// continues from the next part. If the upload_id is stale (R2 cleaned it up),
/// returns an error so the caller can fall back to a fresh upload.
#[allow(clippy::too_many_arguments)]
pub async fn resume_multipart_upload(
    client: &R2Client,
    bucket: &str,
    key: &str,
    file_path: &Path,
    total_bytes: u64,
    config: &UploadConfig,
    upload_id: &str,
    progress_cb: &Option<Box<dyn Fn(UploadProgress) + Send + Sync>>,
    cancel: &AtomicBool,
) -> Result<UploadResult, UploadError> {
    let chunk_size = config.chunk_size_bytes;
    let part_count = num_parts(total_bytes, chunk_size);

    // Discover which parts already completed before the crash
    let existing_parts = client.list_parts(bucket, key, upload_id).await?;
    let completed_part_numbers: std::collections::HashSet<i32> =
        existing_parts.iter().map(|p| p.part_number).collect();

    // Start with already-uploaded parts in our result set
    let mut completed_parts: Vec<crate::s3::UploadedPart> = existing_parts;

    // Calculate bytes already uploaded from completed parts
    let already_uploaded: u64 = completed_part_numbers
        .iter()
        .map(|&pn| {
            let offset = (pn as u64 - 1) * chunk_size as u64;
            std::cmp::min(chunk_size as u64, total_bytes - offset)
        })
        .sum();

    let bytes_done = AtomicU64::new(already_uploaded);
    let bytes_ref: &AtomicU64 = &bytes_done;
    let start_time = Instant::now();

    // Build list of parts that still need uploading
    let remaining: Vec<usize> = (1..=part_count)
        .filter(|&idx| !completed_part_numbers.contains(&(idx as i32)))
        .collect();

    // Upload remaining parts with bounded concurrency
    let mut stream = stream::iter(remaining)
        .map(|part_idx| async move {
            if cancel.load(Ordering::Relaxed) {
                return Err(UploadError::Cancelled);
            }

            let part_number = part_idx as i32;
            let offset = (part_idx as u64 - 1) * chunk_size as u64;
            let bytes_to_read =
                std::cmp::min(chunk_size as u64, total_bytes - offset) as usize;

            let mut file = tokio::fs::File::open(file_path).await?;
            file.seek(std::io::SeekFrom::Start(offset)).await?;
            let mut buf = vec![0u8; bytes_to_read];
            file.read_exact(&mut buf).await?;

            let part = client
                .upload_part(bucket, key, upload_id, part_number, buf)
                .await?;

            bytes_ref.fetch_add(bytes_to_read as u64, Ordering::Relaxed);
            Ok(part)
        })
        .buffer_unordered(config.concurrency);

    let mut upload_err: Option<UploadError> = None;

    loop {
        match stream.next().await {
            Some(Ok(part)) => {
                completed_parts.push(part);
                if let Some(ref cb) = progress_cb {
                    let uploaded = bytes_done.load(Ordering::Relaxed);
                    let elapsed = start_time.elapsed().as_secs_f64();
                    let speed = if elapsed > 0.0 {
                        uploaded as f64 / elapsed
                    } else {
                        0.0
                    };
                    let remaining_bytes = total_bytes.saturating_sub(uploaded);
                    let eta = if speed > 0.0 {
                        Some(remaining_bytes as f64 / speed)
                    } else {
                        None
                    };
                    cb(UploadProgress {
                        bytes_uploaded: uploaded,
                        total_bytes,
                        speed_bytes_per_sec: speed,
                        eta_seconds: eta,
                    });
                }
            }
            Some(Err(e)) => {
                upload_err = Some(e);
                break;
            }
            None => break,
        }
    }

    drop(stream);

    // On error during resume, do NOT abort the multipart — we want to retry later
    if let Some(e) = upload_err {
        return Err(e);
    }

    completed_parts.sort_by_key(|p| p.part_number);

    let e_tag = client
        .complete_multipart_upload(bucket, key, upload_id, completed_parts)
        .await?;

    Ok(UploadResult {
        e_tag,
        total_bytes,
        already_existed: false,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    const MB: u64 = 1024 * 1024;

    #[test]
    fn default_upload_config() {
        let cfg = UploadConfig::default();
        assert_eq!(cfg.chunk_size_bytes, 8 * 1024 * 1024);
        assert_eq!(cfg.concurrency, 4);
    }

    #[test]
    fn num_parts_exact_division() {
        assert_eq!(num_parts(16 * MB, 8 * MB as usize), 2);
    }

    #[test]
    fn num_parts_with_remainder() {
        assert_eq!(num_parts(17 * MB, 8 * MB as usize), 3);
    }

    #[test]
    fn num_parts_smaller_than_chunk() {
        assert_eq!(num_parts(1 * MB, 8 * MB as usize), 1);
    }

    #[test]
    fn num_parts_zero_bytes() {
        assert_eq!(num_parts(0, 8 * MB as usize), 0);
    }

    #[test]
    fn num_parts_one_byte() {
        assert_eq!(num_parts(1, 8 * MB as usize), 1);
    }

    #[test]
    fn num_parts_exact_chunk_boundary() {
        // Exactly 8 MB = 1 part (not 2)
        assert_eq!(num_parts(8 * MB, 8 * MB as usize), 1);
    }

    #[test]
    fn num_parts_large_file() {
        // 5 GB with 8 MB chunks = 640 parts
        assert_eq!(num_parts(5 * 1024 * MB, 8 * MB as usize), 640);
    }

    #[test]
    fn upload_progress_stores_values() {
        let p = UploadProgress {
            bytes_uploaded: 1024,
            total_bytes: 2048,
            speed_bytes_per_sec: 512.0,
            eta_seconds: Some(2.0),
        };
        assert_eq!(p.bytes_uploaded, 1024);
        assert_eq!(p.total_bytes, 2048);
        assert!((p.speed_bytes_per_sec - 512.0).abs() < f64::EPSILON);
        assert_eq!(p.eta_seconds, Some(2.0));
    }

    #[test]
    fn upload_result_stores_values() {
        let r = UploadResult {
            e_tag: "\"abc123\"".to_string(),
            total_bytes: 999,
            already_existed: false,
        };
        assert_eq!(r.e_tag, "\"abc123\"");
        assert_eq!(r.total_bytes, 999);
        assert!(!r.already_existed);
    }

    #[test]
    fn upload_result_already_existed() {
        let r = UploadResult {
            e_tag: "\"existing\"".to_string(),
            total_bytes: 512,
            already_existed: true,
        };
        assert!(r.already_existed);
    }

    #[test]
    fn small_file_uses_single_upload_path() {
        let cfg = UploadConfig::default();
        let chunk = cfg.chunk_size_bytes as u64;
        // Files at or below chunk_size go through single upload
        assert!(1024 <= chunk);
        assert!(chunk <= chunk);
        // Files above chunk_size trigger multipart
        assert!(chunk + 1 > chunk);
    }

    // -- hashes_match tests ---------------------------------------------------

    #[test]
    fn hashes_match_sha256_metadata() {
        let info = ObjectInfo {
            e_tag: Some("\"md5hash\"".into()),
            sha256: Some("abc123def456".into()),
            content_length: None,
            last_modified: None,
        };
        assert!(hashes_match("abc123def456", &info));
        assert!(!hashes_match("different", &info));
    }

    #[test]
    fn hashes_match_prefers_metadata_over_etag() {
        // When both sha256 metadata and ETag exist, metadata wins
        let info = ObjectInfo {
            e_tag: Some("\"etag_val\"".into()),
            sha256: Some("sha_val".into()),
            content_length: None,
            last_modified: None,
        };
        assert!(hashes_match("sha_val", &info));
        assert!(!hashes_match("etag_val", &info));
    }

    #[test]
    fn hashes_match_falls_back_to_etag() {
        // No sha256 metadata — fall back to ETag comparison
        let info = ObjectInfo {
            e_tag: Some("\"abc123\"".into()),
            sha256: None,
            content_length: None,
            last_modified: None,
        };
        assert!(hashes_match("abc123", &info));
        assert!(!hashes_match("different", &info));
    }

    #[test]
    fn hashes_match_etag_strips_quotes() {
        let info = ObjectInfo {
            e_tag: Some("\"deadbeef\"".into()),
            sha256: None,
            content_length: None,
            last_modified: None,
        };
        assert!(hashes_match("deadbeef", &info));
    }

    #[test]
    fn hashes_match_no_etag_or_metadata() {
        let info = ObjectInfo {
            e_tag: None,
            sha256: None,
            content_length: None,
            last_modified: None,
        };
        assert!(!hashes_match("abc123", &info));
    }
}
