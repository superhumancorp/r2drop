// r2-cli/src/upload.rs — Upload command for R2Drop CLI
// Handles file/folder uploads with optional ZIP compression and progress display.
// In standalone mode (no daemon), uploads directly via r2-core.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use r2_core::config::Config;
use r2_core::credentials;
use r2_core::history::HistoryDb;
use r2_core::s3::R2Client;
use r2_core::upload::{self, UploadConfig, UploadProgress};

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------

/// Arguments for the `r2drop upload` command.
#[derive(clap::Args, Debug)]
pub struct UploadArgs {
    /// File or folder path to upload
    pub path: PathBuf,
    /// Compress as ZIP before uploading
    #[arg(long)]
    pub compress: bool,
    /// Upload using a specific account name
    #[arg(long)]
    pub account: Option<String>,
}

// ---------------------------------------------------------------------------
// Upload command entry point
// ---------------------------------------------------------------------------

/// Execute the upload command. Resolves account, builds R2 client, and uploads
/// each file with a terminal progress display.
pub async fn cmd_upload(args: UploadArgs) {
    let cfg = load_config();
    let (account, token) = resolve_account(&cfg, args.account.as_deref());

    let account_id = account.account_id.as_deref().unwrap_or_else(|| {
        eprintln!("Account \"{}\" missing account_id. Re-run `r2drop login`.", account.name);
        std::process::exit(1);
    });
    if account.bucket.is_empty() {
        eprintln!("Account \"{}\" has no bucket configured.", account.name);
        std::process::exit(1);
    }

    // CLI currently passes token as both S3 creds (legacy behavior).
    // When the CLI gets proper S3 credential support, these should be
    // replaced with the real access_key_id and secret_access_key.
    let client = R2Client::new(account_id, &token, &token, &token);
    let upload_cfg = UploadConfig {
        chunk_size_bytes: cfg.preferences.chunk_size_mb as usize * 1024 * 1024,
        concurrency: cfg.preferences.concurrent_uploads as usize,
    };

    // Validate and resolve the input path
    let path = match args.path.canonicalize() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Invalid path \"{}\": {e}", args.path.display());
            std::process::exit(1);
        }
    };

    // Build the list of (local_path, r2_key, should_cleanup) tuples
    let files: Vec<(PathBuf, String, bool)> = if args.compress {
        match compress_path(&path) {
            Ok(zip_path) => {
                let name = zip_path.file_name().unwrap().to_string_lossy().to_string();
                vec![(zip_path, build_r2_key(&account.path, &name), true)]
            }
            Err(e) => {
                eprintln!("Compression failed: {e}");
                std::process::exit(1);
            }
        }
    } else if path.is_dir() {
        collect_dir_files(&path, &account.path)
            .into_iter()
            .map(|(p, k)| (p, k, false))
            .collect()
    } else {
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        vec![(path.clone(), build_r2_key(&account.path, &name), false)]
    };

    if files.is_empty() {
        println!("No files to upload.");
        return;
    }
    println!("Uploading {} file(s) to {}/{}", files.len(), account.bucket, account.path);

    let cancel = AtomicBool::new(false);
    let mut ok_count = 0;

    for (local_path, r2_key, cleanup) in &files {
        let file_name = local_path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| r2_key.clone());
        let total = std::fs::metadata(local_path).map(|m| m.len()).unwrap_or(0);

        println!("  {} ({})", file_name, crate::format_bytes(total));

        // Progress callback — overwrites current line via \r
        let progress_cb: Box<dyn Fn(UploadProgress) + Send + Sync> = Box::new(|p| {
            let pct = if p.total_bytes > 0 {
                (p.bytes_uploaded * 100) / p.total_bytes
            } else {
                100
            };
            let speed = format_speed(p.speed_bytes_per_sec);
            let eta = match p.eta_seconds {
                Some(s) if s > 0.5 => format!("ETA {s:.0}s"),
                _ => String::new(),
            };
            print!("\r    {pct:>3}%  {speed}  {eta}          ");
            let _ = std::io::stdout().flush();
        });

        match upload::upload_file(
            &client,
            &account.bucket,
            r2_key,
            local_path,
            &upload_cfg,
            Some(progress_cb),
            &cancel,
        )
        .await
        {
            Ok(result) => {
                // Overwrite progress line with result
                if result.already_existed {
                    print!("\r    skipped (already exists)              \n");
                } else {
                    print!("\r    done                                  \n");
                }
                record_history(&file_name, total, r2_key, &account.bucket, &account.name);
                ok_count += 1;
            }
            Err(e) => {
                print!("\r    failed: {e}                           \n");
            }
        }

        if *cleanup {
            let _ = std::fs::remove_file(local_path);
        }
    }

    println!("{ok_count}/{} file(s) uploaded.", files.len());
}

// ---------------------------------------------------------------------------
// Account resolution
// ---------------------------------------------------------------------------

fn load_config() -> Config {
    Config::load().unwrap_or_else(|e| {
        eprintln!("Error loading config: {e}");
        std::process::exit(1);
    })
}

