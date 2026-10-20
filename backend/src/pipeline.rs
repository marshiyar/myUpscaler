//! Turns the app's options into a filter chain, in the order the app has always applied them:
//!
//! decimate → deblock → dering → denoise → retime/interpolate → Lanczos scale → sharpen → deband → second-set
//! deblock, dering, denoise, sharpen and deband → EQ → grain.
//!
//! Strength mappings (how a slider value becomes filter parameters) are the app's established ones.

use crate::filters::atadenoise::AtaDenoise;
use crate::filters::bm3d::Bm3d;
use crate::filters::deband::{Deband, GradFun};
use crate::filters::deblock::Deblock;
use crate::filters::decimate::Decimate;
use crate::filters::eq::Eq;
use crate::filters::grain::Grain;
use crate::filters::hqdn3d::Hqdn3d;
use crate::filters::interpolate::{Mode, Retimer};
use crate::filters::nlmeans::NlMeans;
use crate::filters::scale::{scaled_size, Lanczos};
use crate::filters::sharpen::{Cas, Unsharp};
use crate::filters::{number, Chain, Filter};
use crate::options::{text, Options};

/// What is being processed.
#[derive(Clone, Copy, Debug)]
pub enum Source {
    Video { fps: f64 },
    Image,
}

pub struct Plan {
    pub chain: Chain,
    /// Output frame rate as a fraction (videos only).
    pub fps: Option<(u32, u32)>,
    pub scale: f64,
    /// Settings that cannot be honoured, to tell the user.
    pub notes: Vec<String>,
}

/// A non-negative strength; `auto`, empty, negative or invalid text gives 0 (the filter's default applies).
fn strength(s: &str) -> f64 {
    number(s).filter(|v| *v >= 0.0).unwrap_or(0.0)
}

fn flag(v: i32) -> bool {
    v != 0
}

pub fn hqdn3d(s: &str) -> Hqdn3d {
    let mut luma = strength(s);
    if luma <= 0.0 {
        luma = 4.0;
    }
    let luma = luma.clamp(1.0, 10.0);
    let temporal = luma * 1.5;
    Hqdn3d::new(luma, luma * 0.75, temporal, temporal * 0.75)
}

pub fn nlmeans(s: &str) -> NlMeans {
    let mut sigma = strength(s);
    if sigma <= 0.0 {
        sigma = 1.0;
    }
    let sigma = sigma.clamp(1.0, 30.0);
    let step = |limits: &[f64], base: usize| base + 2 * limits.iter().filter(|&&l| sigma > l).count();
    NlMeans::new(sigma, step(&[5.0, 10.0, 15.0, 20.0], 7), step(&[5.0, 10.0, 15.0, 20.0, 25.0], 15))
}

pub fn atadenoise(s: &str) -> AtaDenoise {
    let mut t = strength(s);
    if t <= 0.0 {
        t = 9.0;
    }
    let t = t.clamp(1.0, 20.0);
    AtaDenoise::new(t, 0.01 + t / 20.0 * 0.03, 0.02 + t / 20.0 * 0.06)
}

pub fn bm3d(s: &str) -> Bm3d {
    if s.trim() == "auto" {
        return Bm3d::new(None);
    }
    let mut sigma = strength(s);
    if sigma <= 0.0 {
        sigma = 2.5;
    }
    Bm3d::new(Some(sigma.min(20.0)))
}

pub fn dering(s: &str) -> Hqdn3d {
    let mut d = strength(s);
    if d <= 0.0 {
        d = 0.5;
    }
    let luma = d * 8.0;
    let (chroma, luma_t) = (luma * 0.75, luma * 1.5);
    Hqdn3d::new(luma.min(15.0), chroma, luma_t, luma_t * 0.75).dering()
}

fn denoiser(kind: &str, s: &str) -> Option<Box<dyn Filter>> {
    Some(match kind {
        "bm3d" => Box::new(bm3d(s)),
        "hqdn3d" => Box::new(hqdn3d(s)),
        "nlmeans" => Box::new(nlmeans(s)),
        "atadenoise" => Box::new(atadenoise(s)),
        _ => return None,
    })
}

fn sharpener(method: &str, strength_s: &str, radius: &str, amount: &str, threshold: &str) -> Box<dyn Filter> {
    if method == "unsharp" {
        Box::new(Unsharp::new(
            number(radius).unwrap_or(5.0),
            number(amount).unwrap_or(1.0),
            number(threshold).unwrap_or(0.0),
        ))
    } else {
        Box::new(Cas::new(number(strength_s).unwrap_or(0.25)))
    }
}

