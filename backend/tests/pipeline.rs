//! How the app's options become a filter chain (`pipeline::build`): stage order, switches, zero-strength bypass,
//! validation, frame-rate handling and strength mappings.

// The cases read as "defaults, then these changes".
#![allow(clippy::field_reassign_with_default)]

use up60p::options::{set, Options};
use up60p::pipeline::*;

fn video(o: &Options, fps: f64) -> Plan {
    build(o, Source::Video { fps }).unwrap()
}

fn assert_order(d: &str, order: &[&str]) {
    let mut at = 0;
    for name in order {
        let found = d[at..].find(name).unwrap_or_else(|| panic!("{name} missing or out of order in {d}"));
        at += found + name.len();
    }
}

#[test]
fn default_video_chain_matches_the_app_order() {
    let plan = video(&Options::default(), 24.0);
    let d = plan.chain.describe();
    assert_order(
        &d,
        &["decimate", "deblock", "bm3d", "retime(dup, 60.000", "lanczos(x2.00)", "cas", "deband", "grain"],
    );
    // The factory EQ is neutral, so it is left out.
    assert!(!d.contains("eq("), "{d}");
    assert_eq!(plan.fps, Some((60, 1)));
}

#[test]
fn denoise_comes_before_dering_and_the_second_set_runs_on_its_own_switches() {
    let mut o = Options::default();
    o.dering_active = 1;
    o.no_deblock = 1;
    o.no_denoise = 1;
    o.use_dering_2 = 1;
    o.use_deblock_2 = 1;
    o.use_denoise_2 = 1;
    set(&mut o.denoiser_2, "nlmeans");
    let d = build(&o, Source::Image).unwrap().chain.describe();
    assert_order(&d, &["dering", "lanczos", "cas", "deband", "dering", "deblock", "nlmeans"]);
    let mut o = Options::default();
    o.dering_active = 1;
    let d = build(&o, Source::Image).unwrap().chain.describe();
    assert_order(&d, &["deblock", "bm3d", "dering"]);
}

#[test]
fn images_skip_temporal_stages() {
    let d = build(&Options::default(), Source::Image).unwrap().chain.describe();
    assert!(!d.contains("decimate") && !d.contains("retime"), "{d}");
}

#[test]
fn zero_strengths_bypass_their_stage() {
    let mut o = Options::default();
    o.no_grain = 1;
    o.use_denoise_2 = 1;
    o.use_sharpen_2 = 1;
    o.use_deband_2 = 1;
    o.use_dering_2 = 1;
    o.no_denoise = 1;
    o.no_sharpen = 1;
    o.no_deband = 1;
    for f in [
        &mut o.denoise_strength_2[..],
        &mut o.sharpen_strength_2[..],
        &mut o.deband_strength_2[..],
        &mut o.dering_strength_2[..],
    ] {
        set(f, "0");
    }
    let d = build(&o, Source::Image).unwrap().chain.describe();
    for name in ["bm3d", "cas", "deband", "dering"] {
        assert!(!d.contains(name), "{name} in {d}");
    }
    set(&mut o.sharpen_method_2, "unsharp");
    set(&mut o.usm_amount_2, "0");
    set(&mut o.deband_method_2, "f3kdb");
    for f in [&mut o.f3kdb_range_2[..], &mut o.f3kdb_y_2[..], &mut o.f3kdb_cbcr_2[..]] {
        set(f, "0");
    }
    let d = build(&o, Source::Image).unwrap().chain.describe();
    assert!(!d.contains("unsharp") && !d.contains("deband"), "{d}");
    // Grain runs when either the first set's switch or the second set's says so.
    o.use_grain_2 = 1;
    set(&mut o.grain_strength_2, "2");
    assert!(build(&o, Source::Image).unwrap().chain.describe().contains("grain(2.00)"));
    set(&mut o.grain_strength_2, "0");
    assert!(!build(&o, Source::Image).unwrap().chain.describe().contains("grain"));
}

#[test]
fn eq_is_validated_and_neutral_values_bypass_it() {
    let mut o = Options::default();
    set(&mut o.eq_contrast, "1.03");
    assert!(build(&o, Source::Image).unwrap().chain.describe().contains("eq(contrast=1.030"));
    for (field, bad) in [(0, "1001"), (1, "-1.5"), (2, "3.1"), (0, "abc"), (1, "inf")] {
        let mut o = Options::default();
        let f = [&mut o.eq_contrast[..], &mut o.eq_brightness[..], &mut o.eq_saturation[..]];
        set(f.into_iter().nth(field).unwrap(), bad);
        assert!(build(&o, Source::Image).is_err(), "{bad} accepted");
        o.no_eq = 1;
        assert!(build(&o, Source::Image).is_ok(), "{bad} rejected with EQ off");
    }
}

#[test]
fn hardware_choices_are_validated() {
    let mut o = Options::default();
    for (encoder, hwaccel, ok) in [
        ("auto", "none", true),
        ("cpu", "videotoolbox", true),
        ("videotoolbox", "none", true),
        ("nvenc", "none", false),
        ("auto", "cuda", false),
    ] {
        set(&mut o.encoder, encoder);
        set(&mut o.hwaccel, hwaccel);
        assert_eq!(build(&o, Source::Image).is_ok(), ok, "{encoder} {hwaccel}");
    }
    set(&mut o.encoder, "videotoolbox");
    set(&mut o.hwaccel, "none");
    o.use10 = 1;
    assert!(build(&o, Source::Video { fps: 24.0 }).is_err());
    assert!(build(&o, Source::Image).is_ok());
    set(&mut o.codec, "hevc");
    assert!(build(&o, Source::Video { fps: 24.0 }).is_ok());
}

