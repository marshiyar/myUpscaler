//! Turns the app's options into a filter chain, in the order the app applies them:
//!
//! decimate → deblock → denoise → dering → interpolate → Lanczos scale → sharpen → deband → second-set dering,
//! deblock, denoise, sharpen and deband → EQ → grain → repeat.
//!
//! A video's frame rate is changed by one of the two: interpolate (blend or motion-compensated pictures, a stage of
//! the chain) or repeat (showing frames again, done by the job on the finished pictures, so the filters run once per
//! source frame and a repeat costs nothing).
//!
//! Strength mappings (how a slider value becomes filter parameters) are the app's established ones. A strength of
//! exactly zero leaves its stage out, as does a neutral EQ. Invalid EQ values, frame rates, Neo F3kdb parameters and
//! hardware choices are errors rather than silently replaced.

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
use crate::filters::repeat::Repeater;
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
    /// Frame repetition to the output rate, after the chain (videos without interpolation).
    pub repeat: Option<Repeater>,
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

/// The dering stage; a strength of exactly zero leaves it out.
fn dering_stage(s: &str) -> Option<Box<dyn Filter>> {
    (!is_zero(s)).then(|| Box::new(dering(s)) as Box<dyn Filter>)
}

/// The denoiser named by `kind`; unknown names and a strength of exactly zero leave it out.
fn denoiser(kind: &str, s: &str) -> Option<Box<dyn Filter>> {
    if is_zero(s) {
        return None;
    }
    Some(match kind {
        "bm3d" => Box::new(bm3d(s)),
        "hqdn3d" => Box::new(hqdn3d(s)),
        "nlmeans" => Box::new(nlmeans(s)),
        "atadenoise" => Box::new(atadenoise(s)),
        _ => return None,
    })
}

/// True for text that is exactly the number zero ("0", "0.0"): the app's way of switching a stage off.
fn is_zero(s: &str) -> bool {
    number(s) == Some(0.0)
}

fn sharpener(method: &str, strength_s: &str, radius: &str, amount: &str, threshold: &str) -> Option<Box<dyn Filter>> {
    if method == "unsharp" {
        let amount = number(amount).unwrap_or(1.0);
        (amount != 0.0).then(|| {
            Box::new(Unsharp::new(number(radius).unwrap_or(5.0), amount, number(threshold).unwrap_or(0.0)))
                as Box<dyn Filter>
        })
    } else {
        let s = number(strength_s).unwrap_or(0.25);
        (s > 0.0).then(|| Box::new(Cas::new(s)) as Box<dyn Filter>)
    }
}

/// A whole number in `0..=max`, or `None`.
fn integer(s: &str, max: u32) -> Option<u32> {
    number(s).filter(|v| *v >= 0.0 && *v <= max as f64 && v.fract() == 0.0).map(|v| v as u32)
}

fn debander(method: &str, s: &str, range: &str, y: &str, cbcr: &str) -> Result<Option<Box<dyn Filter>>, String> {
    if method != "f3kdb" && method != "neo_f3kdb" && is_zero(s) {
        return Ok(None);
    }
    Ok(Some(match method {
        "gradfun" => Box::new(GradFun::new(number(s).unwrap_or(1.2))),
        "neo_f3kdb" => {
            // f3kdb's integer parameters: thresholds are on its 12-bit scale (16 per 8-bit code value).
            let (Some(r), Some(y), Some(c)) = (integer(range, 255), integer(y, 511), integer(cbcr, 511)) else {
                return Err("Neo F3kdb requires an integer range 0..255 and thresholds 0..511.".into());
            };
            if r == 0 || (y == 0 && c == 0) {
                return Ok(None);
            }
            let level = |t: u32| t as f64 / 16.0 / 255.0;
            Box::new(Deband::new(level(y), level(c), r as usize, false))
        }
        "f3kdb" => {
            if is_zero(range) && is_zero(y) && is_zero(cbcr) {
                return Ok(None);
            }
            let y = number(y).unwrap_or(0.0);
            let c = number(cbcr).unwrap_or(0.0);
            let thr_y = if y > 0.0 { y / 2000.0 } else { 0.03 }.clamp(0.001, 0.5);
            let thr_c = if c > 0.0 { c / 2000.0 } else { 0.015 }.min(0.5);
            let r = number(range).map_or(16, |r| r as i64);
            Box::new(Deband::new(thr_y, thr_c, if r < 1 { 16 } else { r as usize }, false))
        }
        _ => Box::new(Deband::new(number(s).unwrap_or(0.02), 0.02, 16, true)),
    }))
}

