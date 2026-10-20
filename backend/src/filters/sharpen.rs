//! Luma sharpening, run after scaling:
//!
//! - contrast-adaptive sharpening (the published FidelityFX CAS formulation): a negative-lobe cross filter whose
//!   strength per pixel shrinks where the local neighbourhood already has high contrast, so edges sharpen without
//!   ringing or clipping;
//! - unsharp mask: adds back the difference from a Gaussian blur of the given window size, ignoring differences
//!   below a threshold so grain and noise are not amplified.

use super::Spatial;
use crate::frame::{Frame, Plane};
use crate::par;

pub struct Cas {
    /// 0..1.
    pub strength: f32,
}

impl Cas {
    pub fn new(strength: f64) -> Cas {
        Cas { strength: strength.clamp(0.0, 1.0) as f32 }
    }
}

impl Spatial for Cas {
    fn describe(&self) -> String {
        format!("cas({:.2})", self.strength)
    }

    fn apply(&mut self, frame: &mut Frame) {
        let src = frame.planes[0].clone();
        let peak = -1.0 / (8.0 + (5.0 - 8.0) * self.strength);
        let w = src.w;
        let h = src.h;
        let norm: Vec<f32> = src.data.iter().map(|v| (v / 255.0).clamp(0.0, 1.0)).collect();
        par::for_each_row(&mut frame.planes[0].data, w, |y, row| {
            let up = &norm[y.saturating_sub(1) * w..][..w];
            let mid = &norm[y * w..][..w];
            let down = &norm[(y + 1).min(h - 1) * w..][..w];
            for (x, out) in row.iter_mut().enumerate() {
                let (l, r) = (x.saturating_sub(1), (x + 1).min(w - 1));
                let (a, b, c) = (up[l], up[x], up[r]);
                let (d, e, f) = (mid[l], mid[x], mid[r]);
                let (g, h, i) = (down[l], down[x], down[r]);
                let mn_cross = b.min(d).min(e).min(f).min(h);
                let mn = mn_cross + mn_cross.min(a).min(c).min(g).min(i);
                let mx_cross = b.max(d).max(e).max(f).max(h);
                let mx = mx_cross + mx_cross.max(a).max(c).max(g).max(i);
                let amp = if mx > 0.0 { (mn.min(2.0 - mx) / mx).clamp(0.0, 1.0).sqrt() } else { 0.0 };
                let wgt = amp * peak;
                let v = ((b + d + f + h) * wgt + e) / (1.0 + 4.0 * wgt);
                *out = v * 255.0;
            }
        });
    }
}

pub struct Unsharp {
    /// Window side (odd, 3..=23).
    pub size: usize,
    pub amount: f32,
    /// Differences below this (code values) are not sharpened.
    pub threshold: f32,
}

impl Unsharp {
    /// `size` is the matrix size (rounded to odd 3..=23), `amount` in -2..5, `threshold` a fraction of the range.
    pub fn new(size: f64, amount: f64, threshold: f64) -> Unsharp {
        let s = (size.round().clamp(3.0, 23.0) as usize) | 1;
        Unsharp {
            size: s,
            amount: amount.clamp(-2.0, 5.0) as f32,
            threshold: (threshold.clamp(0.0, 1.0) * 255.0) as f32,
        }
    }

    fn blur(&self, p: &Plane) -> Plane {
        let r = self.size / 2;
        let sigma = r as f32 / 2.0 + 0.5;
        let kernel: Vec<f32> =
            (0..=2 * r).map(|i| (-((i as f32 - r as f32).powi(2)) / (2.0 * sigma * sigma)).exp()).collect();
        let norm: f32 = kernel.iter().sum();
        let kernel: Vec<f32> = kernel.into_iter().map(|k| k / norm).collect();
        let w = p.w;
        let mut mid = Plane::new(p.w, p.h, 0.0);
        par::for_each_row(&mut mid.data, w, |y, row| {
            for (x, o) in row.iter_mut().enumerate() {
                *o = kernel
                    .iter()
                    .enumerate()
                    .map(|(k, c)| c * p.clamped(x as isize + k as isize - r as isize, y as isize))
                    .sum();
            }
        });
        let mut out = Plane::new(p.w, p.h, 0.0);
        par::for_each_row(&mut out.data, w, |y, row| {
            for (x, o) in row.iter_mut().enumerate() {
                *o = kernel
                    .iter()
                    .enumerate()
                    .map(|(k, c)| c * mid.clamped(x as isize, y as isize + k as isize - r as isize))
                    .sum();
            }
        });
        out
    }
}

impl Spatial for Unsharp {
    fn describe(&self) -> String {
        format!("unsharp({}x{}, amount={:.2}, threshold={:.1})", self.size, self.size, self.amount, self.threshold)
    }

    fn apply(&mut self, frame: &mut Frame) {
        let blurred = self.blur(&frame.planes[0]);
        for (v, b) in frame.planes[0].data.iter_mut().zip(&blurred.data) {
            let d = *v - b;
            let d = d.signum() * (d.abs() - self.threshold).max(0.0);
            *v += self.amount * d;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::clean;

    fn edge_contrast(f: &Frame) -> f32 {
        // Across the vertical checker edge between x = 15 and 16.
        f.planes[0].at(16, 4) - f.planes[0].at(15, 4)
    }

    #[test]
    fn cas_increases_edge_contrast_and_keeps_flat_areas() {
        let mut f = clean(64, 32);
        for v in f.planes[0].data.iter_mut() {
            *v = (*v * 0.5 + 60.0).min(250.0);
        }
        let before = f.clone();
        Cas::new(0.8).apply(&mut f);
        assert!(edge_contrast(&f).abs() > edge_contrast(&before).abs());
        let mut flat = clean(16, 16);
        flat.planes[0].data.iter_mut().for_each(|v| *v = 90.0);
        Cas::new(1.0).apply(&mut flat);
        assert!(flat.planes[0].data.iter().all(|v| (v - 90.0).abs() < 1e-3));
    }

    #[test]
    fn unsharp_threshold_leaves_small_detail() {
        let mut f = clean(32, 32);
        f.planes[0].data.iter_mut().enumerate().for_each(|(i, v)| *v = 100.0 + (i % 2) as f32);
        let before = f.planes[0].clone();
        Unsharp::new(5.0, 1.0, 0.03).apply(&mut f);
        assert_eq!(f.planes[0], before);
        let mut g = clean(64, 32);
        let before = edge_contrast(&g);
        Unsharp::new(5.0, 1.0, 0.0).apply(&mut g);
        assert!(edge_contrast(&g).abs() > before.abs());
    }
}
