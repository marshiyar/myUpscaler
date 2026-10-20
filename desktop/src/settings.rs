//! Moves settings between the interface (the `Settings` global) and the backend's `Options`. The interface starts
//! from `Options::default()`, so the factory settings are defined once, in `backend/src/options.rs`.

use up60p::options::{set, text, Options};

use crate::Settings;

/// Backend names for the interface's choice indexes.
pub const DENOISERS: [&str; 4] = ["bm3d", "hqdn3d", "nlmeans", "atadenoise"];
pub const DEBLOCK_MODES: [&str; 2] = ["weak", "strong"];
pub const DEBAND_METHODS: [&str; 4] = ["deband", "gradfun", "f3kdb", "neo_f3kdb"];

/// Slider range and default for a denoiser's strength, as in the macOS app.
pub fn denoise_range(denoiser: &str) -> (f32, f32, f32) {
    match denoiser {
        "hqdn3d" => (1.0, 10.0, 4.0),
        "nlmeans" => (1.0, 30.0, 1.0),
        "atadenoise" => (1.0, 20.0, 9.0),
        _ => (0.0, 20.0, 2.5),
    }
}

fn index_of(names: &[&str], name: &str) -> Option<usize> {
    names.iter().position(|n| *n == name)
}

fn number(s: &str, fallback: f32) -> f32 {
    s.trim().parse::<f32>().ok().filter(|v| v.is_finite()).unwrap_or(fallback)
}

fn flag(v: i32) -> bool {
    v != 0
}

/// Shows `o` in the interface.
pub fn load(s: &Settings, o: &Options) {
    s.set_crf(number(&text(&o.crf), 20.0));
    s.set_scale(text(&o.scale_factor).into());
    s.set_fps(text(&o.fps).into());
    s.set_interpolation(match (flag(o.no_interpolate), text(&o.mi_mode).as_str()) {
        (true, _) => 0,
        (false, "blend") => 2,
        _ => 1,
    });

    let denoiser = text(&o.denoiser);
    s.set_denoise(!flag(o.no_denoise));
    s.set_denoiser(index_of(&DENOISERS, &denoiser).unwrap_or(0) as i32);
    s.set_denoise_strength(number(&text(&o.denoise_strength), denoise_range(&denoiser).2));
    s.set_dering(flag(o.dering_active));
    s.set_dering_strength(number(&text(&o.dering_strength), 0.5));
    s.set_sharpen(!flag(o.no_sharpen));
    s.set_sharpen_method(if text(&o.sharpen_method) == "unsharp" { 1 } else { 0 });
    s.set_cas_strength(number(&text(&o.sharpen_strength), 0.25));
    s.set_usm_radius(number(&text(&o.usm_radius), 5.0));
    s.set_usm_amount(number(&text(&o.usm_amount), 1.0));
    s.set_usm_threshold(number(&text(&o.usm_threshold), 0.03));
    s.set_eq(!flag(o.no_eq));
    s.set_contrast(number(&text(&o.eq_contrast), 1.0));
    s.set_brightness(number(&text(&o.eq_brightness), 0.0));
    s.set_saturation(number(&text(&o.eq_saturation), 1.0));

    let denoiser2 = text(&o.denoiser_2);
    s.set_denoise2(flag(o.use_denoise_2));
    s.set_denoiser2(index_of(&DENOISERS, &denoiser2).unwrap_or(0) as i32);
    s.set_denoise2_strength(number(&text(&o.denoise_strength_2), denoise_range(&denoiser2).2));
    s.set_dering2(flag(o.use_dering_2));
    s.set_dering2_strength(number(&text(&o.dering_strength_2), 0.5));
    s.set_sharpen2(flag(o.use_sharpen_2));
    s.set_cas2_strength(number(&text(&o.sharpen_strength_2), 0.25));
    s.set_deblock2(flag(o.use_deblock_2));
    s.set_deband2(flag(o.use_deband_2));
    s.set_deband2_strength(text(&o.deband_strength_2).into());
    s.set_grain2(flag(o.use_grain_2));
    s.set_grain2_strength(text(&o.grain_strength_2).into());

    s.set_deblock(!flag(o.no_deblock));
    s.set_deblock_mode(index_of(&DEBLOCK_MODES, &text(&o.deblock_mode)).unwrap_or(1) as i32);
    s.set_deband(!flag(o.no_deband));
    s.set_deband_method(index_of(&DEBAND_METHODS, &text(&o.deband_method)).unwrap_or(0) as i32);
    s.set_deband_strength(text(&o.deband_strength).into());
    s.set_f3kdb_range(text(&o.f3kdb_range).into());
    s.set_f3kdb_y(text(&o.f3kdb_y).into());
    s.set_f3kdb_cbcr(text(&o.f3kdb_cbcr).into());
    s.set_grain(if flag(o.no_grain) { "0".into() } else { text(&o.grain_strength).into() });
    s.set_decimate(!flag(o.no_decimate));
    s.set_threads(text(&o.threads).into());
    s.set_custom_output(!text(&o.outdir).is_empty());
    s.set_output_folder(text(&o.outdir).into());
    update_ranges(s);
}

