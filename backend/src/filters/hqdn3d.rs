//! Recursive spatio-temporal low-pass denoiser. Each sample is pulled towards its already-filtered neighbour (left,
//! above, and the same pixel in the previous output frame) by a weight that falls as their difference grows, so
//! flat noise is averaged away while edges, whose differences are large, are left alone.
//!
//! The weight for a difference d is ((255 - |d|) / 255)^g, with g chosen so that a difference equal to the strength
//! keeps a quarter of the pull.

use super::Filter;
use crate::frame::{Frame, Plane};

/// Lookup resolution: entries per code value.
const STEPS: f32 = 4.0;
const LUT_LEN: usize = 255 * STEPS as usize + 1;

#[derive(Clone)]
struct Curve {
    lut: Vec<f32>,
    strength: f32,
}

impl Curve {
    fn new(strength: f64) -> Curve {
        let s = strength.clamp(0.0, 252.0) as f32;
        if s <= 0.0 {
            return Curve { lut: vec![0.0; LUT_LEN], strength: 0.0 };
        }
        let gamma = 0.25f32.ln() / (1.0 - s / 255.0 - 1e-5).ln();
        let lut = (0..LUT_LEN).map(|i| ((255.0 - i as f32 / STEPS) / 255.0).max(0.0).powf(gamma)).collect();
        Curve { lut, strength: s }
    }

    /// The filtered value: `cur` pulled towards `prev`.
    #[inline]
    fn pull(&self, cur: f32, prev: f32) -> f32 {
        let d = prev - cur;
        let i = ((d.abs() * STEPS) as usize).min(LUT_LEN - 1);
        cur + d * self.lut[i]
    }
}

pub struct Hqdn3d {
    spatial: [Curve; 2],
    temporal: [Curve; 2],
    previous: Option<[Plane; 3]>,
    label: &'static str,
}

impl Hqdn3d {
    /// Luma spatial, chroma spatial, luma temporal and chroma temporal strengths in code values.
    pub fn new(luma_spatial: f64, chroma_spatial: f64, luma_temporal: f64, chroma_temporal: f64) -> Hqdn3d {
        Hqdn3d {
            spatial: [Curve::new(luma_spatial), Curve::new(chroma_spatial)],
            temporal: [Curve::new(luma_temporal), Curve::new(chroma_temporal)],
            previous: None,
            label: "hqdn3d",
        }
    }

    /// The same filter used as a dering pass (named so in the log).
    pub fn dering(mut self) -> Hqdn3d {
        self.label = "dering";
        self
    }

    fn spatial_pass(curve: &Curve, p: &mut Plane) {
        if curve.strength <= 0.0 {
            return;
        }
        let w = p.w;
        // Horizontal, left to right, every row on its own.
        crate::par::for_each_row(&mut p.data, w, |_, row| {
            let mut acc = row[0];
            for v in row.iter_mut() {
                acc = curve.pull(*v, acc);
                *v = acc;
            }
        });
        // Vertical, top to bottom: each row pulls towards the filtered row above.
        for y in 1..p.h {
            let (above, rest) = p.data.split_at_mut(y * w);
            let above = &above[(y - 1) * w..];
            for (v, a) in rest[..w].iter_mut().zip(above) {
                *v = curve.pull(*v, *a);
            }
        }
    }
}

impl Filter for Hqdn3d {
    fn describe(&self) -> String {
        format!(
            "{}({:.2}:{:.2}:{:.2}:{:.2})",
            self.label,
            self.spatial[0].strength,
            self.spatial[1].strength,
            self.temporal[0].strength,
            self.temporal[1].strength
        )
    }

    fn push(&mut self, mut frame: Frame, out: &mut Vec<Frame>) {
        let previous = self.previous.take().filter(|p| p[0].w == frame.width() && p[0].h == frame.height());
        std::thread::scope(|s| {
            for (i, plane) in frame.planes.iter_mut().enumerate() {
                let k = usize::from(i > 0);
                let (spatial, temporal) = (&self.spatial[k], &self.temporal[k]);
                let prev = previous.as_ref().map(|p| &p[i]);
                s.spawn(move || {
                    Self::spatial_pass(spatial, plane);
                    if let (Some(prev), true) = (prev, temporal.strength > 0.0) {
                        for (v, p) in plane.data.iter_mut().zip(&prev.data) {
                            *v = temporal.pull(*v, *p);
                        }
                    }
                });
            }
        });
        self.previous = Some(frame.planes.clone());
        out.push(frame);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::{clean, frame, rms};

    #[test]
    fn reduces_noise_and_keeps_edges() {
        let truth = clean(96, 64);
        let mut f = Hqdn3d::new(4.0, 3.0, 6.0, 4.5);
        let mut out = Vec::new();
        for i in 0..4 {
            f.push(frame(96, 64, 6.0, i, i as f64), &mut out);
        }
        let last = out.last().unwrap();
        let noisy = frame(96, 64, 6.0, 3, 0.0);
        let before = rms(&noisy.planes[0], &truth.planes[0]);
        let after = rms(&last.planes[0], &truth.planes[0]);
        assert!(after < before * 0.75, "{before} -> {after}");
        // The 30-level checker edge survives.
        assert!((last.planes[0].at(15, 2) - last.planes[0].at(17, 2)).abs() > 20.0);
    }

    #[test]
    fn zero_strength_is_identity() {
        let input = frame(32, 16, 5.0, 1, 0.0);
        let mut out = Vec::new();
        Hqdn3d::new(0.0, 0.0, 0.0, 0.0).push(input.clone(), &mut out);
        assert_eq!(out[0].planes, input.planes);
    }
}
