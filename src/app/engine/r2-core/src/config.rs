// r2-core/src/config.rs — TOML config parsing and writing for R2Drop
// Manages ~/.r2drop/config.toml with account list, active account, and preferences.
// Supports R2DROP_HOME env var to override the default config directory.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("failed to read config file: {0}")]
    Read(#[from] std::io::Error),

    #[error("failed to parse config TOML: {0}")]
    Parse(#[from] toml::de::Error),

    #[error("failed to serialize config to TOML: {0}")]
    Serialize(#[from] toml::ser::Error),
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// A single Cloudflare R2 account entry.
/// Credentials (API tokens) are stored in macOS Keychain — never in this struct.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Account {
    pub name: String,
    /// Cloudflare account ID (hex string). Needed for API calls.
    #[serde(default)]
    pub account_id: Option<String>,
    pub bucket: String,
    /// Default upload path prefix inside the bucket (e.g. "uploads/").
    #[serde(default)]
    pub path: String,
    /// Optional custom domain for public URLs (e.g. "cdn.example.com").
    #[serde(default)]
    pub custom_domain: Option<String>,
}

/// Global upload and UI preferences.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Preferences {
    /// Number of parallel upload workers (1–16, default 4).
    #[serde(default = "default_concurrent_uploads")]
    pub concurrent_uploads: u8,

    /// Multipart chunk size in megabytes (5–100, default 8).
    #[serde(default = "default_chunk_size_mb")]
    pub chunk_size_mb: u8,

    /// Glob patterns for files to skip (e.g. ".DS_Store").
    #[serde(default = "default_exclusion_patterns")]
    pub exclusion_patterns: Vec<String>,

    /// Start R2Drop automatically when the user logs in.
    #[serde(default)]
    pub launch_at_login: bool,

    /// Hide the Dock icon and run as a menu-bar-only app.
    #[serde(default)]
    pub hide_dock_icon: bool,

    /// Play a system sound when an upload completes.
    #[serde(default = "default_true")]
    pub play_sound: bool,

    /// Follow symlinks during upload (default: false = skip symlinks).
    #[serde(default)]
    pub follow_symlinks: bool,

    /// Maximum number of rotated log files to keep (default 5).
    #[serde(default = "default_max_log_files")]
    pub max_log_files: u16,

    /// Maximum log file size in megabytes before rotation (default 10).
    #[serde(default = "default_max_log_file_size_mb")]
    pub max_log_file_size_mb: u16,
}

// Serde default helpers
fn default_concurrent_uploads() -> u8 {
    4
}
fn default_chunk_size_mb() -> u8 {
    8
}
fn default_exclusion_patterns() -> Vec<String> {
    vec![
        ".DS_Store".into(),
        "._*".into(),
        ".Thumbs.db".into(),
        ".Spotlight-V100".into(),
        ".Trashes".into(),
        "__MACOSX".into(),
        ".fseventsd".into(),
    ]
}
fn default_true() -> bool {
    true
}
fn default_max_log_files() -> u16 {
    5
}
fn default_max_log_file_size_mb() -> u16 {
    10
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            concurrent_uploads: default_concurrent_uploads(),
            chunk_size_mb: default_chunk_size_mb(),
            exclusion_patterns: default_exclusion_patterns(),
            launch_at_login: false,
            hide_dock_icon: false,
            play_sound: true,
            follow_symlinks: false,
            max_log_files: default_max_log_files(),
            max_log_file_size_mb: default_max_log_file_size_mb(),
        }
    }
}

/// Top-level config file: `~/.r2drop/config.toml`.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Config {
    /// Which account name is currently active (matches an entry in `accounts`).
    #[serde(default)]
    pub active_account: Option<String>,

    /// Registered Cloudflare R2 accounts.
    #[serde(default)]
    pub accounts: Vec<Account>,

    /// Global preferences.
    #[serde(default)]
    pub preferences: Preferences,
}

// ---------------------------------------------------------------------------
// Directory resolution
// ---------------------------------------------------------------------------

