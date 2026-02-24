// r2-core/src/lib.rs — Shared upload engine library for R2Drop
// Provides config parsing, S3 client, upload logic, queue, and hashing.
// Used by both the FFI bridge (r2-ffi) and the CLI (r2-cli).

pub mod config;
pub mod credentials;
pub mod hash;
pub mod history;
pub mod logging;
pub mod queue;
pub mod runner;
pub mod s3;
pub mod upload;