/// A target frame rate: a positive number or fraction such as `30000/1001`, as a fraction.
pub fn target_rate(s: &str) -> Option<(u32, u32)> {
    let s = s.trim();
    let (num, den) = match s.split_once('/') {
        Some((n, d)) => (number(n)?, number(d)?),
        None => (number(s)?, 1.0),
    };
    let rate = num / den;
    if !(num > 0.0 && den > 0.0 && rate.is_finite() && rate > 0.0 && rate <= MAX_FPS) {
        return None;
    }
    if num.fract() == 0.0 && den.fract() == 0.0 && num <= u32::MAX as f64 && den <= u32::MAX as f64 {
        let g = gcd(num as u64, den as u64);
        return Some(((num as u64 / g) as u32, (den as u64 / g) as u32));
    }
    Some(rational(rate))
}

fn gcd(a: u64, b: u64) -> u64 {
    if b == 0 {
        a.max(1)
    } else {
        gcd(b, a % b)
    }
}

/// Highest output frame rate accepted.
pub const MAX_FPS: f64 = 1000.0;

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

/// The source timing the app measured, when it is complete and the source is verified constant-rate.
pub struct Timing {
    pub duration: f64,
    pub rate: f64,
    pub frames: i64,
}

impl Timing {
    pub fn from_options(o: &Options) -> Option<Timing> {
        let known = flag(o.source_cfr_verified)
            && o.source_frame_count > 0
            && o.source_video_duration.is_finite()
            && o.source_video_duration > 0.0
            && o.source_rate_num > 0
            && o.source_rate_den > 0;
        known.then(|| Timing {
            duration: o.source_video_duration,
            rate: o.source_rate_num as f64 / o.source_rate_den as f64,
            frames: o.source_frame_count,
        })
    }
}

/// A strictly parsed value in `min..=max`.
fn within(s: &str, min: f64, max: f64) -> Option<f64> {
    number(s).filter(|v| (min..=max).contains(v))
}

fn validate_hardware(o: &Options, video: bool) -> Result<(), String> {
    let (encoder, hwaccel) = (text(&o.encoder), text(&o.hwaccel));
    if !matches!(encoder.as_str(), "" | "auto" | "cpu" | "videotoolbox")
        || !matches!(hwaccel.as_str(), "" | "none" | "videotoolbox")
    {
        return Err("Unsupported encoder or hardware decoder. Choose CPU/Auto or VideoToolbox.".into());
    }
    if video && encoder == "videotoolbox" && flag(o.use10) && text(&o.codec) == "h264" {
        return Err("VideoToolbox H.264 supports 8-bit output. Select HEVC for 10-bit output.".into());
    }
    Ok(())
}

