//! `up60p_options`, the options struct the Swift app fills, and its defaults.

use std::ffi::{c_char, c_int};

/// `UP60P_PATH_MAX` in the generated `up60p.h`.
pub const PATH_MAX: usize = 1024;

/// Declares `Options` and, from the same list, `FIELDS`, which `header.rs` turns into the C declaration of
/// `up60p_options` that Swift imports. One list, so the two layouts cannot drift apart.
macro_rules! options {
    ($($field:ident : $kind:tt,)*) => {
        /// The app's processing options (`up60p_options` in the generated `up60p.h`): text fields are NUL-terminated
        /// byte arrays, switches are `int`s.
        #[repr(C)]
        #[derive(Clone)]
        pub struct Options {
            $(pub $field: options!(@type $kind),)*
        }

        /// Every field in declaration order: name and text capacity (`None` for an `int` switch).
        pub const FIELDS: &[(&str, Option<usize>)] = &[$((stringify!($field), options!(@size $kind)),)*];
    };
    (@type flag) => { c_int };
    (@type [$n:expr]) => { [c_char; $n] };
    (@size flag) => { None };
    (@size [$n:expr]) => { Some($n) };
}

options! {
    // Core
    codec: [8],
    crf: [16],
    preset: [32],
    fps: [16],
    scale_factor: [16],
    // Scaler / AI
    scaler: [16],
    ai_backend: [16],
    ai_model: [PATH_MAX],
    ai_model_type: [16],
    dnn_backend: [32],
    // Filters, first set
    denoiser: [16],
    denoise_strength: [16],
    deblock_mode: [16],
    deblock_thresh: [64],
    dering_active: flag,
    dering_strength: [16],
    sharpen_method: [16],
    sharpen_strength: [32],
    usm_radius: [16],
    usm_amount: [16],
    usm_threshold: [16],
    deband_method: [16],
    deband_strength: [32],
    f3kdb_range: [16],
    f3kdb_y: [16],
    f3kdb_cbcr: [16],
    grain_strength: [16],
    // Filters, second set
    denoiser_2: [16],
    denoise_strength_2: [16],
    deblock_mode_2: [16],
    deblock_thresh_2: [64],
    dering_active_2: flag,
    dering_strength_2: [16],
    sharpen_method_2: [16],
    sharpen_strength_2: [32],
    usm_radius_2: [16],
    usm_amount_2: [16],
    usm_threshold_2: [16],
    deband_method_2: [16],
    deband_strength_2: [32],
    f3kdb_range_2: [16],
    f3kdb_y_2: [16],
    f3kdb_cbcr_2: [16],
    grain_strength_2: [16],
    use_denoise_2: flag,
    use_deblock_2: flag,
    use_dering_2: flag,
    use_sharpen_2: flag,
    use_deband_2: flag,
    use_grain_2: flag,
    // Interpolation / EQ
    mi_mode: [16],
    eq_contrast: [16],
    eq_brightness: [16],
    eq_saturation: [16],
    // Encoder extra
    x265_params: [256],
    // I/O
    outdir: [PATH_MAX],
    audio_bitrate: [32],
    threads: [16],
    movflags: [32],
    use10: flag,
    preview: flag,
    // Toggles
    no_deblock: flag,
    no_denoise: flag,
    no_decimate: flag,
    no_interpolate: flag,
    no_sharpen: flag,
    no_deband: flag,
    no_eq: flag,
    no_grain: flag,
    pci_safe_mode: flag,
    // Hardware (accepted for compatibility; the backend runs on the CPU)
    hwaccel: [16],
    encoder: [16],
}

/// Fields the app sends that the backend deliberately does not use, with the reason. Every other field changes the
/// output; `tests/settings_contract.rs` checks both halves of that statement against the source.
pub const NOT_USED: &[(&str, &str)] = &[
    ("preset", "x264 speed preset; the engine's H.264 encoder has quality tiers, chosen from crf"),
    ("ai_backend", "legacy FFmpeg DNN scaler; CoreML upscaling runs in Swift"),
    ("ai_model", "legacy FFmpeg DNN scaler; CoreML upscaling runs in Swift"),
    ("ai_model_type", "legacy FFmpeg DNN scaler; CoreML upscaling runs in Swift"),
    ("dnn_backend", "legacy FFmpeg DNN scaler; CoreML upscaling runs in Swift"),
    ("x265_params", "HEVC encoder settings; the engine encodes H.264"),
    ("audio_bitrate", "AAC bitrate; audio is written as lossless FLAC"),
    ("movflags", "MP4 layout flags; the engine's muxer decides the layout"),
    ("hwaccel", "hardware decoding; the engine decodes in software"),
    ("encoder", "hardware encoder choice; the engine's H.264 encoder is software"),
];

