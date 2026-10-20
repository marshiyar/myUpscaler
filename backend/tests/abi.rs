//! The app fills `up60p_options` from Swift through `myUpscaler/upscaler/up60p.h`; the backend reads it as
//! `options::Options`. This compiles the header with the system C compiler and compares the size and the offset of
//! every field with the Rust struct, so a field added to one side only fails the build's tests.

use std::mem::{offset_of, size_of};
use std::path::PathBuf;
use std::process::Command;

use up60p::options::Options;

macro_rules! offsets {
    ($($f:ident),* $(,)?) => {
        vec![$((stringify!($f), offset_of!(Options, $f))),*]
    };
}

#[test]
fn header_layout_matches_rust() {
    let fields = offsets!(
        codec,
        crf,
        preset,
        fps,
        scale_factor,
        scaler,
        ai_backend,
        ai_model,
        ai_model_type,
        dnn_backend,
        denoiser,
        denoise_strength,
        deblock_mode,
        deblock_thresh,
        dering_active,
        dering_strength,
        sharpen_method,
        sharpen_strength,
        usm_radius,
        usm_amount,
        usm_threshold,
        deband_method,
        deband_strength,
        f3kdb_range,
        f3kdb_y,
        f3kdb_cbcr,
        grain_strength,
        denoiser_2,
        denoise_strength_2,
        deblock_mode_2,
        deblock_thresh_2,
        dering_active_2,
        dering_strength_2,
        sharpen_method_2,
        sharpen_strength_2,
        usm_radius_2,
        usm_amount_2,
        usm_threshold_2,
        deband_method_2,
        deband_strength_2,
        f3kdb_range_2,
        f3kdb_y_2,
        f3kdb_cbcr_2,
        grain_strength_2,
        use_denoise_2,
        use_deblock_2,
        use_dering_2,
        use_sharpen_2,
        use_deband_2,
        use_grain_2,
        mi_mode,
        eq_contrast,
        eq_brightness,
        eq_saturation,
        x265_params,
        outdir,
        audio_bitrate,
        threads,
        movflags,
        use10,
        preview,
        no_deblock,
        no_denoise,
        no_decimate,
        no_interpolate,
        no_sharpen,
        no_deband,
        no_eq,
        no_grain,
        pci_safe_mode,
        hwaccel,
        encoder,
    );

    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
    let header = root.join("myUpscaler/upscaler/up60p.h");
    let dir = std::env::temp_dir().join(format!("up60p-abi-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut c = format!(
        "#include <stdio.h>\n#include <stddef.h>\n#include \"{}\"\nint main(void) {{\n  printf(\"size %zu\\n\", sizeof(up60p_options));\n",
        header.display()
    );
    for (name, _) in &fields {
        c += &format!("  printf(\"{name} %zu\\n\", offsetof(up60p_options, {name}));\n");
    }
    c += "  return 0;\n}\n";
    let src = dir.join("abi.c");
    let exe = dir.join("abi");
    std::fs::write(&src, c).unwrap();
    let compiler = std::env::var("CC").unwrap_or_else(|_| "cc".into());
    let built = match Command::new(&compiler).arg(&src).arg("-o").arg(&exe).status() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("skipped: no C compiler ({compiler}: {e})");
            return;
        }
    };
    assert!(built.success(), "the header does not compile");
    let output = Command::new(&exe).output().unwrap();
    let text = String::from_utf8(output.stdout).unwrap();
    let c_values: Vec<(String, usize)> = text
        .lines()
        .map(|l| {
            let (k, v) = l.split_once(' ').unwrap();
            (k.to_owned(), v.parse().unwrap())
        })
        .collect();
    assert_eq!(c_values[0], ("size".to_owned(), size_of::<Options>()), "sizeof(up60p_options)");
    for ((name, rust), (c_name, c)) in fields.iter().zip(&c_values[1..]) {
        assert_eq!((name.to_string(), *rust), (c_name.clone(), *c), "offset of {name}");
    }
    assert_eq!(up60p::up60p_options_size(), size_of::<Options>());
}