#[test]
fn neo_f3kdb_takes_integer_parameters() {
    let mut o = Options::default();
    set(&mut o.deband_method, "neo_f3kdb");
    set(&mut o.f3kdb_range, "20");
    set(&mut o.f3kdb_y, "64");
    set(&mut o.f3kdb_cbcr, "32");
    let d = build(&o, Source::Image).unwrap().chain.describe();
    assert!(d.contains("deband(y=4.00, c=2.00, range=20, strict)"), "{d}");
    for (range, y) in [("256", "64"), ("20", "512"), ("2.5", "64"), ("20", "-1"), ("x", "64")] {
        set(&mut o.f3kdb_range, range);
        set(&mut o.f3kdb_y, y);
        assert!(build(&o, Source::Image).is_err(), "{range} {y} accepted");
    }
    for (range, y, c) in [("0", "64", "32"), ("20", "0", "0")] {
        set(&mut o.f3kdb_range, range);
        set(&mut o.f3kdb_y, y);
        set(&mut o.f3kdb_cbcr, c);
        assert!(!build(&o, Source::Image).unwrap().chain.describe().contains("deband"));
    }
}

#[test]
fn target_rates() {
    assert_eq!(target_rate("30000/1001"), Some((30000, 1001)));
    assert_eq!(target_rate("60"), Some((60, 1)));
    assert_eq!(target_rate("120/2"), Some((60, 1)));
    assert_eq!(target_rate("23.976"), Some((24000, 1001)));
    for bad in ["0", "-30", "abc", "30/0", "", "1e9", "nan"] {
        assert_eq!(target_rate(bad), None, "{bad}");
    }
    let mut o = Options::default();
    set(&mut o.fps, "fast");
    assert!(build(&o, Source::Video { fps: 24.0 }).is_err());
    assert!(build(&o, Source::Image).is_ok());
}

#[test]
fn source_rate_and_toggles() {
    let mut o = Options::default();
    set(&mut o.fps, "source");
    o.no_denoise = 1;
    o.no_grain = 1;
    o.no_eq = 1;
    let plan = video(&o, 30000.0 / 1001.0);
    assert_eq!(plan.fps, Some((30000, 1001)));
    let d = plan.chain.describe();
    assert!(!d.contains("bm3d") && !d.contains("grain") && !d.contains("eq("), "{d}");
    // Without interpolation the target rate is still honoured, by repeating and dropping frames.
    set(&mut o.fps, "120");
    let plan = video(&o, 25.0);
    assert_eq!(plan.fps, Some((120, 1)));
    assert!(plan.chain.describe().contains("retime(dup, 120.000"));
}

#[test]
fn verified_timing_gives_exact_frame_counts_and_interpolates_only_upwards() {
    let mut o = Options::default();
    o.no_interpolate = 0;
    o.source_cfr_verified = 1;
    o.source_video_duration = 10.01;
    o.source_rate_num = 24000;
    o.source_rate_den = 1001;
    o.source_frame_count = 240;
    set(&mut o.fps, "60");
    assert!(video(&o, 24.0).chain.describe().contains("retime(mci, 60.000 fps, 601 frames)"));
    set(&mut o.fps, "24000/1001");
    let d = video(&o, 24.0).chain.describe();
    assert!(d.contains("retime(dup, 23.976 fps, 240 frames)"), "{d}");
    set(&mut o.fps, "30");
    assert!(video(&o, 24.0).chain.describe().contains("retime(mci, 30.000 fps, 300 frames)"));
    set(&mut o.fps, "60");
    o.source_frame_count = 1;
    assert!(video(&o, 24.0).chain.describe().contains("retime(dup"));
    o.source_frame_count = 240;
    set(&mut o.mi_mode, "dup");
    assert!(video(&o, 24.0).chain.describe().contains("retime(dup"));
    // Unverified timing: interpolate without a frame limit, and say so.
    set(&mut o.mi_mode, "blend");
    o.source_cfr_verified = 0;
    let plan = video(&o, 24.0);
    assert!(plan.chain.describe().contains("retime(blend, 60.000 fps)"));
    assert!(plan.notes.iter().any(|n| n.contains("Source timing is unknown")));
    set(&mut o.fps, "source");
    o.source_cfr_verified = 1;
    assert_eq!(video(&o, 23.9).fps, Some((24000, 1001)));
}

#[test]
fn strength_mappings() {
    assert_eq!(nlmeans("12").patch, 11);
    assert_eq!(nlmeans("12").research, 19);
    assert_eq!(atadenoise("").frames, 9);
    assert!(bm3d("auto").sigma.is_none());
    assert_eq!(bm3d("50").sigma, Some(20.0));
    assert_eq!(rational(23.976), (24000, 1001));
    assert_eq!(rational(25.0), (25, 1));
    assert_eq!(quality("18"), up60p::engine::Quality::High);
    assert_eq!(quality("23"), up60p::engine::Quality::Standard);
    assert_eq!(quality("30"), up60p::engine::Quality::Draft);
}
