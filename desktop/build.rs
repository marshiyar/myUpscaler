//! Compiles the Slint interface (`ui/`), and makes the MpVFX media engine library findable by the app: run paths on
//! macOS and Linux (to the prepared engine, and beside the program for a packaged app; the backend's own apply only to
//! the backend's binaries), the DLL beside the program on Windows.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=MPVFX_MEDIA_DIR");
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let candidates = [
        env::var("MPVFX_MEDIA_DIR").ok().map(|d| PathBuf::from(d).join("lib")),
        Some(manifest.join("../third_party/mpvfx-media/lib")),
    ];
    let windows = env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows");
    for dir in candidates.into_iter().flatten() {
        println!("cargo:rerun-if-changed={}", dir.display());
        if windows && dir.join("mpvfx_ffi.dll").is_file() {
            // Windows looks for the DLL beside the program: copy it into the folder that receives myupscaler.exe
            // (target/<profile>), so the built app runs from there and ships as the two files.
            let out = PathBuf::from(env::var("OUT_DIR").unwrap_or_default());
            if let Some(bin_dir) = out.ancestors().nth(3) {
                std::fs::copy(dir.join("mpvfx_ffi.dll"), bin_dir.join("mpvfx_ffi.dll"))
                    .unwrap_or_else(|e| panic!("copying mpvfx_ffi.dll: {e}"));
            }
            break;
        }
        if !windows && ["libmpvfx_ffi.dylib", "libmpvfx_ffi.so"].iter().any(|n| dir.join(n).is_file()) {
            let dir = dir.canonicalize().unwrap_or(dir);
            println!("cargo:rustc-link-arg=-Wl,-rpath,{}", dir.display());
            // A packaged app keeps the library beside the program (the release archives).
            let beside =
                if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") { "@executable_path" } else { "$ORIGIN" };
            println!("cargo:rustc-link-arg=-Wl,-rpath,{beside}");
            break;
        }
    }

    // The Cupertino base style on every platform; the app's own controls draw the rest from ui/theme.slint.
    let config = slint_build::CompilerConfiguration::new().with_style("cupertino".into());
    slint_build::compile_with_config("ui/app.slint", config).expect("the Slint interface failed to compile");
}
