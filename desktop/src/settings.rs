//! Moves settings between the interface (the `Settings` global) and the backend's `Options`. The interface starts
//! from `Options::default()`, so the factory settings are defined once, in `backend/src/options.rs`. The mappings
//! follow the macOS app's controls (`myUpscaler/State`): choice menus with an "Off" entry, deringing that is off at
//! zero, deblock thresholds as `alpha=…:beta=…`, and x265 parameters as `aq-mode=…,psy-rd=…,deblock=a,b`.

use up60p::options::{set, text, Options};

use crate::Settings;

/// Backend names for the interface's choice indexes, in the macOS app's menu order (after "Off").
pub const DENOISERS: [&str; 4] = ["bm3d", "nlmeans", "hqdn3d", "atadenoise"];
pub const DEBLOCK_MODES: [&str; 2] = ["weak", "strong"];
pub const PRESETS: [&str; 3] = ["veryfast", "faster", "medium"];
const DEBLOCK_KEYS: [&str; 4] = ["alpha", "beta", "gamma", "delta"];

/// Hardware choices this platform offers, as in the macOS app on a Mac.
pub fn hwaccels() -> &'static [&'static str] {
    if cfg!(target_os = "macos") {
        &["none", "videotoolbox"]
    } else {
        &["none"]
    }
}

pub fn encoders() -> &'static [&'static str] {
    if cfg!(target_os = "macos") {
        &["auto", "cpu", "videotoolbox"]
    } else {
        &["auto", "cpu"]
    }
}

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

/// A denoise menu index (0 off) for a switch and a denoiser name.
fn denoise_choice(on: bool, denoiser: &str) -> i32 {
    if on {
        index_of(&DENOISERS, denoiser).map_or(1, |i| i as i32 + 1)
    } else {
        0
    }
}

/// A deband menu index (0 off, 1 deband or f3kdb, 2 gradfun, 3 Neo F3kdb) and whether it is f3kdb.
fn deband_choice(on: bool, method: &str) -> (i32, bool) {
    match (on, method) {
        (false, _) => (0, method == "f3kdb"),
        (true, "gradfun") => (2, false),
        (true, "neo_f3kdb") => (3, false),
        (true, m) => (1, m == "f3kdb"),
    }
}

fn deband_method(choice: i32, f3kdb: bool) -> &'static str {
    match choice {
        2 => "gradfun",
        3 => "neo_f3kdb",
        _ if f3kdb => "f3kdb",
        _ => "deband",
    }
}

/// A `key=value` entry of a `:`-separated list (deblock thresholds).
fn threshold(list: &str, key: &str) -> String {
    list.split(':')
        .filter_map(|e| e.split_once('='))
        .filter(|(k, _)| k.trim() == key)
        .map(|(_, v)| v.trim().to_owned())
        .next_back()
        .unwrap_or_default()
}

/// Thresholds are valid when each is empty or a number from 0 to 1.
fn thresholds_valid(values: &[String]) -> bool {
    values.iter().all(|v| v.is_empty() || v.parse::<f64>().is_ok_and(|n| (0.0..=1.0).contains(&n)))
}

/// The x265 parameters `aq-mode=…,psy-rd=…,deblock=a,b` as (aq-mode, psy-rd, deblock a, deblock b).
fn x265_fields(params: &str) -> (String, String, String, String) {
    let mut entries: Vec<(String, String)> = Vec::new();
    for token in params.split(',') {
        match token.split_once('=') {
            Some((k, v)) => entries.push((k.trim().to_owned(), v.trim().to_owned())),
            // A value with a comma (deblock=a,b) continues the previous entry.
            None => {
                if let Some(last) = entries.last_mut() {
                    last.1 = format!("{},{}", last.1, token.trim());
                }
            }
        }
    }
    let get = |key: &str| entries.iter().rev().find(|(k, _)| k == key).map(|e| e.1.clone()).unwrap_or_default();
    let deblock = get("deblock");
    let (a, b) = deblock.split_once(',').map_or((deblock.clone(), String::new()), |(a, b)| (a.into(), b.into()));
    (get("aq-mode"), get("psy-rd"), a, b)
}