/// Resolve account by name (from --account flag) or fall back to active_account.
/// Returns the account reference and its token from the keychain.
fn resolve_account<'a>(
    cfg: &'a Config,
    name: Option<&str>,
) -> (&'a r2_core::config::Account, String) {
    let account_name = name
        .map(|s| s.to_string())
        .or_else(|| cfg.active_account.clone())
        .unwrap_or_else(|| {
            eprintln!("No account specified. Use --account or run `r2drop login`.");
            std::process::exit(1);
        });

    let account = cfg
        .accounts
        .iter()
        .find(|a| a.name == account_name)
        .unwrap_or_else(|| {
            eprintln!("Account \"{account_name}\" not found in config.");
            std::process::exit(1);
        });

    let token = credentials::get_token(&account.name).unwrap_or_else(|e| {
        eprintln!("No token for \"{}\": {e}. Run `r2drop login`.", account.name);
        std::process::exit(1);
    });

    (account, token)
}

// ---------------------------------------------------------------------------
// File collection helpers
// ---------------------------------------------------------------------------

/// Build an R2 key by joining a path prefix with a file name.
fn build_r2_key(prefix: &str, name: &str) -> String {
    if prefix.is_empty() {
        name.to_string()
    } else if prefix.ends_with('/') {
        format!("{prefix}{name}")
    } else {
        format!("{prefix}/{name}")
    }
}

/// Walk a directory recursively, returning (absolute_path, r2_key) pairs.
/// The R2 key preserves the directory name as a top-level folder.
fn collect_dir_files(dir: &Path, prefix: &str) -> Vec<(PathBuf, String)> {
    let mut files = Vec::new();
    let dir_name = dir.file_name().unwrap_or_default().to_string_lossy();
    walk_dir(dir, dir, &dir_name, prefix, &mut files);
    files
}

fn walk_dir(
    path: &Path,
    base: &Path,
    dir_name: &str,
    prefix: &str,
    out: &mut Vec<(PathBuf, String)>,
) {
    let entries = match std::fs::read_dir(path) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("Warning: cannot read {}: {e}", path.display());
            return;
        }
    };
    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_dir() {
            walk_dir(&p, base, dir_name, prefix, out);
        } else if p.is_file() {
            let relative = p.strip_prefix(base).unwrap_or(&p);
            let r2_name = format!("{dir_name}/{}", relative.to_string_lossy());
            out.push((p, build_r2_key(prefix, &r2_name)));
        }
    }
}

// ---------------------------------------------------------------------------
// ZIP compression (--compress flag)
// ---------------------------------------------------------------------------

/// Compress a file or directory into a ZIP in the system temp directory.
/// Returns the path to the created ZIP file.
fn compress_path(source: &Path) -> Result<PathBuf, String> {
    let stem = source.file_name().unwrap_or_default().to_string_lossy();
    let zip_path = std::env::temp_dir().join(format!("{stem}.zip"));

    let file =
        std::fs::File::create(&zip_path).map_err(|e| format!("create zip: {e}"))?;
    let mut zip = zip::ZipWriter::new(file);
    let opts = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);

    if source.is_file() {
        let name = source.file_name().unwrap().to_string_lossy();
        zip.start_file(name.as_ref(), opts)
            .map_err(|e| format!("zip start_file: {e}"))?;
        let mut f = std::fs::File::open(source).map_err(|e| e.to_string())?;
        std::io::copy(&mut f, &mut zip).map_err(|e| e.to_string())?;
    } else {
        add_dir_to_zip(&mut zip, source, source, opts)?;
    }

    zip.finish().map_err(|e| format!("zip finish: {e}"))?;
    let size = std::fs::metadata(&zip_path).map(|m| m.len()).unwrap_or(0);
    println!("Compressed to {} ({})", zip_path.display(), crate::format_bytes(size));
    Ok(zip_path)
}

/// Recursively add directory contents to a ZIP archive.
fn add_dir_to_zip(
    zip: &mut zip::ZipWriter<std::fs::File>,
    path: &Path,
    base: &Path,
    opts: zip::write::SimpleFileOptions,
) -> Result<(), String> {
    for entry in std::fs::read_dir(path).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let p = entry.path();
        let rel = p.strip_prefix(base).unwrap().to_string_lossy().to_string();

        if p.is_dir() {
            zip.add_directory(format!("{rel}/"), opts)
                .map_err(|e| format!("zip add_directory: {e}"))?;
            add_dir_to_zip(zip, &p, base, opts)?;
        } else {
            zip.start_file(&rel, opts)
                .map_err(|e| format!("zip start_file: {e}"))?;
            let mut f = std::fs::File::open(&p).map_err(|e| e.to_string())?;
            std::io::copy(&mut f, zip).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// History & formatting helpers
// ---------------------------------------------------------------------------

/// Record a completed upload in history.db (best-effort, ignores errors).
fn record_history(file_name: &str, size: u64, r2_key: &str, bucket: &str, account: &str) {
    if let Ok(db) = HistoryDb::open_default() {
        let _ = db.insert_entry(file_name, size, r2_key, bucket, account, "");
    }
}

/// Format upload speed as a human-readable string (e.g. "2.3 MB/s").
fn format_speed(bytes_per_sec: f64) -> String {
    let bps = bytes_per_sec as u64;
    if bps >= 1_048_576 {
        format!("{:.1} MB/s", bytes_per_sec / 1_048_576.0)
    } else if bps >= 1024 {
        format!("{:.0} KB/s", bytes_per_sec / 1024.0)
    } else {
        format!("{bps} B/s")
    }
}
