// r2-core/src/s3.rs — S3-compatible R2 client for R2Drop
// Wraps both the Cloudflare REST API (token/account/bucket management)
// and aws-sdk-s3 (object upload operations) behind a single R2Client.

use aws_sdk_s3::config::{Credentials, Region};
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::types::CompletedMultipartUpload;
use aws_sdk_s3::types::CompletedPart;
use aws_sdk_s3::Client as S3Client;
use serde::Deserialize;
use thiserror::Error;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Cloudflare API base URL for account/token management.
const CF_API_BASE: &str = "https://api.cloudflare.com/client/v4";

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum R2Error {
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),

    #[error("S3 operation failed: {0}")]
    S3(String),

    #[error("Cloudflare API error ({code}): {message}")]
    CloudflareApi { code: i64, message: String },

    #[error("invalid API token")]
    InvalidToken,

    #[error("object not found: {bucket}/{key}")]
    NotFound { bucket: String, key: String },
}

// ---------------------------------------------------------------------------
// Cloudflare API response types (deserialized from JSON)
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct CfResponse<T> {
    success: bool,
    #[serde(default)]
    errors: Vec<CfError>,
    result: Option<T>,
}

#[derive(Debug, Deserialize)]
struct CfError {
    #[serde(default)]
    code: i64,
    #[serde(default)]
    message: String,
}

/// Cloudflare account info returned by `GET /accounts`.
#[derive(Debug, Clone, Deserialize)]
struct CfAccountInfo {
    id: String,
    name: String,
}

/// Cloudflare R2 bucket info returned by `GET /accounts/{id}/r2/buckets`.
#[derive(Debug, Deserialize)]
struct CfBucketsResult {
    buckets: Vec<CfBucketInfo>,
}

#[derive(Debug, Clone, Deserialize)]
struct CfBucketInfo {
    name: String,
}

// ---------------------------------------------------------------------------
// Public return types
// ---------------------------------------------------------------------------

/// A Cloudflare account with its ID and display name.
#[derive(Debug, Clone)]
pub struct AccountInfo {
    pub id: String,
    pub name: String,
}

/// Metadata returned by head_object for an existing R2 object.
#[derive(Debug, Clone)]
pub struct ObjectInfo {
    /// S3 ETag (typically MD5 for single-part uploads, quoted).
    pub e_tag: Option<String>,
    /// SHA-256 hash stored as custom metadata by R2Drop.
    /// Present only for objects uploaded by R2Drop with hash tracking.
    pub sha256: Option<String>,
    /// Object size in bytes (from Content-Length header).
    pub content_length: Option<u64>,
    /// Last modification timestamp as ISO 8601 string.
    pub last_modified: Option<String>,
}

/// Metadata returned by a completed multipart upload part.
#[derive(Debug, Clone)]
pub struct UploadedPart {
    pub part_number: i32,
    pub e_tag: String,
}

// ---------------------------------------------------------------------------
// R2Client
// ---------------------------------------------------------------------------

/// Unified client for Cloudflare REST API + S3-compatible R2 operations.
///
/// - Cloudflare REST: token validation, account listing, bucket management
/// - S3-compatible: head_object, put_object, multipart upload lifecycle
pub struct R2Client {
    http: reqwest::Client,
    token: String,
    s3: S3Client,
    account_id: String,
}

impl R2Client {
    /// Create a new R2Client for the given account.
    ///
    /// `account_id` is the Cloudflare account ID (hex string).
    /// `token` is the Cloudflare API token with R2 permissions.
    pub fn new(account_id: &str, token: &str) -> Self {
        let s3 = build_s3_client(account_id, token);
        Self {
            http: reqwest::Client::new(),
            token: token.to_string(),
            s3,
            account_id: account_id.to_string(),
        }
    }

    /// Returns the Cloudflare account ID this client is bound to.
    pub fn account_id(&self) -> &str {
        &self.account_id
    }

    // -- Cloudflare REST API -----------------------------------------------

    /// Validate an API token against Cloudflare. Returns `Ok(())` on success.
    /// This is a static method — no account_id needed.
    pub async fn validate_token(token: &str) -> Result<(), R2Error> {
        let url = format!("{CF_API_BASE}/user/tokens/verify");
        let resp: CfResponse<serde_json::Value> = reqwest::Client::new()
            .get(&url)
            .bearer_auth(token)
            .send()
            .await?
            .json()
            .await?;

        if resp.success {
            Ok(())
        } else {
            Err(R2Error::InvalidToken)
        }
    }

    /// List Cloudflare accounts accessible with the given token.
    /// Static method — doesn't require an existing R2Client.
    pub async fn list_accounts(token: &str) -> Result<Vec<AccountInfo>, R2Error> {
        let url = format!("{CF_API_BASE}/accounts");
        let resp: CfResponse<Vec<CfAccountInfo>> = reqwest::Client::new()
            .get(&url)
            .bearer_auth(token)
            .send()
            .await?
            .json()
            .await?;

        extract_cf_result(resp).map(|accounts| {
            accounts
                .into_iter()
                .map(|a| AccountInfo {
                    id: a.id,
                    name: a.name,
                })
                .collect()
        })
    }