fn x265_params(aq: &str, psy: &str, deblock1: &str, deblock2: &str) -> String {
    let mut params = Vec::new();
    if !aq.is_empty() {
        params.push(format!("aq-mode={aq}"));
    }
    if !psy.is_empty() {
        params.push(format!("psy-rd={psy}"));
    }
    if !deblock1.is_empty() || !deblock2.is_empty() {
        params.push(format!("deblock={deblock1},{deblock2}"));
    }
    params.join(",")
}

/// Shows `o` in the interface.
pub fn load(s: &Settings, o: &Options) {
    s.set_scaler(0);
    s.set_crf(number(&text(&o.crf), 20.0));
    s.set_scale(text(&o.scale_factor).into());
    s.set_fps(text(&o.fps).into());
    s.set_interpolation(match (flag(o.no_interpolate), text(&o.mi_mode).as_str()) {
        (true, _) => 0,
        (false, "blend") => 2,
        _ => 1,
    });

    let denoiser = text(&o.denoiser);
    s.set_denoise(denoise_choice(!flag(o.no_denoise), &denoiser));
    s.set_denoise_strength(number(&text(&o.denoise_strength), denoise_range(&denoiser).2));
    s.set_dering(if flag(o.dering_active) { number(&text(&o.dering_strength), 0.5) } else { 0.0 });
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

    s.set_denoise2(denoise_choice(flag(o.use_denoise_2), &text(&o.denoiser_2)));
    s.set_denoise2_strength(text(&o.denoise_strength_2).into());
    s.set_dering2(if flag(o.use_dering_2) { number(&text(&o.dering_strength_2), 0.5) } else { 0.0 });
    s.set_sharpen2(flag(o.use_sharpen_2));
    s.set_sharpen2_method(if text(&o.sharpen_method_2) == "unsharp" { 1 } else { 0 });
    s.set_cas2_strength(text(&o.sharpen_strength_2).into());
    s.set_usm2_radius(text(&o.usm_radius_2).into());
    s.set_usm2_amount(text(&o.usm_amount_2).into());
    let (deband2, f3kdb2) = deband_choice(flag(o.use_deband_2), &text(&o.deband_method_2));
    s.set_deband2(deband2);
    s.set_f3kdb2(f3kdb2);
    s.set_deband2_strength(text(&o.deband_strength_2).into());
    s.set_f3kdb2_range(text(&o.f3kdb_range_2).into());
    s.set_f3kdb2_y(text(&o.f3kdb_y_2).into());
    s.set_f3kdb2_cbcr(text(&o.f3kdb_cbcr_2).into());
    s.set_grain2(flag(o.use_grain_2));
    s.set_grain2_strength(text(&o.grain_strength_2).into());

    s.set_deblock(if flag(o.no_deblock) {
        0
    } else {
        index_of(&DEBLOCK_MODES, &text(&o.deblock_mode)).map_or(2, |i| i as i32 + 1)
    });
    let thresholds = text(&o.deblock_thresh);
    s.set_deblock_alpha(threshold(&thresholds, "alpha").into());
    s.set_deblock_beta(threshold(&thresholds, "beta").into());
    s.set_deblock_gamma(threshold(&thresholds, "gamma").into());
    s.set_deblock_delta(threshold(&thresholds, "delta").into());
    let (deband, f3kdb) = deband_choice(!flag(o.no_deband), &text(&o.deband_method));
    s.set_deband(deband);
    s.set_f3kdb(f3kdb);
    s.set_deband_strength(text(&o.deband_strength).into());
    s.set_f3kdb_range(text(&o.f3kdb_range).into());
    s.set_f3kdb_y(text(&o.f3kdb_y).into());
    s.set_f3kdb_cbcr(text(&o.f3kdb_cbcr).into());
    s.set_grain(if flag(o.no_grain) { "0".into() } else { text(&o.grain_strength).into() });
    s.set_decimate(!flag(o.no_decimate));

    s.set_custom_output(!text(&o.outdir).is_empty());
    s.set_output_folder(text(&o.outdir).into());
    s.set_hwaccel(index_of(hwaccels(), &text(&o.hwaccel)).unwrap_or(0) as i32);
    s.set_encoder(index_of(encoders(), &text(&o.encoder)).unwrap_or(0) as i32);
    s.set_hevc(text(&o.codec) == "hevc");
    s.set_ten_bit(flag(o.use10));
    s.set_faststart(text(&o.movflags).contains("+faststart"));
    s.set_force_8bit(flag(o.pci_safe_mode));
    s.set_audio_bitrate(text(&o.audio_bitrate).into());
    s.set_preset(index_of(&PRESETS, &text(&o.preset)).unwrap_or(1) as i32);
    s.set_threads(text(&o.threads).into());
    let (aq, psy, deblock1, deblock2) = x265_fields(&text(&o.x265_params));
    s.set_aq_mode(aq.into());
    s.set_psy_rd(psy.into());
    s.set_x265_deblock1(deblock1.into());
    s.set_x265_deblock2(deblock2.into());
    update_ranges(s);
}