/// Builds the filter chain, or explains which setting is invalid.
pub fn build(o: &Options, source: Source) -> Result<Plan, String> {
    let mut chain = Chain::default();
    let mut notes = Vec::new();
    let video = matches!(source, Source::Video { .. });
    validate_hardware(o, video)?;
    let eq = if flag(o.no_eq) {
        None
    } else {
        let (Some(c), Some(b), Some(s)) = (
            within(&text(&o.eq_contrast), -1000.0, 1000.0),
            within(&text(&o.eq_brightness), -1.0, 1.0),
            within(&text(&o.eq_saturation), 0.0, 3.0),
        ) else {
            return Err("Invalid EQ values: contrast -1000..1000, brightness -1..1, saturation 0..3.".into());
        };
        Some(Eq::new(c, b, s)).filter(|e| !e.is_identity())
    };
    let scale = number(&text(&o.scale_factor)).filter(|v| *v > 0.0 && *v <= 16.0).unwrap_or(2.0);

    if video && !flag(o.no_decimate) {
        chain.push_stage(Box::new(Decimate::default()));
    }
    if !flag(o.no_deblock) {
        chain.push_stage(Box::new(Deblock::new(&text(&o.deblock_mode), &text(&o.deblock_thresh))));
    }
    if !flag(o.no_denoise) {
        chain.push_some(denoiser(&text(&o.denoiser), &text(&o.denoise_strength)));
    }
    if flag(o.dering_active) {
        chain.push_some(dering_stage(&text(&o.dering_strength)));
    }
    let mut fps = None;
    let mut repeat = None;
    if let Source::Video { fps: src_fps } = source {
        let fps_option = text(&o.fps);
        let timing = Timing::from_options(o);
        let src_rate = timing.as_ref().map_or(src_fps, |t| t.rate);
        if fps_option == "source" || fps_option == "lock" {
            repeat = Some(Repeater::new(src_rate, src_rate));
            let exact =
                timing.as_ref().and_then(|_| target_rate(&format!("{}/{}", o.source_rate_num, o.source_rate_den)));
            fps = Some(exact.unwrap_or_else(|| rational(src_rate)));
        } else {
            let (num, den) =
                target_rate(&fps_option).ok_or("Invalid target FPS: a positive rate or fraction is required.")?;
            let target = num as f64 / den as f64;
            let mi_mode = text(&o.mi_mode);
            let mut interpolate = !flag(o.no_interpolate) && mi_mode != "dup";
            let mut retimer_frames = None;
            match &timing {
                Some(t) => {
                    if target <= t.rate * (1.0 + 1e-9) || t.frames == 1 {
                        interpolate = false;
                    }
                    retimer_frames = Some((t.duration * target + 0.5 + 1e-9).floor().max(1.0) as u64);
                }
                None if interpolate => notes.push(
                    "Source timing is unknown or variable; motion interpolation may shorten the final frames.".into(),
                ),
                None => {}
            }
            let mode = if interpolate { Mode::parse(&mi_mode) } else { Mode::Dup };
            if mode == Mode::Dup {
                let repeater = Repeater::new(target, src_rate);
                repeat = Some(match retimer_frames {
                    Some(n) => repeater.with_frame_limit(n),
                    None => repeater,
                });
            } else {
                let mut retimer = Retimer::new(mode, target, src_rate);
                if let Some(n) = retimer_frames {
                    retimer = retimer.with_frame_limit(n);
                }
                chain.push_stage(Box::new(retimer));
            }
            fps = Some((num, den));
        }
    }
    chain.push_stage(Box::new(Lanczos { factor: scale }));
    if !flag(o.no_sharpen) {
        chain.push_some(sharpener(
            &text(&o.sharpen_method),
            &text(&o.sharpen_strength),
            &text(&o.usm_radius),
            &text(&o.usm_amount),
            &text(&o.usm_threshold),
        ));
    }
    if !flag(o.no_deband) {
        chain.push_some(debander(
            &text(&o.deband_method),
            &text(&o.deband_strength),
            &text(&o.f3kdb_range),
            &text(&o.f3kdb_y),
            &text(&o.f3kdb_cbcr),
        )?);
    }
    if flag(o.use_dering_2) {
        chain.push_some(dering_stage(&text(&o.dering_strength_2)));
    }
    if flag(o.use_deblock_2) {
        chain.push_stage(Box::new(Deblock::new(&text(&o.deblock_mode_2), &text(&o.deblock_thresh_2))));
    }
    if flag(o.use_denoise_2) {
        chain.push_some(denoiser(&text(&o.denoiser_2), &text(&o.denoise_strength_2)));
    }
    if flag(o.use_sharpen_2) {
        chain.push_some(sharpener(
            &text(&o.sharpen_method_2),
            &text(&o.sharpen_strength_2),
            &text(&o.usm_radius_2),
            &text(&o.usm_amount_2),
            &text(&o.usm_threshold_2),
        ));
    }
    if flag(o.use_deband_2) {
        chain.push_some(debander(
            &text(&o.deband_method_2),
            &text(&o.deband_strength_2),
            &text(&o.f3kdb_range_2),
            &text(&o.f3kdb_y_2),
            &text(&o.f3kdb_cbcr_2),
        )?);
    }
    if let Some(eq) = eq {
        chain.push_stage(Box::new(eq));
    }
    if flag(o.use_grain_2) || !flag(o.no_grain) {
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
    Ok(Plan { chain, repeat, fps, scale, notes })
}

impl Plan {
    /// The chain and the repetition, for the log: `bm3d(...) -> lanczos(x2.00) -> retime(dup, 60.000 fps)`.
    pub fn describe(&self) -> String {
        match (&self.repeat, self.chain.is_empty()) {
            (Some(r), true) => r.describe(),
            (Some(r), false) => format!("{} -> {}", self.chain.describe(), r.describe()),
            (None, _) => self.chain.describe(),
        }
    }
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
