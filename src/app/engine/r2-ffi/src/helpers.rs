// r2-ffi/src/helpers.rs — Internal helpers for the FFI bridge
// Provides the tokio runtime, thread-local error storage, string conversion,
// and the global network availability flag (FR-031).

use std::cell::RefCell;
use std::ffi::CString;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

// ---------------------------------------------------------------------------
// Tokio runtime (shared across all FFI calls)
// ---------------------------------------------------------------------------

/// Lazily-initialized multi-threaded tokio runtime.
/// All async FFI functions run their futures on this runtime via `block_on`.
static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

/// Get or create the shared tokio runtime.
pub fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to create tokio runtime")
    })
}

// ---------------------------------------------------------------------------
// Global network availability flag (FR-031)
// ---------------------------------------------------------------------------

/// Shared flag indicating whether the device has network connectivity.
/// Updated by Swift via `r2_set_network_available()`, read by the runner.
static NETWORK_AVAILABLE: AtomicBool = AtomicBool::new(true);

/// Get a reference to the global network availability flag.
pub fn network_available() -> &'static AtomicBool {
    &NETWORK_AVAILABLE
}

/// Toggle network availability and log the transition.
/// Called by the FFI layer when Swift reports connectivity changes.
pub fn set_network_available(available: bool) {
    if available {
        tracing::info!("network connectivity restored, resuming queue processing");
        NETWORK_AVAILABLE.store(true, Ordering::Relaxed);
    } else {
        tracing::warn!("network connectivity lost, pausing queue processing");
        NETWORK_AVAILABLE.store(false, Ordering::Relaxed);
    }
}

// ---------------------------------------------------------------------------
// Thread-local error storage
// ---------------------------------------------------------------------------

thread_local! {
    /// Last error message from an FFI call. Set by `set_last_error`, read by
    /// `r2_get_last_error`. Thread-local so concurrent FFI calls don't clobber.
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

/// Store an error message for later retrieval via `r2_get_last_error`.
pub fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

/// Take the last error message (clears it). Returns None if no error is stored.
pub fn take_last_error() -> Option<String> {
    LAST_ERROR.with(|e| e.borrow_mut().take())
}

// ---------------------------------------------------------------------------
// String conversion helpers
// ---------------------------------------------------------------------------

/// Convert a Rust string to a C-allocated `*mut c_char`.
/// Caller must free the result with `r2_free_string`.
/// Returns null if the string contains interior NUL bytes.
pub fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cs) => cs.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Convert a C string pointer to a Rust &str.
/// Returns None if the pointer is null or not valid UTF-8.
///
/// # Safety
/// `ptr` must point to a valid NUL-terminated C string or be null.
pub unsafe fn from_c_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { std::ffi::CStr::from_ptr(ptr) }.to_str().ok()
}
