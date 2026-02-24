// r2-core/src/logging.rs — Structured audit logging for R2Drop (FR-067, FR-068)
// Provides rolling file appender with configurable retention.
// Logs upload activity (start, progress, complete, fail, retry) with structured fields.
// NEVER logs API tokens or credentials.

use std::fs;
use std::path::PathBuf;

use tracing_appender::rolling;
use tracing_subscriber::fmt;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::EnvFilter;

use crate::config;

// ---------------------------------------------------------------------------
// Log directory resolution
// ---------------------------------------------------------------------------

/// Returns the logs directory path: `~/.r2drop/logs/` (or `$R2DROP_HOME/logs/`).
/// Creates the directory if it doesn't exist.
pub fn logs_dir() -> Result<PathBuf, config::ConfigError> {
    let dir = config::config_dir()?.join("logs");
    if !dir.exists() {
        fs::create_dir_all(&dir)?;
    }
    Ok(dir)
}

// ---------------------------------------------------------------------------
// Logger initialization
// ---------------------------------------------------------------------------

/// Initialize the global tracing subscriber with a rolling file appender.
///
/// - Logs to `~/.r2drop/logs/r2drop.log` with daily rotation (FR-067).
/// - Keeps up to `max_log_files` rotated files (configurable retention).
/// - Log format: timestamp + level + target + structured fields.
/// - Also logs to stderr when `also_stderr` is true (useful for CLI).
/// - Safe to call once per process. Subsequent calls are no-ops.
///
/// Returns Ok(()) if the subscriber was installed, or Err if it failed.
/// If a subscriber is already installed (e.g. in tests), returns Ok(()) silently.
pub fn init_logging(max_log_files: usize, also_stderr: bool) -> Result<(), config::ConfigError> {
    let log_dir = logs_dir()?;

    // Daily rolling file appender: r2drop.YYYY-MM-DD.log
    let file_appender = rolling::Builder::new()
        .rotation(rolling::Rotation::DAILY)
        .filename_prefix("r2drop")
        .filename_suffix("log")
        .max_log_files(max_log_files)
        .build(log_dir)
        .map_err(|e| {
            config::ConfigError::Read(std::io::Error::other(e))
        })?;

    // Default filter: info level, overridable via RUST_LOG env var
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    // File layer — always active
    let file_layer = fmt::layer()
        .with_writer(file_appender)
        .with_ansi(false)
        .with_target(true)
        .with_thread_ids(false);

    if also_stderr {
        // CLI mode: log to both file and stderr
        let stderr_layer = fmt::layer()
            .with_writer(std::io::stderr)
            .with_ansi(true)
            .with_target(false);

        tracing_subscriber::registry()
            .with(env_filter)
            .with(file_layer)
            .with(stderr_layer)
            .try_init()
            .ok();
    } else {
        // App mode: log to file only (no terminal noise)
        tracing_subscriber::registry()
            .with(env_filter)
            .with(file_layer)
            .try_init()
            .ok();
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn logs_dir_is_inside_config_dir() {
        let tmp = tempfile::tempdir().unwrap();
        std::env::set_var("R2DROP_HOME", tmp.path());
        let dir = logs_dir().unwrap();
        assert!(dir.ends_with("logs"));
        assert!(dir.exists());
        std::env::remove_var("R2DROP_HOME");
    }

    #[test]
    fn init_logging_does_not_panic() {
        // In test context a subscriber may already be installed.
        // init_logging should handle this gracefully (no-op).
        let tmp = tempfile::tempdir().unwrap();
        std::env::set_var("R2DROP_HOME", tmp.path());
        let result = init_logging(3, false);
        assert!(result.is_ok());
        std::env::remove_var("R2DROP_HOME");
    }
}
