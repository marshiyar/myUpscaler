//! Each function the app calls through `up60p.h`, called the way Swift calls it: raw pointers, a C log callback,
//! status codes. The library keeps process-wide state (log callback, cancel flag, one run at a time), so these run
//! one at a time.

use std::ffi::{c_char, CStr, CString};
use std::sync::Mutex;

use up60p::options::{set, text, Options};
use up60p::{
    status, up60p_default_options, up60p_engine_version, up60p_init, up60p_options_size, up60p_process_path,
    up60p_request_cancel, up60p_set_dry_run, up60p_shutdown,
};

static SERIAL: Mutex<()> = Mutex::new(());
static LOG: Mutex<Vec<String>> = Mutex::new(Vec::new());

extern "C" fn capture(message: *const c_char) {
    // SAFETY: the library passes a NUL-terminated string valid for the call.
    let m = unsafe { CStr::from_ptr(message) }.to_string_lossy().into_owned();
    LOG.lock().unwrap_or_else(|e| e.into_inner()).push(m);
}

fn log_text() -> String {
    LOG.lock().unwrap_or_else(|e| e.into_inner()).join("")
}

fn engine_present() -> bool {
    !up60p_engine_version().is_null()
}

fn process(path: &str, o: &Options) -> i32 {
    let c = CString::new(path).unwrap();
    // SAFETY: both pointers are valid for the call.
    unsafe { up60p_process_path(c.as_ptr(), o) }
}

fn defaults() -> Options {
    let mut o = std::mem::MaybeUninit::<Options>::uninit();
    // SAFETY: the function writes a whole Options.
    unsafe {
        up60p_default_options(o.as_mut_ptr());
        o.assume_init()
    }
}

fn scratch(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("up60p-capi-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn init_registers_the_log_and_reports_the_engine() {
    let _s = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    LOG.lock().unwrap().clear();
    let code = up60p_init(std::ptr::null(), Some(capture));
    if engine_present() {
        assert_eq!(code, status::OK);
        assert!(log_text().contains("MpVFX media engine"), "{}", log_text());
        // SAFETY: non-NULL static string.
        assert!(!unsafe { CStr::from_ptr(up60p_engine_version()) }.to_bytes().is_empty());
    } else {
        assert_eq!(code, status::ENGINE_UNAVAILABLE);
    }
}

#[test]
fn default_options_are_the_factory_settings_and_null_is_ignored() {
    let o = defaults();
    assert_eq!(text(&o.scaler), "lanczos");
    assert_eq!(text(&o.denoiser), "bm3d");
    assert_eq!(text(&o.scale_factor), "2");
    // SAFETY: NULL is documented as accepted.
    unsafe { up60p_default_options(std::ptr::null_mut()) };
    assert_eq!(up60p_options_size(), std::mem::size_of::<Options>());
}

#[test]
fn process_rejects_null_and_unsupported_scalers() {
    let _s = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let o = defaults();
    // SAFETY: NULL arguments are checked by the library.
    assert_eq!(unsafe { up60p_process_path(std::ptr::null(), &o) }, status::INVALID_OPTIONS);
    let c = CString::new("x.mp4").unwrap();
    // SAFETY: as above.
    assert_eq!(unsafe { up60p_process_path(c.as_ptr(), std::ptr::null()) }, status::INVALID_OPTIONS);
    let mut coreml = defaults();
    set(&mut coreml.scaler, "coreml");
    assert_eq!(process("x.mp4", &coreml), status::UNSUPPORTED_SCALER);
}

#[test]
fn missing_and_unsupported_inputs_return_errors() {
    let _s = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_present() {
        return;
    }
    up60p_init(std::ptr::null(), Some(capture));
    let dir = scratch("errors");
    assert_eq!(process(dir.join("missing.mp4").to_str().unwrap(), &defaults()), status::IO);
    std::fs::write(dir.join("scan.tiff"), b"II*\0").unwrap();
    assert_eq!(process(dir.join("scan.tiff").to_str().unwrap(), &defaults()), status::UNSUPPORTED_MEDIA);
}

#[test]
fn dry_run_plans_without_writing_and_cancel_is_cleared_per_run() {
    let _s = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_present() {
        return;
    }
    up60p_init(std::ptr::null(), Some(capture));
    let dir = scratch("dry");
    let input = dir.join("still.png");
    up60p::png::write(&input, &[200; 12 * 10 * 4], 12, 10, false).unwrap();

    LOG.lock().unwrap().clear();
    up60p_set_dry_run(1);
    assert_eq!(process(input.to_str().unwrap(), &defaults()), status::OK);
    up60p_set_dry_run(0);
    assert!(log_text().contains("CMD: up60p -i "), "{}", log_text());
    assert!(!dir.join("still_[restored].png").exists(), "dry run wrote output");

    // A cancel requested between runs does not stop the next run.
    // A single file reports that its output is committed; a folder run reports plain success.
    up60p_request_cancel();
    assert_eq!(process(input.to_str().unwrap(), &defaults()), status::OK_COMMITTED);
    assert!(dir.join("still_[restored].png").is_file());
    assert_eq!(process(dir.to_str().unwrap(), &defaults()), status::OK);

    // Invalid settings are refused before anything is written.
    let mut bad = defaults();
    up60p::options::set(&mut bad.eq_saturation, "9");
    std::fs::remove_file(dir.join("still_[restored].png")).unwrap();
    assert_eq!(process(input.to_str().unwrap(), &bad), status::INVALID_OPTIONS);
    assert!(!dir.join("still_[restored].png").exists());
    up60p_shutdown();
}