/// Returns the R2Drop config directory path.
///
/// Priority:
/// 1. `R2DROP_HOME` env var (if set and non-empty)
/// 2. `~/.r2drop/`
///
/// Creates the directory (and parents) if it doesn't exist.
pub fn config_dir() -> Result<PathBuf, ConfigError> {
    let dir = match std::env::var("R2DROP_HOME") {
        Ok(val) if !val.is_empty() => PathBuf::from(val),
        _ => {
            let home = dirs_home().ok_or_else(|| {
                ConfigError::Read(std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "could not determine home directory",
                ))
            })?;
            home.join(".r2drop")
        }
    };

    // Create directory (and parents) if missing
    if !dir.exists() {
        fs::create_dir_all(&dir)?;
    }

    Ok(dir)
}

/// Portable home directory lookup (avoids pulling in the full `directories` crate API).
fn dirs_home() -> Option<PathBuf> {
    directories::BaseDirs::new().map(|d| d.home_dir().to_path_buf())
}

/// Full path to `config.toml` inside the config directory.
pub fn config_path() -> Result<PathBuf, ConfigError> {
    Ok(config_dir()?.join("config.toml"))
}

// ---------------------------------------------------------------------------
// Read / Write
// ---------------------------------------------------------------------------

impl Config {
    /// Load config from the default path (`~/.r2drop/config.toml`).
    /// Returns `Config::default()` if the file doesn't exist yet.
    pub fn load() -> Result<Self, ConfigError> {
        let path = config_path()?;
        Self::load_from(&path)
    }

    /// Load config from a specific path.
    /// Returns `Config::default()` if the file doesn't exist yet.
    pub fn load_from(path: &Path) -> Result<Self, ConfigError> {
        if !path.exists() {
            return Ok(Self::default());
        }
        let contents = fs::read_to_string(path)?;
        let cfg: Config = toml::from_str(&contents)?;
        Ok(cfg)
    }

    /// Save config to the default path (`~/.r2drop/config.toml`).
    pub fn save(&self) -> Result<(), ConfigError> {
        let path = config_path()?;
        self.save_to(&path)
    }