fn debander(method: &str, s: &str, range: &str, y: &str, cbcr: &str) -> Box<dyn Filter> {
    match method {
        "gradfun" => Box::new(GradFun::new(number(s).unwrap_or(1.2))),
        "f3kdb" => {
            let y = number(y).unwrap_or(0.0);
            let c = number(cbcr).unwrap_or(0.0);
            let thr_y = if y > 0.0 { y / 2000.0 } else { 0.03 }.clamp(0.001, 0.5);
            let thr_c = if c > 0.0 { c / 2000.0 } else { 0.015 }.min(0.5);
            let r = number(range).map_or(16, |r| r as i64);
            Box::new(Deband::new(thr_y, thr_c, if r < 1 { 16 } else { r as usize }, false))
        }
        _ => Box::new(Deband::new(number(s).unwrap_or(0.02), 0.02, 16, true)),
    }
}

/// The output frame rate for a source rate and the fps option (`source`/`lock` keep the source rate).
pub fn output_fps(fps_option: &str, src_fps: f64, interpolate: bool) -> f64 {
    let target = if interpolate && fps_option != "source" && fps_option != "lock" { number(fps_option) } else { None };
    match target.filter(|v| *v > 0.0 && *v <= 240.0) {
        Some(v) => v,
        None if src_fps > 0.0 => src_fps,
        None => 30.0,
    }
}

/// A frame rate as a fraction, recognising the NTSC rates.
pub fn rational(fps: f64) -> (u32, u32) {
    for base in [24.0, 30.0, 48.0, 60.0, 120.0] {
        if (fps - base * 1000.0 / 1001.0).abs() < 0.005 {
            return ((base * 1000.0) as u32, 1001);
        }
    }
    if (fps - fps.round()).abs() < 0.001 {
        return (fps.round().max(1.0) as u32, 1);
    }
    ((fps * 1000.0).round().max(1.0) as u32, 1000)
}

pub fn build(o: &Options, source: Source) -> Plan {
    let mut chain = Chain::default();
    let mut notes = Vec::new();
    let video = matches!(source, Source::Video { .. });
    let scale = number(&text(&o.scale_factor)).filter(|v| *v > 0.0 && *v <= 16.0).unwrap_or(2.0);

    if video && !flag(o.no_decimate) {
        chain.push_stage(Box::new(Decimate::default()));
    }
    if !flag(o.no_deblock) {
        chain.push_stage(Box::new(Deblock::new(&text(&o.deblock_mode), &text(&o.deblock_thresh))));
    }
    if flag(o.dering_active) {
        chain.push_stage(Box::new(dering(&text(&o.dering_strength))));
    }
    if !flag(o.no_denoise) {
        if let Some(f) = denoiser(&text(&o.denoiser), &text(&o.denoise_strength)) {
            chain.push_stage(f);
        }
    }
    let mut fps = None;
    if let Source::Video { fps: src_fps } = source {
        let interpolate = !flag(o.no_interpolate);
        let out = output_fps(&text(&o.fps), src_fps, interpolate);
        let mode = if interpolate { Mode::parse(&text(&o.mi_mode)) } else { Mode::Dup };
        chain.push_stage(Box::new(Retimer::new(mode, out, src_fps)));
        fps = Some(rational(out));
    }
    chain.push_stage(Box::new(Lanczos { factor: scale }));
    if !flag(o.no_sharpen) {
        chain.push_stage(sharpener(
            &text(&o.sharpen_method),
            &text(&o.sharpen_strength),
            &text(&o.usm_radius),
            &text(&o.usm_amount),
            &text(&o.usm_threshold),
        ));
    }
    if !flag(o.no_deband) {
        chain.push_stage(debander(
            &text(&o.deband_method),
            &text(&o.deband_strength),
            &text(&o.f3kdb_range),
            &text(&o.f3kdb_y),
            &text(&o.f3kdb_cbcr),
        ));
    }
    if flag(o.use_deblock_2) && !flag(o.no_deblock) {
        chain.push_stage(Box::new(Deblock::new(&text(&o.deblock_mode_2), &text(&o.deblock_thresh_2))));
    }
    if flag(o.use_dering_2) && flag(o.dering_active_2) {
        chain.push_stage(Box::new(dering(&text(&o.dering_strength_2))));
    }
    if flag(o.use_denoise_2) && !flag(o.no_denoise) {
        if let Some(f) = denoiser(&text(&o.denoiser_2), &text(&o.denoise_strength_2)) {
            chain.push_stage(f);
        }
    }
    if flag(o.use_sharpen_2) && !flag(o.no_sharpen) {
        chain.push_stage(sharpener(
            &text(&o.sharpen_method_2),
            &text(&o.sharpen_strength_2),
            &text(&o.usm_radius_2),
            &text(&o.usm_amount_2),
            &text(&o.usm_threshold_2),
        ));
    }
    if flag(o.use_deband_2) && !flag(o.no_deband) {
        chain.push_stage(debander(
            &text(&o.deband_method_2),
            &text(&o.deband_strength_2),
            &text(&o.f3kdb_range_2),
            &text(&o.f3kdb_y_2),
            &text(&o.f3kdb_cbcr_2),
        ));
    }
    if !flag(o.no_eq) {
        let eq = Eq::new(
            number(&text(&o.eq_contrast)).unwrap_or(1.0),
            number(&text(&o.eq_brightness)).unwrap_or(0.0),
            number(&text(&o.eq_saturation)).unwrap_or(1.0),
        );
        if !eq.is_identity() {
            chain.push_stage(Box::new(eq));
        }
    }
    if !flag(o.no_grain) {
        let s = if flag(o.use_grain_2) { text(&o.grain_strength_2) } else { text(&o.grain_strength) };
        let g = number(&s).unwrap_or(0.0);
        if g > 0.0 {
            chain.push_stage(Box::new(Grain::new(g)));
        }
    }

    if video {
        if text(&o.codec) == "hevc" {
            notes.push("HEVC output is not available in the Rust engine; writing H.264.".into());
        }
        if flag(o.use10) && !flag(o.pci_safe_mode) {
            notes.push("10-bit output is not available in the Rust engine; writing 8-bit H.264.".into());
        }
        if flag(o.preview) {
            notes.push("Live preview is not available in the Rust engine; processing without it.".into());
        }
    }
    Plan { chain, fps, scale, notes }
}