/// Reads a NUL-terminated field (the whole array when no NUL is present).
pub fn text(field: &[c_char]) -> String {
    let bytes: Vec<u8> = field.iter().take_while(|&&c| c != 0).map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).trim().to_owned()
}

/// Writes `value` into a field, truncated to leave room for the NUL terminator.
pub fn set(field: &mut [c_char], value: &str) {
    field.iter_mut().for_each(|c| *c = 0);
    let room = field.len().saturating_sub(1);
    for (dst, &b) in field.iter_mut().zip(value.as_bytes().iter().take(room)) {
        *dst = b as c_char;
    }
}

impl Default for Options {
    /// The app's factory settings (formerly `set_defaults` in the C engine).
    fn default() -> Options {
        // SAFETY: every field is an integer or an array of integers, for which all-zero bytes are valid.
        let mut o: Options = unsafe { std::mem::zeroed() };
        set(&mut o.codec, "h264");
        set(&mut o.crf, "20");
        set(&mut o.preset, "faster");
        set(&mut o.fps, "60");
        set(&mut o.scale_factor, "2");
        set(&mut o.scaler, "lanczos");
        set(&mut o.ai_backend, "sr");
        set(&mut o.ai_model_type, "espcn");
        set(&mut o.dnn_backend, "tensorflow");
        for (denoiser, strength, deblock, dering, sharpen, sharpen_strength, radius, amount, threshold) in [
            (
                &mut o.denoiser,
                &mut o.denoise_strength,
                &mut o.deblock_mode,
                &mut o.dering_strength,
                &mut o.sharpen_method,
                &mut o.sharpen_strength,
                &mut o.usm_radius,
                &mut o.usm_amount,
                &mut o.usm_threshold,
            ),
            (
                &mut o.denoiser_2,
                &mut o.denoise_strength_2,
                &mut o.deblock_mode_2,
                &mut o.dering_strength_2,
                &mut o.sharpen_method_2,
                &mut o.sharpen_strength_2,
                &mut o.usm_radius_2,
                &mut o.usm_amount_2,
                &mut o.usm_threshold_2,
            ),
        ] {
            set(denoiser, "bm3d");
            set(strength, "2.5");
            set(deblock, "strong");
            set(dering, "0.5");
            set(sharpen, "cas");
            set(sharpen_strength, "0.25");
            set(radius, "5");
            set(amount, "1.0");
            set(threshold, "0.03");
        }
        for (method, strength, range, y, cbcr, grain) in [
            (
                &mut o.deband_method,
                &mut o.deband_strength,
                &mut o.f3kdb_range,
                &mut o.f3kdb_y,
                &mut o.f3kdb_cbcr,
                &mut o.grain_strength,
            ),
            (
                &mut o.deband_method_2,
                &mut o.deband_strength_2,
                &mut o.f3kdb_range_2,
                &mut o.f3kdb_y_2,
                &mut o.f3kdb_cbcr_2,
                &mut o.grain_strength_2,
            ),
        ] {
            set(method, "deband");
            set(strength, "0.015");
            set(range, "15");
            set(y, "64");
            set(cbcr, "64");
            set(grain, "1.0");
        }
        set(&mut o.mi_mode, "mci");
        set(&mut o.eq_contrast, "1.03");
        set(&mut o.eq_brightness, "0.005");
        set(&mut o.eq_saturation, "1.06");
        set(&mut o.audio_bitrate, "192k");
        set(&mut o.movflags, "+faststart");
        set(&mut o.hwaccel, "none");
        set(&mut o.encoder, "auto");
        o
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_round_trip_and_truncation() {
        let mut f = [0 as c_char; 8];
        set(&mut f, "lanczos");
        assert_eq!(text(&f), "lanczos");
        set(&mut f, "much-too-long");
        assert_eq!(text(&f), "much-to");
        assert_eq!(f[7], 0);
    }

    #[test]
    fn defaults_match_the_app() {
        let o = Options::default();
        assert_eq!(text(&o.denoiser), "bm3d");
        assert_eq!(text(&o.fps), "60");
        assert_eq!(text(&o.mi_mode), "mci");
        assert_eq!(text(&o.deband_strength_2), "0.015");
        assert_eq!(o.use_denoise_2, 0);
    }
}
