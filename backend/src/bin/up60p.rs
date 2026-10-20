//! Command-line front end to the backend, for testing and batch use outside the app:
//!
//! ```text
//! up60p [--set key=value ...] [--dry-run] <input file or folder>
//! up60p --write-header <path>     # the C header Swift imports (see header.rs)
//! ```
//!
//! Keys are the `up60p_options` field names (`scale_factor=4`, `denoiser=hqdn3d`, `no_grain=1`, `outdir=/tmp`).

use std::process::ExitCode;
use std::sync::atomic::AtomicBool;

use up60p::job::{configure_threads, Job, JobError};
use up60p::options::{set, Options};

fn apply(o: &mut Options, key: &str, value: &str) -> Result<(), String> {
    let flag = |v: &str| -> Result<i32, String> { v.parse::<i32>().map_err(|_| format!("{key} takes 0 or 1")) };
    macro_rules! fields {
        (text: $($t:ident),*; flags: $($f:ident),*) => {
            match key {
                $(stringify!($t) => set(&mut o.$t, value),)*
                $(stringify!($f) => o.$f = flag(value)?,)*
                _ => return Err(format!("unknown option {key}")),
            }
        };
    }
    fields!(
        text: codec, crf, preset, fps, scale_factor, scaler, denoiser, denoise_strength, deblock_mode, deblock_thresh,
            dering_strength, sharpen_method, sharpen_strength, usm_radius, usm_amount, usm_threshold, deband_method,
            deband_strength, f3kdb_range, f3kdb_y, f3kdb_cbcr, grain_strength, denoiser_2, denoise_strength_2,
            deblock_mode_2, deblock_thresh_2, dering_strength_2, sharpen_method_2, sharpen_strength_2, usm_radius_2,
            usm_amount_2, usm_threshold_2, deband_method_2, deband_strength_2, f3kdb_range_2, f3kdb_y_2, f3kdb_cbcr_2,
            grain_strength_2, mi_mode, eq_contrast, eq_brightness, eq_saturation, outdir, threads;
        flags: dering_active, dering_active_2, use_denoise_2, use_deblock_2, use_dering_2, use_sharpen_2,
            use_deband_2, use_grain_2, use10, preview, no_deblock, no_denoise, no_decimate, no_interpolate,
            no_sharpen, no_deband, no_eq, no_grain, pci_safe_mode
    );
    Ok(())
}

fn main() -> ExitCode {
    let mut options = Options::default();
    let mut dry_run = false;
    let mut input = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "--write-header" => {
                let Some(path) = args.next() else {
                    eprintln!("--write-header needs a path");
                    return ExitCode::from(2);
                };
                return match up60p::header::write(std::path::Path::new(&path)) {
                    Ok(()) => ExitCode::SUCCESS,
                    Err(e) => {
                        eprintln!("{path}: {e}");
                        ExitCode::from(1)
                    }
                };
            }
            "--set" => {
                let Some(kv) = args.next() else {
                    eprintln!("--set needs key=value");
                    return ExitCode::from(2);
                };
                let Some((k, v)) = kv.split_once('=') else {
                    eprintln!("--set needs key=value, got {kv}");
                    return ExitCode::from(2);
                };
                if let Err(e) = apply(&mut options, k, v) {
                    eprintln!("{e}");
                    return ExitCode::from(2);
                }
            }
            "-h" | "--help" => {
                eprintln!("usage: up60p [--set key=value ...] [--dry-run] <input file or folder>");
                return ExitCode::SUCCESS;
            }
            _ => input = Some(arg),
        }
    }
    let Some(input) = input else {
        eprintln!("usage: up60p [--set key=value ...] [--dry-run] <input file or folder>");
        return ExitCode::from(2);
    };
    if let Some(v) = up60p::engine::version() {
        eprintln!("MpVFX media engine {v}");
    }
    configure_threads(&options);
    let cancel = AtomicBool::new(false);
    let log = |m: &str| eprint!("{m}");
    let job = Job { options: &options, log: &log, cancel: &cancel, dry_run };
    match job.run(std::path::Path::new(&input)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(JobError::Cancelled) => ExitCode::from(5),
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(1)
        }
    }
}
