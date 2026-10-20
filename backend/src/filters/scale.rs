//! Separable Lanczos-3 resampling. Output sizes are rounded down to even numbers (the encoder's 4:2:0 needs them).
//! When shrinking, the kernel is widened by the reduction factor so it also low-passes.

use super::Spatial;
use crate::frame::{Frame, Plane};
use crate::par;

const LOBES: f64 = 3.0;

pub struct Lanczos {
    pub factor: f64,
}

/// The output size for an input size and factor: `trunc(size * factor / 2) * 2`, at least 2.
pub fn scaled_size(size: usize, factor: f64) -> usize {
    (((size as f64 * factor / 2.0).trunc() as usize) * 2).max(2)
}

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-9 {
        1.0
    } else {
        let px = std::f64::consts::PI * x;
        px.sin() / px
    }
}

/// Taps for every output position: the first source index and the normalised weights.
fn taps(src: usize, dst: usize) -> Vec<(usize, Vec<f32>)> {
    let ratio = src as f64 / dst as f64;
    let stretch = ratio.max(1.0);
    let support = LOBES * stretch;
    (0..dst)
        .map(|o| {
            let centre = (o as f64 + 0.5) * ratio - 0.5;
            let first = (centre - support).floor() as isize + 1;
            let last = (centre + support).ceil() as isize - 1;
            let mut weights: Vec<f64> = (first..=last)
                .map(|i| {
                    let x = (i as f64 - centre) / stretch;
                    if x.abs() >= LOBES {
                        0.0
                    } else {
                        sinc(x) * sinc(x / LOBES)
                    }
                })
                .collect();
            let sum: f64 = weights.iter().sum();
            if sum.abs() > 1e-12 {
                weights.iter_mut().for_each(|w| *w /= sum);
            }
            // Clamp source indices by folding out-of-range taps onto the edge sample.
            let lo = first.max(0) as usize;
            let hi = (last.min(src as isize - 1)).max(lo as isize) as usize;
            let mut folded = vec![0.0f32; hi - lo + 1];
            for (k, w) in weights.into_iter().enumerate() {
                let i = (first + k as isize).clamp(lo as isize, hi as isize) as usize;
                folded[i - lo] += w as f32;
            }
            (lo, folded)
        })
        .collect()
}

pub fn resize(p: &Plane, w: usize, h: usize) -> Plane {
    if p.w == w && p.h == h {
        return p.clone();
    }
    let tx = taps(p.w, w);
    let ty = taps(p.h, h);
    // Horizontal pass: source rows to output width.
    let mut mid = Plane::new(w, p.h, 0.0);
    par::for_each_row(&mut mid.data, w, |y, row| {
        let src = p.row(y);
        for (o, (first, weights)) in row.iter_mut().zip(&tx) {
            *o = weights.iter().zip(&src[*first..]).map(|(w, v)| w * v).sum();
        }
    });
    // Vertical pass.
    let mut out = Plane::new(w, h, 0.0);
    par::for_each_row(&mut out.data, w, |y, row| {
        let (first, weights) = &ty[y];
        row.iter_mut().for_each(|v| *v = 0.0);
        for (k, wt) in weights.iter().enumerate() {
            let src = mid.row(first + k);
            for (o, v) in row.iter_mut().zip(src) {
                *o += wt * v;
            }
        }
    });
    out
}

impl Spatial for Lanczos {
    fn describe(&self) -> String {
        format!("lanczos(x{:.2})", self.factor)
    }

    fn apply(&mut self, frame: &mut Frame) {
        let w = scaled_size(frame.width(), self.factor);
        let h = scaled_size(frame.height(), self.factor);
        for p in frame.planes.iter_mut() {
            *p = resize(p, w, h);
        }
        if let Some(a) = frame.alpha.as_mut() {
            *a = resize(a, w, h);
            a.data.iter_mut().for_each(|v| *v = v.clamp(0.0, 255.0));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_are_even() {
        assert_eq!(scaled_size(1920, 2.0), 3840);
        assert_eq!(scaled_size(101, 1.5), 150);
        assert_eq!(scaled_size(853, 2.0), 1706);
        assert_eq!(scaled_size(1, 0.5), 2);
    }

    #[test]
    fn preserves_constant_and_ramp() {
        let mut p = Plane::new(20, 10, 0.0);
        for y in 0..10 {
            for x in 0..20 {
                p.data[y * 20 + x] = 50.0 + x as f32 * 2.0;
            }
        }
        let up = resize(&p, 40, 20);
        // Away from the edges a linear ramp stays linear: halfway samples interpolate.
        for x in 8..32 {
            let expect = 50.0 + ((x as f32 + 0.5) / 2.0 - 0.5) * 2.0;
            assert!((up.at(x, 10) - expect).abs() < 0.05, "x={x}: {} vs {expect}", up.at(x, 10));
        }
        let flat = resize(&Plane::new(7, 5, 99.0), 23, 11);
        assert!(flat.data.iter().all(|v| (v - 99.0).abs() < 1e-3));
    }

    #[test]
    fn downscale_averages() {
        let mut p = Plane::new(64, 2, 0.0);
        for (i, v) in p.data.iter_mut().enumerate() {
            *v = if i % 2 == 0 { 0.0 } else { 200.0 };
        }
        let half = resize(&p, 32, 2);
        assert!(half.data[4..28].iter().all(|v| (v - 100.0).abs() < 5.0));
    }
}
