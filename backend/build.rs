//! Finds the MpVFX media engine library for links made by cargo itself (the CLI and the tests).
//!
//! The app links `libup60p.a` and `libmpvfx_ffi.dylib` in Xcode, so the static library needs nothing here. The
//! engine is looked up in `$MPVFX_MEDIA_DIR/lib`, then in `../third_party/mpvfx-media/lib` (where
//! `scripts/prepare-media-engine.sh` puts it). Without it the crate builds with `cfg(no_engine)`: the filters and their
//! tests work, and every engine call reports that the engine is unavailable.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rustc-check-cfg=cfg(no_engine)");
    println!("cargo:rerun-if-env-changed=MPVFX_MEDIA_DIR");

    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let candidates = [
        env::var("MPVFX_MEDIA_DIR").ok().map(|d| PathBuf::from(d).join("lib")),
        Some(manifest.join("../third_party/mpvfx-media/lib")),
    ];
    let names = ["libmpvfx_ffi.dylib", "libmpvfx_ffi.so", "mpvfx_ffi.dll.lib"];
    for dir in candidates.into_iter().flatten() {
        println!("cargo:rerun-if-changed={}", dir.display());
        if names.iter().any(|n| dir.join(n).is_file()) {
            let dir = dir.canonicalize().unwrap_or(dir);
            if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
                link_windows(&dir);
                return;
            }
            println!("cargo:rustc-link-search=native={}", dir.display());
            println!("cargo:rustc-link-lib=dylib=mpvfx_ffi");
            // Lets `cargo run` and `cargo test` find the library without installing it. The static library takes no
            // link arguments, so the app's own run path is unaffected.
            println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
            return;
        }
    }
    println!("cargo:warning=MpVFX media engine not found; building without it (run scripts/prepare-media-engine.sh)");
    println!("cargo:rustc-cfg=no_engine");
}

/// Windows has no run path: a program finds `mpvfx_ffi.dll` beside itself or on `PATH`. Cargo puts link search
/// directories inside the target folder on `PATH` for `cargo run` and `cargo test`, so the DLL and its import library
/// (`mpvfx_ffi.dll.lib`, named as is) are copied into this build's output folder and linked from there. The desktop
/// app's build script copies the DLL beside the executable.
fn link_windows(dir: &std::path::Path) {
    let out = PathBuf::from(env::var("OUT_DIR").expect("cargo sets OUT_DIR"));
    for name in ["mpvfx_ffi.dll", "mpvfx_ffi.dll.lib"] {
        std::fs::copy(dir.join(name), out.join(name)).unwrap_or_else(|e| panic!("copying {name}: {e}"));
    }
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=dylib:+verbatim=mpvfx_ffi.dll.lib");
}
