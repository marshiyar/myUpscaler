//! Command-line front end to the backend, for testing and batch use outside the app:
//!
//! ```text
//! up60p [--set key=value ...] [--dry-run] <input file or folder>
//! up60p --write-header <path>     # the C header Swift imports (see header.rs)
//! ```
//!
//! Keys are the `up60p_options` field names (`scale_factor=4`, `denoiser=hqdn3d`, `no_grain=1`, `outdir=/tmp`); see
//! `Options::set_field`.

use std::process::ExitCode;
use std::sync::atomic::AtomicBool;

use up60p::job::{configure_threads, Job, JobError};
use up60p::options::Options;

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
                if let Err(e) = options.set_field(k, v) {
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