    /// Save config to a specific path.
    pub fn save_to(&self, path: &Path) -> Result<(), ConfigError> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)?;
            }
        }
        let toml_str = toml::to_string_pretty(self)?;
        fs::write(path, toml_str)?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    /// Helper: create a temp dir and point R2DROP_HOME at it.
    fn with_temp_home(f: impl FnOnce(PathBuf)) {
        let tmp = tempfile::tempdir().unwrap();
        let prev = env::var("R2DROP_HOME").ok();
        env::set_var("R2DROP_HOME", tmp.path());
        f(tmp.path().to_path_buf());
        // Restore
        match prev {
            Some(v) => env::set_var("R2DROP_HOME", v),
            None => env::remove_var("R2DROP_HOME"),
        }
    }

    #[test]
    fn default_config_has_sane_values() {
        let cfg = Config::default();
        assert_eq!(cfg.preferences.concurrent_uploads, 4);
        assert_eq!(cfg.preferences.chunk_size_mb, 8);
        assert!(cfg.preferences.play_sound);
        assert!(!cfg.preferences.launch_at_login);
        assert!(!cfg.preferences.hide_dock_icon);
        assert!(cfg.preferences.exclusion_patterns.contains(&".DS_Store".to_string()));
        assert!(cfg.accounts.is_empty());
        assert!(cfg.active_account.is_none());
    }

    #[test]
    fn load_returns_default_when_file_missing() {
        with_temp_home(|dir| {
            let path = dir.join("config.toml");
            let cfg = Config::load_from(&path).unwrap();
            assert_eq!(cfg, Config::default());
        });
    }

    #[test]
    fn round_trip_preserves_all_fields() {
        with_temp_home(|dir| {
            let path = dir.join("config.toml");

            let original = Config {
                active_account: Some("work".into()),
                accounts: vec![
                    Account {
                        name: "work".into(),
                        account_id: Some("abc123def456".into()),
                        bucket: "my-bucket".into(),
                        path: "uploads/".into(),
                        custom_domain: Some("cdn.example.com".into()),
                    },
                    Account {
                        name: "personal".into(),
                        account_id: None,
                        bucket: "personal-bucket".into(),
                        path: String::new(),
                        custom_domain: None,
                    },
                ],
                preferences: Preferences {
                    concurrent_uploads: 8,
                    chunk_size_mb: 16,
                    exclusion_patterns: vec![".DS_Store".into(), "*.tmp".into()],
                    launch_at_login: true,
                    hide_dock_icon: true,
                    play_sound: false,
                    follow_symlinks: true,
                    max_log_files: 10,
                    max_log_file_size_mb: 20,
                },
            };

            original.save_to(&path).unwrap();
            let loaded = Config::load_from(&path).unwrap();
            assert_eq!(original, loaded);
        });
    }

    #[test]
    fn r2drop_home_env_overrides_default_dir() {
        with_temp_home(|dir| {
            let resolved = config_dir().unwrap();
            assert_eq!(resolved, dir);
        });
    }

    #[test]
    fn config_dir_creates_missing_directory() {
        // Use a nested path inside a temp dir to verify parent creation.
        let tmp = tempfile::tempdir().unwrap();
        let nested = tmp.path().join("deeply").join("nested");
        let prev = env::var("R2DROP_HOME").ok();
        env::set_var("R2DROP_HOME", &nested);

        let resolved = config_dir().unwrap();
        assert!(resolved.exists());
        // Only check the directory was created (not exact equality) because
        // parallel tests may race on R2DROP_HOME env var.
        assert!(nested.exists());

        // Restore
        match prev {
            Some(v) => env::set_var("R2DROP_HOME", v),
            None => env::remove_var("R2DROP_HOME"),
        }
    }

    #[test]
    fn save_creates_parent_dirs() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("sub").join("dir").join("config.toml");
        let cfg = Config::default();
        cfg.save_to(&path).unwrap();
        assert!(path.exists());
    }

    #[test]
    fn partial_toml_fills_defaults() {
        with_temp_home(|dir| {
            let path = dir.join("config.toml");
            // Write a minimal TOML — missing preferences entirely
            fs::write(
                &path,
                r#"
active_account = "test"

[[accounts]]
name = "test"
bucket = "b"
"#,
            )
            .unwrap();

            let cfg = Config::load_from(&path).unwrap();
            assert_eq!(cfg.active_account, Some("test".into()));
            assert_eq!(cfg.accounts.len(), 1);
            assert_eq!(cfg.accounts[0].path, ""); // default empty string
            // Preferences should be defaults
            assert_eq!(cfg.preferences.concurrent_uploads, 4);
            assert_eq!(cfg.preferences.chunk_size_mb, 8);
            assert!(cfg.preferences.play_sound);
        });
    }

    #[test]
    fn modify_and_rewrite_preserves_data() {
        with_temp_home(|dir| {
            let path = dir.join("config.toml");

            let mut cfg = Config::default();
            cfg.accounts.push(Account {
                name: "first".into(),
                account_id: None,
                bucket: "b1".into(),
                path: String::new(),
                custom_domain: None,
            });
            cfg.active_account = Some("first".into());
            cfg.save_to(&path).unwrap();

            // Reload, modify, save, reload
            let mut cfg2 = Config::load_from(&path).unwrap();
            cfg2.preferences.concurrent_uploads = 16;
            cfg2.accounts.push(Account {
                name: "second".into(),
                account_id: Some("xyz789".into()),
                bucket: "b2".into(),
                path: "data/".into(),
                custom_domain: Some("cdn.test.com".into()),
            });
            cfg2.save_to(&path).unwrap();

            let cfg3 = Config::load_from(&path).unwrap();
            assert_eq!(cfg3.preferences.concurrent_uploads, 16);
            assert_eq!(cfg3.accounts.len(), 2);
            assert_eq!(cfg3.accounts[1].custom_domain, Some("cdn.test.com".into()));
        });
    }
}
