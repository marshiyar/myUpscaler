//! Compiles the Slint interface (`ui/`), and gives the app's binaries a run path to the MpVFX media engine library so
//! `cargo run` and `cargo test` find it (the backend's own run path applies only to the backend's binaries).

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=MPVFX_MEDIA_DIR");
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let candidates = [
        env::var("MPVFX_MEDIA_DIR").ok().map(|d| PathBuf::from(d).join("lib")),
        Some(manifest.join("../third_party/mpvfx-media/lib")),
    ];
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        for dir in candidates.into_iter().flatten() {
            println!("cargo:rerun-if-changed={}", dir.display());
            if ["libmpvfx_ffi.dylib", "libmpvfx_ffi.so"].iter().any(|n| dir.join(n).is_file()) {
                let dir = dir.canonicalize().unwrap_or(dir);
                println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
                break;
            }
        }
    }

    // The Cupertino base style on every platform; the app's own controls draw the rest from ui/theme.slint.
    let config = slint_build::CompilerConfiguration::new().with_style("cupertino".into());
    slint_build::compile_with_config("ui/app.slint", config).expect("the Slint interface failed to compile");
}
