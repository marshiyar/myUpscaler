//! myUpscaler's processing backend, linked into the app as `libup60p.a` behind a C API whose header (`up60p.h`)
//! is generated from this crate (`header.rs`). Restoration filters, Lanczos scaling and frame interpolation are implemented here;
//! decoding, H.264 encoding and MP4 muxing go through the MpVFX media engine (`libmpvfx_ffi`). No FFmpeg and no
//! external processes.

pub mod engine;
pub mod filters;
pub mod frame;
pub mod header;
pub mod job;
pub mod options;
pub mod par;
pub mod pipeline;
pub mod png;

use std::ffi::{c_char, c_int, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

use job::{Job, JobError};
use options::{text, Options};

/// `up60p_error` in the generated `up60p.h`.
pub mod status {
    pub const OK: i32 = 0;
    pub const INVALID_OPTIONS: i32 = 1;
    pub const ENGINE_UNAVAILABLE: i32 = 2;
    pub const IO: i32 = 3;
    pub const INTERNAL: i32 = 4;
    pub const CANCELLED: i32 = 5;
    pub const UNSUPPORTED_SCALER: i32 = 6;
    /// Success for a single file whose output was written and moved into place (a folder run returns `OK`).
    pub const OK_COMMITTED: i32 = 7;
    pub const UNSUPPORTED_MEDIA: i32 = 8;

    /// Header names (after `UP60P_`) and values.
    pub const ALL: &[(&str, i32)] = &[
        ("OK", OK),
        ("ERR_INVALID_OPTIONS", INVALID_OPTIONS),
        ("ERR_ENGINE_UNAVAILABLE", ENGINE_UNAVAILABLE),
        ("ERR_IO", IO),
        ("ERR_INTERNAL", INTERNAL),
        ("ERR_CANCELLED", CANCELLED),
        ("ERR_UNSUPPORTED_SCALER", UNSUPPORTED_SCALER),
        ("OK_COMMITTED", OK_COMMITTED),
        ("ERR_UNSUPPORTED_MEDIA", UNSUPPORTED_MEDIA),
    ];
}

pub type LogCallback = extern "C" fn(*const c_char);

static LOG: Mutex<Option<LogCallback>> = Mutex::new(None);
static CANCEL: AtomicBool = AtomicBool::new(false);
static DRY_RUN: AtomicBool = AtomicBool::new(false);
static BUSY: Mutex<()> = Mutex::new(());

fn log(message: &str) {
    let callback = *LOG.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(cb) = callback {
        let clean: Vec<u8> = message.bytes().filter(|&b| b != 0).collect();
        if let Ok(c) = CString::new(clean) {
            cb(c.as_ptr());
        }
    }
}

fn guarded(f: impl FnOnce() -> c_int) -> c_int {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| {
        log("Internal error in the processing engine.\n");
        status::INTERNAL
    })
}

/// Registers the log callback and checks that the media engine is present.
#[no_mangle]
pub extern "C" fn up60p_init(_app_support_dir: *const c_char, log_cb: Option<LogCallback>) -> c_int {
    guarded(|| {
        *LOG.lock().unwrap_or_else(|e| e.into_inner()) = log_cb;
        match engine::version() {
            Some(v) => {
                log(&format!("Rust engine {} with MpVFX media engine {v}\n", env!("CARGO_PKG_VERSION")));
                status::OK
            }
            None => {
                log("The MpVFX media engine is missing from this build. Reinstall the app.\n");
                status::ENGINE_UNAVAILABLE
            }
        }
    })
}

/// Fills `out` with the factory settings.
///
/// # Safety
/// `out` is NULL or points to writable memory for one `up60p_options`.
#[no_mangle]
pub unsafe extern "C" fn up60p_default_options(out: *mut Options) {
    if !out.is_null() {
        // SAFETY: the caller provides space for one Options.
        unsafe { out.write(Options::default()) };
    }
}

/// Processes a file or, recursively, every video and image in a folder. Blocks until done; one run at a time.
///
/// # Safety
/// `input_path` is NULL or a NUL-terminated string; `opts` is NULL or points to a valid `up60p_options`.
#[no_mangle]
pub unsafe extern "C" fn up60p_process_path(input_path: *const c_char, opts: *const Options) -> c_int {
    if input_path.is_null() || opts.is_null() {
        return status::INVALID_OPTIONS;
    }
    // SAFETY: checked non-NULL; the caller guarantees validity for the duration of the call.
    let (input, options) = unsafe { (CStr::from_ptr(input_path).to_string_lossy().into_owned(), (*opts).clone()) };
    guarded(|| {
        let Ok(_busy) = BUSY.try_lock() else {
            log("Another file is already being processed.\n");
            return status::INTERNAL;
        };
        if text(&options.scaler) != "lanczos" {
            log("The selected upscaling mode is not handled by the Rust engine. Choose Lanczos or CoreML.\n");
            return status::UNSUPPORTED_SCALER;
        }
        if engine::version().is_none() {
            log("The MpVFX media engine is missing from this build. Reinstall the app.\n");
            return status::ENGINE_UNAVAILABLE;
        }
        CANCEL.store(false, Ordering::SeqCst);
        job::configure_threads(&options);
        let dry_run = DRY_RUN.load(Ordering::Relaxed);
        let job = Job { options: &options, log: &log, cancel: &CANCEL, dry_run };
        let path = Path::new(&input);
        match job.run(path) {
            // A single file's output is in place; a folder run may still be cancelled before its next file.
            Ok(()) if !dry_run && path.is_file() => status::OK_COMMITTED,
            Ok(()) => status::OK,
            Err(JobError::Cancelled) => {
                log("Processing cancelled.\n");
                status::CANCELLED
            }
            Err(e) => {
                log(&format!("Error: {e}\n"));
                match e {
                    JobError::InvalidOptions(_) => status::INVALID_OPTIONS,
                    JobError::Unsupported(_) => status::UNSUPPORTED_MEDIA,
                    JobError::Io(_) => status::IO,
                    JobError::Engine(e) if e.code == -3 => status::UNSUPPORTED_MEDIA,
                    JobError::Engine(_) => status::IO,
                    JobError::Cancelled => status::CANCELLED,
                }
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn up60p_set_dry_run(enable: c_int) {
    DRY_RUN.store(enable != 0, Ordering::Relaxed);
}

/// Asks a running `up60p_process_path` to stop; it returns `UP60P_ERR_CANCELLED` and leaves no partial output.
#[no_mangle]
pub extern "C" fn up60p_request_cancel() {
    CANCEL.store(true, Ordering::SeqCst);
}

/// Cancels any run and stops logging.
#[no_mangle]
pub extern "C" fn up60p_shutdown() {
    CANCEL.store(true, Ordering::SeqCst);
}

/// The media engine's version string (static storage), or NULL when it is not linked.
#[no_mangle]
pub extern "C" fn up60p_engine_version() -> *const c_char {
    static VERSION: OnceLock<Option<CString>> = OnceLock::new();
    VERSION
        .get_or_init(|| engine::version().and_then(|v| CString::new(v).ok()))
        .as_ref()
        .map_or(std::ptr::null(), |c| c.as_ptr())
}

/// `sizeof(up60p_options)`, so the app can check at startup that it and the library agree on the layout.
#[no_mangle]
pub extern "C" fn up60p_options_size() -> usize {
    std::mem::size_of::<Options>()
}