/// Output size for an input size: Lanczos rounding to even sides.
pub fn output_size(w: u32, h: u32, scale: f64) -> (u32, u32) {
    (scaled_size(w as usize, scale) as u32, scaled_size(h as usize, scale) as u32)
}

/// Encoder quality tier for an x264-style CRF.
pub fn quality(crf: &str) -> crate::engine::Quality {
    match number(crf) {
        Some(c) if c <= 20.0 => crate::engine::Quality::High,
        Some(c) if c > 26.0 => crate::engine::Quality::Draft,
        _ => crate::engine::Quality::Standard,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::options::set;

    #[test]
    fn default_video_chain_matches_the_app_order() {
        let plan = build(&Options::default(), Source::Video { fps: 24.0 });
        let d = plan.chain.describe();
        let order =
            ["decimate", "deblock", "bm3d", "retime(mci, 60.000", "lanczos(x2.00)", "cas", "deband", "eq", "grain"];
        let mut at = 0;
        for name in order {
            let found = d[at..].find(name).unwrap_or_else(|| panic!("{name} missing or out of order in {d}"));
            at += found + name.len();
        }
        assert_eq!(plan.fps, Some((60, 1)));
    }

    #[test]
    fn images_skip_temporal_stages() {
        let d = build(&Options::default(), Source::Image).chain.describe();
        assert!(!d.contains("decimate") && !d.contains("retime"), "{d}");
    }

    #[test]
    fn source_rate_and_toggles() {
        let mut o = Options::default();
        set(&mut o.fps, "source");
        o.no_denoise = 1;
        o.no_grain = 1;
        o.no_eq = 1;
        let plan = build(&o, Source::Video { fps: 30000.0 / 1001.0 });
        assert_eq!(plan.fps, Some((30000, 1001)));
        let d = plan.chain.describe();
        assert!(!d.contains("bm3d") && !d.contains("grain") && !d.contains("eq("), "{d}");
        o.no_interpolate = 1;
        set(&mut o.fps, "120");
        assert_eq!(build(&o, Source::Video { fps: 25.0 }).fps, Some((25, 1)));
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
        assert_eq!(quality("18"), crate::engine::Quality::High);
        assert_eq!(quality("23"), crate::engine::Quality::Standard);
        assert_eq!(quality("30"), crate::engine::Quality::Draft);
    }
}