/// Keeps the denoise slider's range in step with the chosen denoiser, clamping the strength into it, and checks
/// the deblock thresholds.
pub fn update_ranges(s: &Settings) {
    let denoiser = DENOISERS[(s.get_denoise() - 1).clamp(0, 3) as usize];
    let (lo, hi, default) = denoise_range(denoiser);
    s.set_denoise_min(lo);
    s.set_denoise_max(hi);
    s.set_denoise_default(default);
    s.set_denoise_strength(s.get_denoise_strength().clamp(lo, hi));
    let values = [s.get_deblock_alpha(), s.get_deblock_beta(), s.get_deblock_gamma(), s.get_deblock_delta()];
    s.set_deblock_valid(thresholds_valid(&values.map(|v| v.trim().to_owned())));
}

/// The backend options for what the interface shows. Fields the interface does not expose keep their defaults.
pub fn options(s: &Settings) -> Options {
    let mut o = Options::default();
    set(&mut o.scaler, "lanczos");
    set(&mut o.crf, &format!("{}", s.get_crf().round() as i32));
    set(&mut o.scale_factor, &s.get_scale());
    set(&mut o.fps, &s.get_fps());
    let interpolation = s.get_interpolation();
    o.no_interpolate = (interpolation == 0) as i32;
    set(&mut o.mi_mode, if interpolation == 2 { "blend" } else { "mci" });

    let denoise = s.get_denoise();
    o.no_denoise = (denoise == 0) as i32;
    if denoise > 0 {
        set(&mut o.denoiser, DENOISERS[(denoise - 1).clamp(0, 3) as usize]);
    }
    set(&mut o.denoise_strength, &format!("{:.2}", s.get_denoise_strength()));
    let dering = s.get_dering();
    // Zero switches deringing off and leaves the factory strength.
    o.dering_active = (dering > 0.0) as i32;
    if dering > 0.0 {
        set(&mut o.dering_strength, &format!("{dering:.3}"));
    }
    o.no_sharpen = !s.get_sharpen() as i32;
    set(&mut o.sharpen_method, if s.get_sharpen_method() == 1 { "unsharp" } else { "cas" });
    set(&mut o.sharpen_strength, &format!("{:.3}", s.get_cas_strength()));
    set(&mut o.usm_radius, &format!("{}", s.get_usm_radius().round() as i32));
    set(&mut o.usm_amount, &format!("{:.2}", s.get_usm_amount()));
    set(&mut o.usm_threshold, &format!("{:.3}", s.get_usm_threshold()));
    o.no_eq = !s.get_eq() as i32;
    set(&mut o.eq_contrast, &format!("{:.3}", s.get_contrast()));
    set(&mut o.eq_brightness, &format!("{:.3}", s.get_brightness()));
    set(&mut o.eq_saturation, &format!("{:.3}", s.get_saturation()));

    let denoise2 = s.get_denoise2();
    o.use_denoise_2 = (denoise2 > 0) as i32;
    if denoise2 > 0 {
        set(&mut o.denoiser_2, DENOISERS[(denoise2 - 1).clamp(0, 3) as usize]);
    }
    set(&mut o.denoise_strength_2, &s.get_denoise2_strength());
    let dering2 = s.get_dering2();
    o.use_dering_2 = (dering2 > 0.0) as i32;
    o.dering_active_2 = o.use_dering_2;
    if dering2 > 0.0 {
        set(&mut o.dering_strength_2, &format!("{dering2:.3}"));
    }
    o.use_sharpen_2 = s.get_sharpen2() as i32;
    set(&mut o.sharpen_method_2, if s.get_sharpen2_method() == 1 { "unsharp" } else { "cas" });
    set(&mut o.sharpen_strength_2, &s.get_cas2_strength());
    set(&mut o.usm_radius_2, &s.get_usm2_radius());
    set(&mut o.usm_amount_2, &s.get_usm2_amount());
    let deband2 = s.get_deband2();
    o.use_deband_2 = (deband2 > 0) as i32;
    if deband2 > 0 {
        set(&mut o.deband_method_2, deband_method(deband2, s.get_f3kdb2()));
    }
    set(&mut o.deband_strength_2, &s.get_deband2_strength());
    set(&mut o.f3kdb_range_2, &s.get_f3kdb2_range());
    set(&mut o.f3kdb_y_2, &s.get_f3kdb2_y());
    set(&mut o.f3kdb_cbcr_2, &s.get_f3kdb2_cbcr());
    o.use_grain_2 = s.get_grain2() as i32;
    set(&mut o.grain_strength_2, &s.get_grain2_strength());

    let deblock = s.get_deblock();
    o.no_deblock = (deblock == 0) as i32;
    if deblock > 0 {
        set(&mut o.deblock_mode, DEBLOCK_MODES[(deblock - 1).clamp(0, 1) as usize]);
    }
    let values = [s.get_deblock_alpha(), s.get_deblock_beta(), s.get_deblock_gamma(), s.get_deblock_delta()];
    let thresholds: Vec<String> = DEBLOCK_KEYS
        .iter()
        .zip(&values)
        .filter(|(_, v)| !v.trim().is_empty())
        .map(|(k, v)| format!("{k}={}", v.trim()))
        .collect();
    set(&mut o.deblock_thresh, &thresholds.join(":"));
    let deband = s.get_deband();
    o.no_deband = (deband == 0) as i32;
    if deband > 0 {
        set(&mut o.deband_method, deband_method(deband, s.get_f3kdb()));
    }
    set(&mut o.deband_strength, &s.get_deband_strength());
    set(&mut o.f3kdb_range, &s.get_f3kdb_range());
    set(&mut o.f3kdb_y, &s.get_f3kdb_y());
    set(&mut o.f3kdb_cbcr, &s.get_f3kdb_cbcr());
    set(&mut o.grain_strength, &s.get_grain());
    o.no_decimate = !s.get_decimate() as i32;

    set(&mut o.outdir, if s.get_custom_output() { s.get_output_folder() } else { Default::default() }.as_str());
    set(&mut o.hwaccel, hwaccels()[(s.get_hwaccel().max(0) as usize).min(hwaccels().len() - 1)]);
    set(&mut o.encoder, encoders()[(s.get_encoder().max(0) as usize).min(encoders().len() - 1)]);
    set(&mut o.codec, if s.get_hevc() { "hevc" } else { "h264" });
    o.use10 = s.get_ten_bit() as i32;
    set(&mut o.movflags, if s.get_faststart() { "+faststart" } else { "" });
    o.pci_safe_mode = s.get_force_8bit() as i32;
    set(&mut o.audio_bitrate, &s.get_audio_bitrate());
    set(&mut o.preset, PRESETS[s.get_preset().clamp(0, 2) as usize]);
    set(&mut o.threads, &s.get_threads());
    set(
        &mut o.x265_params,
        &x265_params(&s.get_aq_mode(), &s.get_psy_rd(), &s.get_x265_deblock1(), &s.get_x265_deblock2()),
    );
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

    /// Every field the interface shows survives load → options unchanged.
    #[test]
    fn factory_settings_round_trip() {
        let ui = window();
        let s = ui.global::<Settings>();
        let defaults = Options::default();
        load(&s, &defaults);
        let o = options(&s);
        let numeric = ["crf", "denoise_strength", "sharpen_strength", "usm_amount", "usm_threshold", "dering_strength"];
        for (name, _) in up60p::options::FIELDS {
            let (a, b) = (o.get(name).unwrap(), defaults.get(name).unwrap());
            if numeric.contains(name) || name.starts_with("eq_") {
                assert_eq!(number(&a, -1.0), number(&b, -2.0), "{name}");
            } else {
                assert_eq!(a, b, "{name}");
            }
        }
    }

    #[test]
    fn choices_map_to_backend_names() {
        let ui = window();
        let s = ui.global::<Settings>();
        load(&s, &Options::default());
        s.set_denoise(2);
        s.set_interpolation(2);
        s.set_deblock(1);
        s.set_deband(3);
        s.set_sharpen_method(1);
        s.set_dering(0.0);
        s.set_custom_output(true);
        s.set_output_folder("/out".into());
        let o = options(&s);
        assert_eq!((o.no_denoise, text(&o.denoiser).as_str()), (0, "nlmeans"));
        assert_eq!((o.no_interpolate, text(&o.mi_mode).as_str()), (0, "blend"));
        assert_eq!(text(&o.deblock_mode), "weak");
        assert_eq!(text(&o.deband_method), "neo_f3kdb");
        assert_eq!(text(&o.sharpen_method), "unsharp");
        assert_eq!(o.dering_active, 0);
        assert_eq!(text(&o.outdir), "/out");
        s.set_custom_output(false);
        s.set_denoise(0);
        s.set_deblock(0);
        s.set_deband(0);
        let o = options(&s);
        assert_eq!((o.no_denoise, o.no_deblock, o.no_deband, text(&o.outdir).as_str()), (1, 1, 1, ""));
    }

    #[test]
    fn f3kdb_is_kept_under_deband() {
        let ui = window();
        let s = ui.global::<Settings>();
        let mut o = Options::default();
        set(&mut o.deband_method, "f3kdb");
        load(&s, &o);
        assert_eq!((s.get_deband(), s.get_f3kdb()), (1, true));
        assert_eq!(text(&options(&s).deband_method), "f3kdb");
    }

    #[test]
    fn thresholds_and_x265_parameters() {
        let ui = window();
        let s = ui.global::<Settings>();
        let mut o = Options::default();
        set(&mut o.deblock_thresh, "alpha=0.1:delta=0.2");
        set(&mut o.x265_params, "aq-mode=3,psy-rd=2.0,deblock=-2,-1");
        load(&s, &o);
        assert_eq!((s.get_deblock_alpha().as_str(), s.get_deblock_delta().as_str()), ("0.1", "0.2"));
        assert_eq!((s.get_x265_deblock1().as_str(), s.get_x265_deblock2().as_str()), ("-2", "-1"));
        let back = options(&s);
        assert_eq!(text(&back.deblock_thresh), "alpha=0.1:delta=0.2");
        assert_eq!(text(&back.x265_params), "aq-mode=3,psy-rd=2.0,deblock=-2,-1");
        s.set_deblock_beta("2".into());
        update_ranges(&s);
        assert!(!s.get_deblock_valid());
    }

    #[test]
    fn denoise_range_follows_the_denoiser() {
        let ui = window();
        let s = ui.global::<Settings>();
        load(&s, &Options::default());
        s.set_denoise(2); // NLMeans: 1..30
        s.set_denoise_strength(45.0);
        update_ranges(&s);
        assert_eq!((s.get_denoise_min(), s.get_denoise_max(), s.get_denoise_default()), (1.0, 30.0, 1.0));
        assert_eq!(s.get_denoise_strength(), 30.0);
    }
}
