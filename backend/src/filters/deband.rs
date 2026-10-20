//! Banding removal for smooth gradients crushed by compression:
//!
//! - `Deband`: for each pixel, four reference pixels at a pseudo-random distance (up to `range`) and direction are
//!   compared with it. In blur mode the pixel takes their average when the average is within the threshold; in
//!   strict mode (used for the f3kdb settings) every reference must be within the threshold. The sampling pattern
//!   is fixed per position (a 128x128 tile), so static areas do not flicker.
//! - `GradFun`: pulls each pixel towards a wide box blur, fully where the difference is tiny and not at all where it
//!   reaches twice the strength, so only near-flat gradients are touched.
//!
//! The final conversion to 8 bits dithers, so the smoothed gradients do not band again.

use super::{box_sum, Spatial};
use crate::frame::{hash3, unit, Frame};
use crate::par;

pub struct Deband {
    /// Thresholds in code values for Y', Cb, Cr.
    pub thresholds: [f32; 3],
    pub range: usize,
    pub blur: bool,
}

impl Deband {
    /// Thresholds as fractions of the range.
    pub fn new(luma: f64, chroma: f64, range: usize, blur: bool) -> Deband {
        let t = |v: f64| (v.clamp(0.00003, 0.5) * 255.0) as f32;
        Deband { thresholds: [t(luma), t(chroma), t(chroma)], range: range.clamp(1, 64), blur }
    }
}

impl Spatial for Deband {
    fn describe(&self) -> String {
        format!(
            "deband(y={:.2}, c={:.2}, range={}, {})",
            self.thresholds[0],
            self.thresholds[1],
            self.range,
            if self.blur { "blur" } else { "strict" }
        )
    }

    fn apply(&mut self, frame: &mut Frame) {
        for (pi, plane) in frame.planes.iter_mut().enumerate() {
            let offsets = self.offsets(pi);
            let src = plane.clone();
            let thr = self.thresholds[pi];
            let (w, h) = (src.w, src.h);
            let r = self.range;
            par::for_each_row(&mut plane.data, w, |y, row| {
                let pattern = &offsets[(y % TILE) * TILE..][..TILE];
                let interior_row = y >= r && y + r < h;
                for (x, out) in row.iter_mut().enumerate() {
                    let (dx, dy) = pattern[x % TILE];
                    let refs = if interior_row && x >= r && x + r < w {
                        let at = |ox: isize, oy: isize| {
                            src.data[(y as isize + oy) as usize * w + (x as isize + ox) as usize]
                        };
                        [at(dx, dy), at(-dx, -dy), at(-dy, dx), at(dy, -dx)]
                    } else {
                        let (xi, yi) = (x as isize, y as isize);
                        [
                            src.clamped(xi + dx, yi + dy),
                            src.clamped(xi - dx, yi - dy),
                            src.clamped(xi - dy, yi + dx),
                            src.clamped(xi + dy, yi - dx),
                        ]
                    };
                    let c = *out;
                    let avg = (refs[0] + refs[1] + refs[2] + refs[3]) * 0.25;
                    let smooth =
                        if self.blur { (avg - c).abs() < thr } else { refs.iter().all(|r| (r - c).abs() < thr) };
                    if smooth {
                        *out = avg;
                    }
                }
            });
        }
    }
}

/// Side of the repeating tile of sampling offsets. Large enough that no repetition is visible.
const TILE: usize = 128;

impl Deband {
    /// Pseudo-random sampling offsets (distance 1..range, any direction) for one plane, per tile position.
    fn offsets(&self, plane: usize) -> Vec<(isize, isize)> {
        let range = self.range as f32;
        (0..TILE * TILE)
            .map(|i| {
                let h = hash3((i % TILE) as u32, (i / TILE) as u32, 0xDEBA_4D00 + plane as u32);
                let dist = 1.0 + unit(h) * (range - 1.0);
                let angle = unit(hash3(h, 7, 11)) * std::f32::consts::TAU;
                ((angle.cos() * dist).round() as isize, (angle.sin() * dist).round() as isize)
            })
            .collect()
    }
}

pub struct GradFun {
    /// Code values (0.51..64).
    pub strength: f32,
    pub radius: usize,
}

impl GradFun {
    /// Strengths below the useful minimum are read as fractions of the range (the deband slider's scale).
    pub fn new(strength: f64) -> GradFun {
        let s = if strength < 0.51 { strength * 255.0 } else { strength };
        GradFun { strength: s.clamp(0.51, 64.0) as f32, radius: 16 }
    }
}

impl Spatial for GradFun {
    fn describe(&self) -> String {
        format!("gradfun({:.2}, radius={})", self.strength, self.radius)
    }

    fn apply(&mut self, frame: &mut Frame) {
        let area = ((2 * self.radius + 1) * (2 * self.radius + 1)) as f32;
        for plane in frame.planes.iter_mut() {
            let blurred = box_sum(plane, self.radius);
            for (v, b) in plane.data.iter_mut().zip(&blurred.data) {
                let delta = b / area - *v;
                let m = (1.0 - delta.abs() / (2.0 * self.strength)).max(0.0);
                *v += delta * m * m;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::Plane;

    /// A slow horizontal gradient quantised into visible steps.
    fn banded() -> Frame {
        let (w, h) = (128, 32);
        let mut y = Plane::new(w, h, 0.0);
        for yy in 0..h {
            for x in 0..w {
                y.data[yy * w + x] = (60.0 + x as f32 * 0.1).floor();
            }
        }
        Frame { planes: [y, Plane::new(w, h, 128.0), Plane::new(w, h, 128.0)], alpha: None, pts: 0.0 }
    }

    /// The largest step between horizontal neighbours away from the borders.
    fn max_step(f: &Frame) -> f32 {
        let p = &f.planes[0];
        let mut m: f32 = 0.0;
        for y in 0..p.h {
            for x in 20..p.w - 20 {
                m = m.max((p.at(x, y) - p.at(x - 1, y)).abs());
            }
        }
        m
    }

    #[test]
    fn deband_softens_steps() {
        let mut f = banded();
        assert!(max_step(&f) >= 1.0);
        Deband::new(0.02, 0.02, 16, true).apply(&mut f);
        assert!(max_step(&f) < 0.9, "{}", max_step(&f));
    }

    #[test]
    fn gradfun_softens_steps() {
        let mut f = banded();
        GradFun::new(1.2).apply(&mut f);
        assert!(max_step(&f) < 0.9, "{}", max_step(&f));
    }

    #[test]
    fn strong_edges_survive() {
        let mut f = banded();
        for yy in 0..32 {
            for x in 64..128 {
                f.planes[0].data[yy * 128 + x] += 80.0;
            }
        }
        Deband::new(0.02, 0.02, 16, false).apply(&mut f);
        GradFun::new(1.2).apply(&mut f);
        assert!(f.planes[0].at(66, 5) - f.planes[0].at(61, 5) > 70.0);
    }
}