/// Keeps the denoise sliders' ranges in step with the chosen denoisers, clamping the strengths into them.
pub fn update_ranges(s: &Settings) {
    let first = DENOISERS[s.get_denoiser().clamp(0, 3) as usize];
    let (lo, hi, default) = denoise_range(first);
    s.set_denoise_min(lo);
    s.set_denoise_max(hi);
    s.set_denoise_default(default);
    s.set_denoise_strength(s.get_denoise_strength().clamp(lo, hi));

    let second = DENOISERS[s.get_denoiser2().clamp(0, 3) as usize];
    let (lo, hi, default) = denoise_range(second);
    s.set_denoise2_min(lo);
    s.set_denoise2_max(hi);
    s.set_denoise2_default(default);
    s.set_denoise2_strength(s.get_denoise2_strength().clamp(lo, hi));
}

/// The backend options for what the interface shows. Fields the interface does not expose keep their defaults.
pub fn options(s: &Settings) -> Options {
    let mut o = Options::default();
    set(&mut o.crf, &format!("{}", s.get_crf().round() as i32));
    set(&mut o.scale_factor, &s.get_scale());
    set(&mut o.fps, &s.get_fps());
    let interpolation = s.get_interpolation();
    o.no_interpolate = (interpolation == 0) as i32;
    set(&mut o.mi_mode, if interpolation == 2 { "blend" } else { "mci" });

    o.no_denoise = !s.get_denoise() as i32;
    set(&mut o.denoiser, DENOISERS[s.get_denoiser().clamp(0, 3) as usize]);
    set(&mut o.denoise_strength, &format!("{:.2}", s.get_denoise_strength()));
    o.dering_active = s.get_dering() as i32;
    set(&mut o.dering_strength, &format!("{:.3}", s.get_dering_strength()));
    o.no_sharpen = !s.get_sharpen() as i32;
    set(&mut o.sharpen_method, if s.get_sharpen_method() == 1 { "unsharp" } else { "cas" });
    set(&mut o.sharpen_strength, &format!("{:.2}", s.get_cas_strength()));
    set(&mut o.usm_radius, &format!("{}", s.get_usm_radius().round() as i32));
    set(&mut o.usm_amount, &format!("{:.2}", s.get_usm_amount()));
    set(&mut o.usm_threshold, &format!("{:.3}", s.get_usm_threshold()));
    o.no_eq = !s.get_eq() as i32;
    set(&mut o.eq_contrast, &format!("{:.3}", s.get_contrast()));
    set(&mut o.eq_brightness, &format!("{:.3}", s.get_brightness()));
    set(&mut o.eq_saturation, &format!("{:.3}", s.get_saturation()));

    o.use_denoise_2 = s.get_denoise2() as i32;
    set(&mut o.denoiser_2, DENOISERS[s.get_denoiser2().clamp(0, 3) as usize]);
    set(&mut o.denoise_strength_2, &format!("{:.2}", s.get_denoise2_strength()));
    o.use_dering_2 = s.get_dering2() as i32;
    set(&mut o.dering_strength_2, &format!("{:.3}", s.get_dering2_strength()));
    o.use_sharpen_2 = s.get_sharpen2() as i32;
    set(&mut o.sharpen_method_2, "cas");
    set(&mut o.sharpen_strength_2, &format!("{:.2}", s.get_cas2_strength()));
    o.use_deblock_2 = s.get_deblock2() as i32;
    o.use_deband_2 = s.get_deband2() as i32;
    set(&mut o.deband_strength_2, &s.get_deband2_strength());
    o.use_grain_2 = s.get_grain2() as i32;
    set(&mut o.grain_strength_2, &s.get_grain2_strength());

    o.no_deblock = !s.get_deblock() as i32;
    set(&mut o.deblock_mode, DEBLOCK_MODES[s.get_deblock_mode().clamp(0, 1) as usize]);
    o.no_deband = !s.get_deband() as i32;
    set(&mut o.deband_method, DEBAND_METHODS[s.get_deband_method().clamp(0, 3) as usize]);
    set(&mut o.deband_strength, &s.get_deband_strength());
    set(&mut o.f3kdb_range, &s.get_f3kdb_range());
    set(&mut o.f3kdb_y, &s.get_f3kdb_y());
    set(&mut o.f3kdb_cbcr, &s.get_f3kdb_cbcr());
    set(&mut o.grain_strength, &s.get_grain());
    o.no_decimate = !s.get_decimate() as i32;
    set(&mut o.threads, &s.get_threads());
    set(&mut o.outdir, if s.get_custom_output() { s.get_output_folder() } else { Default::default() }.as_str());
    o
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AppWindow;
    use slint::ComponentHandle;

    fn window() -> AppWindow {
        i_slint_backend_testing::init_no_event_loop();
        AppWindow::new().unwrap()
    }

    #[test]
    fn factory_settings_round_trip() {
        let ui = window();
        let s = ui.global::<Settings>();
        let defaults = Options::default();
        load(&s, &defaults);
        let o = options(&s);
        for (name, a, b) in [
            ("crf", text(&o.crf), text(&defaults.crf)),
            ("fps", text(&o.fps), text(&defaults.fps)),
            ("scale", text(&o.scale_factor), text(&defaults.scale_factor)),
            ("denoiser", text(&o.denoiser), text(&defaults.denoiser)),
            ("deblock", text(&o.deblock_mode), text(&defaults.deblock_mode)),
            ("deband", text(&o.deband_method), text(&defaults.deband_method)),
            ("grain", text(&o.grain_strength), text(&defaults.grain_strength)),
            ("sharpen", text(&o.sharpen_method), text(&defaults.sharpen_method)),
        ] {
            assert_eq!(a, b, "{name}");
        }
        for (name, a, b) in [
            ("no_interpolate", o.no_interpolate, defaults.no_interpolate),
            ("no_denoise", o.no_denoise, defaults.no_denoise),
            ("no_deblock", o.no_deblock, defaults.no_deblock),
            ("no_sharpen", o.no_sharpen, defaults.no_sharpen),
            ("no_deband", o.no_deband, defaults.no_deband),
            ("no_decimate", o.no_decimate, defaults.no_decimate),
            ("dering_active", o.dering_active, defaults.dering_active),
            ("use_denoise_2", o.use_denoise_2, defaults.use_denoise_2),
        ] {
            assert_eq!(a, b, "{name}");
        }
        assert_eq!(number(&text(&o.denoise_strength), 0.0), 2.5);
        // The factory EQ is neutral, so the chain matches what the backend builds from its own defaults.
        let source = up60p::pipeline::Source::Image;
        assert_eq!(
            up60p::pipeline::build(&o, source).unwrap().chain.describe(),
            up60p::pipeline::build(&defaults, source).unwrap().chain.describe()
        );
    }

    #[test]
    fn choices_map_to_backend_names() {
        let ui = window();
        let s = ui.global::<Settings>();
        load(&s, &Options::default());
        s.set_denoise(false);
        s.set_interpolation(2);
        s.set_deblock_mode(0);
        s.set_deband_method(3);
        s.set_sharpen_method(1);
        s.set_custom_output(true);
        s.set_output_folder("/out".into());
        let o = options(&s);
        assert_eq!(o.no_denoise, 1);
        assert_eq!((o.no_interpolate, text(&o.mi_mode).as_str()), (0, "blend"));
        assert_eq!(text(&o.deblock_mode), "weak");
        assert_eq!(text(&o.deband_method), "neo_f3kdb");
        assert_eq!(text(&o.sharpen_method), "unsharp");
        assert_eq!(text(&o.outdir), "/out");
        s.set_custom_output(false);
        assert_eq!(text(&options(&s).outdir), "");
    }

    #[test]
    fn denoise_ranges_follow_the_denoiser() {
        let ui = window();
        let s = ui.global::<Settings>();
        load(&s, &Options::default());
        s.set_denoiser(2); // NLMeans: 1..30
        s.set_denoise_strength(45.0);
        update_ranges(&s);
        assert_eq!((s.get_denoise_min(), s.get_denoise_max(), s.get_denoise_default()), (1.0, 30.0, 1.0));
        assert_eq!(s.get_denoise_strength(), 30.0);
        s.set_denoiser2(1); // hqdn3d: 1..10
        update_ranges(&s);
        assert_eq!(s.get_denoise2_max(), 10.0);
    }
}
