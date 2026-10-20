//! The contract between the app and the backend, reverse-engineered from what the Swift side sends
//! (`Up60PEngine.makeOptions`): every `up60p_options` field either changes what the backend does, or is listed in
//! `options::NOT_USED` with a reason. And each switch the app exposes has the effect its name promises.

use up60p::options::{set, Options, FIELDS, NOT_USED};
use up60p::pipeline::{build, Source};

/// A change to the options under test.
type Tweak = fn(&mut Options);

const SOURCES: [&str; 3] =
    [include_str!("../src/pipeline.rs"), include_str!("../src/job.rs"), include_str!("../src/lib.rs")];

/// Whether `options.<field>` / `o.<field>` is read anywhere outside the tests.
fn read_by_backend(field: &str) -> bool {
    SOURCES.iter().any(|src| {
        let code = src.split("#[cfg(test)]").next().unwrap_or(src);
        code.match_indices(&format!(".{field}")).any(|(i, m)| {
            let next = code[i + m.len()..].chars().next().unwrap_or(' ');
            !(next.is_alphanumeric() || next == '_')
        })
    })
}

#[test]
fn every_field_is_used_or_explained() {
    for (field, _) in FIELDS {
        let unused = NOT_USED.iter().find(|(f, _)| f == field);
        match unused {
            Some((_, reason)) => {
                assert!(!read_by_backend(field), "{field} is listed as unused ({reason}) but the backend reads it");
                assert!(!reason.is_empty());
            }
            None => assert!(read_by_backend(field), "{field} is neither used by the backend nor listed in NOT_USED"),
        }
    }
    for (field, _) in NOT_USED {
        assert!(FIELDS.iter().any(|(f, _)| f == field), "NOT_USED names a field that does not exist: {field}");
    }
}

fn video(o: &Options) -> String {
    build(o, Source::Video { fps: 24.0 }).chain.describe()
}

#[test]
fn each_off_switch_removes_its_stage() {
    let cases: [(&str, Tweak, &str); 8] = [
        ("no_decimate", |o| o.no_decimate = 1, "decimate"),
        ("no_deblock", |o| o.no_deblock = 1, "deblock"),
        ("no_denoise", |o| o.no_denoise = 1, "bm3d"),
        ("no_interpolate", |o| o.no_interpolate = 1, "retime(mci"),
        ("no_sharpen", |o| o.no_sharpen = 1, "cas("),
        ("no_deband", |o| o.no_deband = 1, "deband("),
        ("no_eq", |o| o.no_eq = 1, "eq("),
        ("no_grain", |o| o.no_grain = 1, "grain("),
    ];
    for (name, switch_off, stage) in cases {
        let mut o = Options::default();
        assert!(video(&o).contains(stage), "{stage} is on by default");
        switch_off(&mut o);
        assert!(!video(&o).contains(stage), "{name} leaves {stage} in place: {}", video(&o));
    }
    // Without interpolation the output still runs on a constant clock, repeating frames.
    let o = Options { no_interpolate: 1, ..Default::default() };
    assert!(video(&o).contains("retime(dup, 24.000 fps)"));
}

#[test]
fn each_second_set_switch_adds_its_stage() {
    let count = |d: &str, s: &str| d.matches(s).count();
    let base = video(&Options::default());
    let cases: [(Tweak, &str); 6] = [
        (|o| o.use_deblock_2 = 1, "deblock("),
        (
            |o| {
                o.use_dering_2 = 1;
                o.dering_active_2 = 1;
            },
            "dering(",
        ),
        (|o| o.use_denoise_2 = 1, "bm3d("),
        (|o| o.use_sharpen_2 = 1, "cas("),
        (|o| o.use_deband_2 = 1, "deband("),
        (
            |o| {
                o.use_grain_2 = 1;
                set(&mut o.grain_strength_2, "3.0");
            },
            "grain(3.00)",
        ),
    ];
    for (switch_on, stage) in cases {
        let mut o = Options::default();
        switch_on(&mut o);
        let d = video(&o);
        assert!(count(&d, stage) > count(&base, stage), "{stage} not added: {d}");
    }
    // The second dering needs both its own switch and its "active" flag, as in the app.
    let o = Options { use_dering_2: 1, ..Default::default() };
    assert!(!video(&o).contains("dering("));
    let o = Options { dering_active: 1, ..Default::default() };
    assert!(video(&o).contains("dering("), "first-set dering");
}

#[test]
fn each_method_choice_selects_its_filter() {
    let cases: [(Tweak, &str); 8] = [
        (|o| set(&mut o.denoiser, "hqdn3d"), "hqdn3d("),
        (|o| set(&mut o.denoiser, "nlmeans"), "nlmeans("),
        (|o| set(&mut o.denoiser, "atadenoise"), "atadenoise("),
        (|o| set(&mut o.denoise_strength, "auto"), "bm3d(sigma=auto)"),
        (|o| set(&mut o.sharpen_method, "unsharp"), "unsharp(5x5"),
        (|o| set(&mut o.deband_method, "gradfun"), "gradfun("),
        (|o| set(&mut o.deband_method, "f3kdb"), "strict"),
        (|o| set(&mut o.mi_mode, "blend"), "retime(blend"),
    ];
    for (choose, expected) in cases {
        let mut o = Options::default();
        choose(&mut o);
        assert!(video(&o).contains(expected), "expected {expected}: {}", video(&o));
    }
    let mut o = Options::default();
    set(&mut o.deblock_mode, "weak");
    assert!(video(&o).contains("deblock(weak"));
    set(&mut o.scale_factor, "4");
    assert!(video(&o).contains("lanczos(x4.00)"));
}

#[test]
fn output_rate_follows_the_fps_setting() {
    for (fps, expected) in [("60", (60, 1)), ("30", (30, 1)), ("source", (24, 1)), ("lock", (24, 1))] {
        let mut o = Options::default();
        set(&mut o.fps, fps);
        assert_eq!(build(&o, Source::Video { fps: 24.0 }).fps, Some(expected), "fps={fps}");
    }
}

#[test]
fn unsupported_requests_are_reported_not_ignored() {
    let mut o = Options::default();
    set(&mut o.codec, "hevc");
    o.use10 = 1;
    o.preview = 1;
    let notes = build(&o, Source::Video { fps: 24.0 }).notes.join("\n");
    assert!(notes.contains("HEVC") && notes.contains("10-bit") && notes.contains("preview"), "{notes}");
    assert!(build(&Options::default(), Source::Video { fps: 24.0 }).notes.is_empty());
}