    /// List R2 buckets for this client's account.
    pub async fn list_buckets(&self) -> Result<Vec<String>, R2Error> {
        let url = format!(
            "{CF_API_BASE}/accounts/{}/r2/buckets",
            self.account_id
        );
        let resp: CfResponse<CfBucketsResult> = self
            .http
            .get(&url)
            .bearer_auth(&self.token)
            .send()
            .await?
            .json()
            .await?;

        extract_cf_result(resp)
            .map(|r| r.buckets.into_iter().map(|b| b.name).collect())
    }

    /// Create a new R2 bucket in this client's account.
    pub async fn create_bucket(&self, bucket_name: &str) -> Result<(), R2Error> {
        let url = format!(
            "{CF_API_BASE}/accounts/{}/r2/buckets/{bucket_name}",
            self.account_id
        );
        let resp: CfResponse<serde_json::Value> = self
            .http
            .put(&url)
            .bearer_auth(&self.token)
            .send()
            .await?
            .json()
            .await?;

        if resp.success {
            Ok(())
        } else {
            extract_cf_result(resp).map(|_| ())
        }
    }

    // -- S3-compatible operations ------------------------------------------

    /// Check if an object exists. Returns metadata including size and last modified.
    pub async fn head_object(
        &self,
        bucket: &str,
        key: &str,
    ) -> Result<Option<ObjectInfo>, R2Error> {
        let result = self
            .s3
            .head_object()
            .bucket(bucket)
            .key(key)
            .send()
            .await;

        match result {
            Ok(output) => {
                let e_tag = output.e_tag().map(|s| s.to_string());
                let sha256 = output
                    .metadata()
                    .and_then(|m| m.get("sha256").cloned());
                let content_length = output.content_length().map(|l| l as u64);
                // Store as epoch seconds — Swift converts with Date(timeIntervalSince1970:)
                let last_modified = output
                    .last_modified()
                    .map(|dt| dt.secs().to_string());
                Ok(Some(ObjectInfo {
                    e_tag,
                    sha256,
                    content_length,
                    last_modified,
                }))
            }
            Err(err) => {
                // R2 returns 404 when object doesn't exist
                if is_not_found(&err) {
                    Ok(None)
                } else {
                    Err(R2Error::S3(err.to_string()))
                }
            }
        }
    }

    /// Upload a small file as a single object (no multipart).
    /// If `sha256` is provided, stores it as custom metadata for dedup detection.
    pub async fn put_object(
        &self,
        bucket: &str,
        key: &str,
        body: Vec<u8>,
        sha256: Option<&str>,
    ) -> Result<String, R2Error> {
        let mut builder = self
            .s3
            .put_object()
            .bucket(bucket)
            .key(key)
            .body(ByteStream::from(body));

        if let Some(hash) = sha256 {
            builder = builder.metadata("sha256", hash);
        }

        let output = builder
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        Ok(output.e_tag().unwrap_or_default().to_string())
    }

    /// Initiate a multipart upload. Returns the upload ID.
    /// If `sha256` is provided, stores it as custom metadata for dedup detection.
    pub async fn create_multipart_upload(
        &self,
        bucket: &str,
        key: &str,
        sha256: Option<&str>,
    ) -> Result<String, R2Error> {
        let mut builder = self
            .s3
            .create_multipart_upload()
            .bucket(bucket)
            .key(key);

        if let Some(hash) = sha256 {
            builder = builder.metadata("sha256", hash);
        }

        let output = builder
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        output
            .upload_id()
            .map(|s| s.to_string())
            .ok_or_else(|| R2Error::S3("no upload_id in response".into()))
    }

    /// Upload a single part of a multipart upload.
    pub async fn upload_part(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
        part_number: i32,
        body: Vec<u8>,
    ) -> Result<UploadedPart, R2Error> {
        let output = self
            .s3
            .upload_part()
            .bucket(bucket)
            .key(key)
            .upload_id(upload_id)
            .part_number(part_number)
            .body(ByteStream::from(body))
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        let e_tag = output
            .e_tag()
            .unwrap_or_default()
            .to_string();

        Ok(UploadedPart {
            part_number,
            e_tag,
        })
    }

    /// Finalize a multipart upload with the list of completed parts.
    pub async fn complete_multipart_upload(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
        parts: Vec<UploadedPart>,
    ) -> Result<String, R2Error> {
        // Build the CompletedMultipartUpload from our UploadedPart list
        let completed_parts: Vec<CompletedPart> = parts
            .into_iter()
            .map(|p| {
                CompletedPart::builder()
                    .part_number(p.part_number)
                    .e_tag(p.e_tag)
                    .build()
            })
            .collect();

        let completed = CompletedMultipartUpload::builder()
            .set_parts(Some(completed_parts))
            .build();

        let output = self
            .s3
            .complete_multipart_upload()
            .bucket(bucket)
            .key(key)
            .upload_id(upload_id)
            .multipart_upload(completed)
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        Ok(output.e_tag().unwrap_or_default().to_string())
    }

