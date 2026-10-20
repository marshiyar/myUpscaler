//! `up60p_options` (the C struct the Swift app fills, laid out exactly as in `up60p.h`) and its defaults.

use std::ffi::{c_char, c_int};

/// `UP60P_PATH_MAX` in `up60p.h`.
pub const PATH_MAX: usize = 1024;

/// Mirrors `up60p_options` in `myUpscaler/upscaler/up60p.h` field for field.
#[repr(C)]
#[derive(Clone)]
pub struct Options {
    // Core
    pub codec: [c_char; 8],
    pub crf: [c_char; 16],
    pub preset: [c_char; 32],
    pub fps: [c_char; 16],
    pub scale_factor: [c_char; 16],
    // Scaler / AI
    pub scaler: [c_char; 16],
    pub ai_backend: [c_char; 16],
    pub ai_model: [c_char; PATH_MAX],
    pub ai_model_type: [c_char; 16],
    pub dnn_backend: [c_char; 32],
    // Filters, first set
    pub denoiser: [c_char; 16],
    pub denoise_strength: [c_char; 16],
    pub deblock_mode: [c_char; 16],
    pub deblock_thresh: [c_char; 64],
    pub dering_active: c_int,
    pub dering_strength: [c_char; 16],
    pub sharpen_method: [c_char; 16],
    pub sharpen_strength: [c_char; 32],
    pub usm_radius: [c_char; 16],
    pub usm_amount: [c_char; 16],
    pub usm_threshold: [c_char; 16],
    pub deband_method: [c_char; 16],
    pub deband_strength: [c_char; 32],
    pub f3kdb_range: [c_char; 16],
    pub f3kdb_y: [c_char; 16],
    pub f3kdb_cbcr: [c_char; 16],
    pub grain_strength: [c_char; 16],
    // Filters, second set
    pub denoiser_2: [c_char; 16],
    pub denoise_strength_2: [c_char; 16],
    pub deblock_mode_2: [c_char; 16],
    pub deblock_thresh_2: [c_char; 64],
    pub dering_active_2: c_int,
    pub dering_strength_2: [c_char; 16],
    pub sharpen_method_2: [c_char; 16],
    pub sharpen_strength_2: [c_char; 32],
    pub usm_radius_2: [c_char; 16],
    pub usm_amount_2: [c_char; 16],
    pub usm_threshold_2: [c_char; 16],
    pub deband_method_2: [c_char; 16],
    pub deband_strength_2: [c_char; 32],
    pub f3kdb_range_2: [c_char; 16],
    pub f3kdb_y_2: [c_char; 16],
    pub f3kdb_cbcr_2: [c_char; 16],
    pub grain_strength_2: [c_char; 16],
    pub use_denoise_2: c_int,
    pub use_deblock_2: c_int,
    pub use_dering_2: c_int,
    pub use_sharpen_2: c_int,
    pub use_deband_2: c_int,
    pub use_grain_2: c_int,
    // Interpolation / EQ
    pub mi_mode: [c_char; 16],
    pub eq_contrast: [c_char; 16],
    pub eq_brightness: [c_char; 16],
    pub eq_saturation: [c_char; 16],
    // Encoder extra
    pub x265_params: [c_char; 256],
    // I/O
    pub outdir: [c_char; PATH_MAX],
    pub audio_bitrate: [c_char; 32],
    pub threads: [c_char; 16],
    pub movflags: [c_char; 32],
    pub use10: c_int,
    pub preview: c_int,
    // Toggles
    pub no_deblock: c_int,
    pub no_denoise: c_int,
    pub no_decimate: c_int,
    pub no_interpolate: c_int,
    pub no_sharpen: c_int,
    pub no_deband: c_int,
    pub no_eq: c_int,
    pub no_grain: c_int,
    pub pci_safe_mode: c_int,
    // Hardware (accepted for compatibility; the backend runs on the CPU)
    pub hwaccel: [c_char; 16],
    pub encoder: [c_char; 16],
}

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
