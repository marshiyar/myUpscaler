//! Non-local means: every pixel becomes a weighted average of the pixels in its search window, weighted by how
//! similar the patches around them are. Patch distances are computed for one offset at a time over a whole band of
//! rows with running box sums, so the cost per pixel and offset is constant whatever the patch size.

use super::Spatial;
use crate::frame::{Frame, Plane};
use crate::par;

pub struct NlMeans {
    /// Noise level in code values.
    pub sigma: f32,
    /// Patch side (odd).
    pub patch: usize,
    /// Search window side (odd).
    pub research: usize,
}

/// Search window side above which the cost (quadratic in the side) stops paying for itself.
const MAX_RESEARCH: usize = 21;
const MAX_PATCH: usize = 11;

impl NlMeans {
    pub fn new(sigma: f64, patch: usize, research: usize) -> NlMeans {
        let odd = |v: usize, max: usize| (v.clamp(3, max)) | 1;
        NlMeans { sigma: sigma.max(0.1) as f32, patch: odd(patch, MAX_PATCH), research: odd(research, MAX_RESEARCH) }
    }

    fn plane(&self, src: &Plane, research: usize) -> Plane {
        let (w, h) = (src.w, src.h);
        let pr = (self.patch / 2) as isize;
        let rr = (research / 2) as isize;
        let area = (self.patch * self.patch) as f32;
        // Distances below the expected distance of two patches of pure noise (2 sigma^2) all count as a match.
        let floor = 2.0 * self.sigma * self.sigma;
        let h2 = (0.4 * self.sigma).powi(2).max(1e-3) * 4.0;
        let mut out = Plane::new(w, h, 0.0);
        par::for_each_row_chunk(&mut out.data, w, |y0, band| {
            let rows = band.len() / w;
            let ext = rows + 2 * pr as usize;
            let mut num = vec![0.0f32; rows * w];
            let mut den = vec![0.0f32; rows * w];
            let mut diff = vec![0.0f32; ext * w];
            let mut hsum = vec![0.0f32; ext * w];
            for dy in -rr..=rr {
                for dx in -rr..=rr {
                    // Squared differences for the band plus its patch margin.
                    for e in 0..ext {
                        let y = y0 as isize + e as isize - pr;
                        for x in 0..w {
                            let a = src.clamped(x as isize, y);
                            let b = src.clamped(x as isize + dx, y + dy);
                            diff[e * w + x] = (a - b) * (a - b);
                        }
                    }
                    // Horizontal box sums.
                    for e in 0..ext {
                        let row = &diff[e * w..(e + 1) * w];
                        let out_row = &mut hsum[e * w..(e + 1) * w];
                        let mut acc: f32 = (-pr..=pr).map(|k| row[k.clamp(0, w as isize - 1) as usize]).sum();
                        for (x, o) in out_row.iter_mut().enumerate() {
                            *o = acc;
                            let leave = (x as isize - pr).clamp(0, w as isize - 1) as usize;
                            let enter = (x as isize + pr + 1).clamp(0, w as isize - 1) as usize;
                            acc += row[enter] - row[leave];
                        }
                    }
                    // Vertical box sums give the patch distance; accumulate the weighted neighbour.
                    let centre = dx == 0 && dy == 0;
                    for x in 0..w {
                        let mut acc: f32 = (0..self.patch).map(|k| hsum[k * w + x]).sum();
                        for i in 0..rows {
                            let weight = if centre {
                                1.0
                            } else {
                                let d = (acc / area - floor).max(0.0);
                                (-d / h2).exp()
                            };
                            if weight > 1e-4 {
                                let y = (y0 + i) as isize;
                                num[i * w + x] += weight * src.clamped(x as isize + dx, y + dy);
                                den[i * w + x] += weight;
                            }
                            if i + 1 < rows {
                                acc += hsum[(i + self.patch) * w + x] - hsum[i * w + x];
                            }
                        }
                    }
                }
            }
            for i in 0..rows * w {
                band[i] = num[i] / den[i];
            }
        });
        out
    }
}

impl Spatial for NlMeans {
    fn describe(&self) -> String {
        format!("nlmeans(s={:.2}, p={}, r={})", self.sigma, self.patch, self.research)
    }

    fn apply(&mut self, frame: &mut Frame) {
        // Chroma is smoother and lower in detail; a smaller window costs a third as much for the same result.
        let chroma_research = (self.research / 2) | 1;
        for (i, p) in frame.planes.iter_mut().enumerate() {
            let r = if i == 0 { self.research } else { chroma_research.max(5) };
            *p = self.plane(p, r);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::{clean, frame, rms};

    #[test]
    fn reduces_noise() {
        let truth = clean(64, 48);
        let mut f = frame(64, 48, 10.0, 7, 0.0);
        let before = rms(&f.planes[0], &truth.planes[0]);
        NlMeans::new(8.0, 7, 11).apply(&mut f);
        let after = rms(&f.planes[0], &truth.planes[0]);
        assert!(after < before * 0.6, "{before} -> {after}");
    }

    #[test]
    fn flat_image_is_unchanged() {
        let mut f = frame(24, 24, 0.0, 0, 0.0);
        for p in f.planes.iter_mut() {
            p.data.iter_mut().for_each(|v| *v = 77.0);
        }
        NlMeans::new(3.0, 5, 7).apply(&mut f);
        assert!(f.planes[0].data.iter().all(|v| (v - 77.0).abs() < 1e-3));
    }
}
