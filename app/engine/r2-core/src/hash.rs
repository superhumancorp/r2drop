// r2-core/src/hash.rs — Incremental SHA-256 file hashing for R2Drop
// Streams files in 64KB chunks to avoid buffering entire files in memory.
// Used for idempotent upload detection (FR-026): compare local hash against
// remote SHA-256 metadata to skip re-uploading identical files.

use sha2::{Digest, Sha256};
use std::path::Path;
use tokio::io::AsyncReadExt;

/// Size of each read buffer for incremental hashing (64 KB).
const HASH_BUFFER_SIZE: usize = 64 * 1024;

/// Compute SHA-256 hash of a file by streaming in chunks.
///
/// Returns lowercase hex-encoded hash string (64 characters).
/// Never loads the entire file into memory — reads in 64 KB increments.
/// Works correctly for files of any size, including > 4 GB.
pub async fn hash_file(path: &Path) -> Result<String, std::io::Error> {
    let mut file = tokio::fs::File::open(path).await?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; HASH_BUFFER_SIZE];

    loop {
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }

    let result = hasher.finalize();
    Ok(to_hex(&result))
}

/// Convert a byte slice to lowercase hex string.
fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn hash_empty_file() {
        let file = NamedTempFile::new().unwrap();
        let hash = hash_file(file.path()).await.unwrap();
        // SHA-256 of empty input is a well-known constant
        assert_eq!(
            hash,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[tokio::test]
    async fn hash_known_content() {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(b"hello world").unwrap();
        file.flush().unwrap();
        let hash = hash_file(file.path()).await.unwrap();
        // SHA-256("hello world") — verified with `echo -n "hello world" | shasum -a 256`
        assert_eq!(
            hash,
            "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        );
    }

    #[tokio::test]
    async fn hash_large_file_multiple_buffers() {
        // File larger than HASH_BUFFER_SIZE (64KB) to test multi-chunk reading
        let mut file = NamedTempFile::new().unwrap();
        let data = vec![0xABu8; 100 * 1024]; // 100 KB
        file.write_all(&data).unwrap();
        file.flush().unwrap();

        let hash = hash_file(file.path()).await.unwrap();
        assert_eq!(hash.len(), 64);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[tokio::test]
    async fn hash_consistency() {
        let mut file = NamedTempFile::new().unwrap();
        file.write_all(b"deterministic content").unwrap();
        file.flush().unwrap();

        let hash1 = hash_file(file.path()).await.unwrap();
        let hash2 = hash_file(file.path()).await.unwrap();
        assert_eq!(hash1, hash2, "same file should produce same hash");
    }

    #[tokio::test]
    async fn hash_different_content_differs() {
        let mut f1 = NamedTempFile::new().unwrap();
        f1.write_all(b"content A").unwrap();
        f1.flush().unwrap();

        let mut f2 = NamedTempFile::new().unwrap();
        f2.write_all(b"content B").unwrap();
        f2.flush().unwrap();

        let h1 = hash_file(f1.path()).await.unwrap();
        let h2 = hash_file(f2.path()).await.unwrap();
        assert_ne!(h1, h2, "different content should produce different hashes");
    }

    #[test]
    fn to_hex_produces_correct_output() {
        assert_eq!(to_hex(&[0x00, 0xff, 0xab]), "00ffab");
        assert_eq!(to_hex(&[]), "");
    }

    #[tokio::test]
    async fn hash_nonexistent_file_returns_error() {
        let result = hash_file(Path::new("/nonexistent/file.txt")).await;
        assert!(result.is_err());
    }
}