    /// List parts already uploaded for a multipart upload (FR-028 resume).
    /// Returns the parts sorted by part_number. Used to discover which
    /// chunks completed before a crash so we can resume from the next one.
    pub async fn list_parts(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
    ) -> Result<Vec<UploadedPart>, R2Error> {
        let output = self
            .s3
            .list_parts()
            .bucket(bucket)
            .key(key)
            .upload_id(upload_id)
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        let parts = output
            .parts()
            .iter()
            .map(|p| UploadedPart {
                part_number: p.part_number().unwrap_or(0),
                e_tag: p.e_tag().unwrap_or_default().to_string(),
            })
            .collect();

        Ok(parts)
    }

    /// Cancel an incomplete multipart upload to free orphaned parts.
    pub async fn abort_multipart_upload(
        &self,
        bucket: &str,
        key: &str,
        upload_id: &str,
    ) -> Result<(), R2Error> {
        self.s3
            .abort_multipart_upload()
            .bucket(bucket)
            .key(key)
            .upload_id(upload_id)
            .send()
            .await
            .map_err(|e| R2Error::S3(e.to_string()))?;

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build an aws-sdk-s3 client configured for Cloudflare R2.
///
/// R2's S3-compatible endpoint is:
///   https://<account_id>.r2.cloudflarestorage.com
fn build_s3_client(account_id: &str, token: &str) -> S3Client {
    let endpoint = format!("https://{account_id}.r2.cloudflarestorage.com");

    // R2 uses the API token as both access_key_id and secret_access_key.
    // The token is the only credential — there's no separate secret key.
    let creds = Credentials::new(token, token, None, None, "r2drop");

    let config = aws_sdk_s3::Config::builder()
        .endpoint_url(endpoint)
        .credentials_provider(creds)
        .region(Region::new("auto"))
        .force_path_style(true)
        .behavior_version_latest()
        .build();

    S3Client::from_conf(config)
}

/// Extract the result payload from a Cloudflare API response, or return an error.
fn extract_cf_result<T>(resp: CfResponse<T>) -> Result<T, R2Error> {
    if resp.success {
        resp.result
            .ok_or_else(|| R2Error::S3("empty result in successful response".into()))
    } else {
        let err = resp.errors.into_iter().next().unwrap_or(CfError {
            code: 0,
            message: "unknown Cloudflare API error".into(),
        });
        Err(R2Error::CloudflareApi {
            code: err.code,
            message: err.message,
        })
    }
}

/// Check if an S3 SDK error is a 404 Not Found.
fn is_not_found<E: std::fmt::Display>(err: &aws_sdk_s3::error::SdkError<E>) -> bool {
    // The SDK wraps service errors. Check the raw HTTP status if available.
    match err {
        aws_sdk_s3::error::SdkError::ServiceError(service_err) => {
            service_err.raw().status().as_u16() == 404
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_s3_client_creates_valid_client() {
        // Smoke test: building the client should not panic.
        let _client = build_s3_client("abc123", "fake-token");
    }

    #[test]
    fn extract_cf_result_success() {
        let resp = CfResponse {
            success: true,
            errors: vec![],
            result: Some(42),
        };
        assert_eq!(extract_cf_result(resp).unwrap(), 42);
    }

    #[test]
    fn extract_cf_result_error() {
        let resp: CfResponse<i32> = CfResponse {
            success: false,
            errors: vec![CfError {
                code: 1000,
                message: "bad request".into(),
            }],
            result: None,
        };
        let err = extract_cf_result(resp).unwrap_err();
        match err {
            R2Error::CloudflareApi { code, message } => {
                assert_eq!(code, 1000);
                assert_eq!(message, "bad request");
            }
            _ => panic!("expected CloudflareApi error"),
        }
    }

    #[test]
    fn extract_cf_result_missing_result() {
        let resp: CfResponse<i32> = CfResponse {
            success: true,
            errors: vec![],
            result: None,
        };
        // success=true but result=None should be an error
        assert!(extract_cf_result(resp).is_err());
    }

    #[test]
    fn uploaded_part_stores_values() {
        let part = UploadedPart {
            part_number: 3,
            e_tag: "\"abc123\"".into(),
        };
        assert_eq!(part.part_number, 3);
        assert_eq!(part.e_tag, "\"abc123\"");
    }

    #[test]
    fn r2_client_new_does_not_panic() {
        // Verifies the constructor wires up S3 client without network calls.
        let client = R2Client::new("test-account", "test-token");
        assert_eq!(client.account_id(), "test-account");
    }

    #[test]
    fn error_display_messages() {
        let err = R2Error::InvalidToken;
        assert_eq!(format!("{err}"), "invalid API token");

        let err = R2Error::CloudflareApi {
            code: 9999,
            message: "forbidden".into(),
        };
        assert!(format!("{err}").contains("9999"));
        assert!(format!("{err}").contains("forbidden"));

        let err = R2Error::NotFound {
            bucket: "b".into(),
            key: "k".into(),
        };
        assert!(format!("{err}").contains("b/k"));
    }
}
