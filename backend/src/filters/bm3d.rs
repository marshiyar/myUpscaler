//! Block-matching and 3D filtering (the hard-thresholding "basic estimate" of BM3D, Dabov et al., IEEE TIP 2007) on
//! luma. For each reference block on a grid, the most similar blocks in a search window are stacked into a group,
//! the group is transformed (2D DCT per block, Walsh-Hadamard across the stack), small coefficients are zeroed,
//! and the inverse is aggregated back with a Kaiser window, weighted by the sparsity of the group.

use super::Spatial;
use crate::frame::{Frame, Plane};
use crate::par;

const N: usize = 8;
const AREA: usize = N * N;
/// Reference blocks every STEP pixels.
const STEP: usize = 4;
/// Search window half-size and stride.
const SEARCH: isize = 10;
const SEARCH_STRIDE: isize = 2;
/// Largest group (a power of two).
const MAX_GROUP: usize = 8;
/// Hard threshold in noise standard deviations.
const LAMBDA: f32 = 2.7;

pub struct Bm3d {
    /// `None`: estimate the noise level from each frame.
    pub sigma: Option<f32>,
    dct: [[f32; N]; N],
    kaiser: [f32; AREA],
}

impl Bm3d {
    pub fn new(sigma: Option<f64>) -> Bm3d {
        let mut dct = [[0.0f32; N]; N];
        for (k, row) in dct.iter_mut().enumerate() {
            let a = if k == 0 { (1.0 / N as f64).sqrt() } else { (2.0 / N as f64).sqrt() };
            for (n, v) in row.iter_mut().enumerate() {
                *v = (a * (std::f64::consts::PI * (2 * n + 1) as f64 * k as f64 / (2 * N) as f64).cos()) as f32;
            }
        }
        // Kaiser window, beta = 2.
        let beta = 2.0f64;
        let i0 = |x: f64| {
            let (mut sum, mut term) = (1.0f64, 1.0f64);
            for k in 1..30 {
                term *= (x / 2.0) * (x / 2.0) / (k * k) as f64;
                sum += term;
            }
            sum
        };
        let k1: Vec<f64> = (0..N)
            .map(|i| {
                let r = 2.0 * i as f64 / (N - 1) as f64 - 1.0;
                i0(beta * (1.0 - r * r).max(0.0).sqrt()) / i0(beta)
            })
            .collect();
        let mut kaiser = [0.0f32; AREA];
        for y in 0..N {
            for x in 0..N {
                kaiser[y * N + x] = (k1[y] * k1[x]) as f32;
            }
        }
        Bm3d { sigma: sigma.map(|s| s.clamp(0.1, 50.0) as f32), dct, kaiser }
    }

    fn dct2(&self, block: &mut [f32; AREA], inverse: bool) {
        let mut tmp = [0.0f32; AREA];
        // Rows.
        for y in 0..N {
            for k in 0..N {
                let mut acc = 0.0;
                for n in 0..N {
                    acc += if inverse { self.dct[n][k] * block[y * N + n] } else { self.dct[k][n] * block[y * N + n] };
                }
                tmp[y * N + k] = acc;
            }
        }
        // Columns.
        for x in 0..N {
            for k in 0..N {
                let mut acc = 0.0;
                for n in 0..N {
                    acc += if inverse { self.dct[n][k] * tmp[n * N + x] } else { self.dct[k][n] * tmp[n * N + x] };
                }
                block[k * N + x] = acc;
            }
        }
    }

    fn denoise(&self, src: &Plane, sigma: f32) -> Plane {
        let (w, h) = (src.w, src.h);
        if w < N || h < N {
            return src.clone();
        }
        let grid = |len: usize| {
            let mut v: Vec<usize> = (0..=len - N).step_by(STEP).collect();
            if *v.last().unwrap_or(&0) != len - N {
                v.push(len - N);
            }
            v
        };
        let (xs, ys) = (grid(w), grid(h));
        let threshold = LAMBDA * sigma;
        // Mean squared difference below which a block joins the group: the noise floor plus room for texture.
        let match_limit = 2.0 * sigma * sigma + 400.0;

        // Each worker aggregates a band of reference rows into its own buffers (band rows plus the block height).
        let bands = par::threads().min(ys.len()).max(1);
        let per = ys.len().div_ceil(bands);
        let partials = par::map(bands, |b| {
            let refs = &ys[(b * per).min(ys.len())..((b + 1) * per).min(ys.len())];
            let (Some(&first), Some(&last)) = (refs.first(), refs.last()) else { return (0, Vec::new(), Vec::new()) };
            // Matched blocks lie within SEARCH rows of their reference block.
            let top = first.saturating_sub(SEARCH as usize);
            let rows = (last + N + SEARCH as usize).min(h) - top;
            let mut num = vec![0.0f32; rows * w];
            let mut den = vec![0.0f32; rows * w];
            let mut candidates: Vec<(f32, usize, usize)> = Vec::new();
            let mut group = vec![[0.0f32; AREA]; MAX_GROUP];
            for &ry in refs {
                for &rx in &xs {
                    candidates.clear();
                    let y_lo = (ry as isize - SEARCH).max(0);
                    let y_hi = (ry as isize + SEARCH).min((h - N) as isize);
                    let x_lo = (rx as isize - SEARCH).max(0);
                    let x_hi = (rx as isize + SEARCH).min((w - N) as isize);
                    let mut cy = y_lo;
                    while cy <= y_hi {
                        let mut cx = x_lo;
                        while cx <= x_hi {
                            let (cx_u, cy_u) = (cx as usize, cy as usize);
                            let mut ssd = 0.0f32;
                            for j in 0..N {
                                let a = &src.data[(ry + j) * w + rx..(ry + j) * w + rx + N];
                                let b = &src.data[(cy_u + j) * w + cx_u..(cy_u + j) * w + cx_u + N];
                                for i in 0..N {
                                    let d = a[i] - b[i];
                                    ssd += d * d;
                                }
                            }
                            let msd = ssd / AREA as f32;
                            if msd <= match_limit && !(cx_u == rx && cy_u == ry) {
                                candidates.push((msd, cx_u, cy_u));
                            }
                            cx += SEARCH_STRIDE;
                        }
                        cy += SEARCH_STRIDE;
                    }
                    candidates.sort_by(|a, b| a.0.total_cmp(&b.0));
                    // The reference block always leads its group.
                    candidates.insert(0, (0.0, rx, ry));
                    let mut size = 1;
                    while size * 2 <= candidates.len().min(MAX_GROUP) {
                        size *= 2;
                    }
                    for (g, &(_, bx, by)) in candidates.iter().take(size).enumerate() {
                        for j in 0..N {
                            group[g][j * N..(j + 1) * N]
                                .copy_from_slice(&src.data[(by + j) * w + bx..(by + j) * w + bx + N]);
                        }
                        self.dct2(&mut group[g], false);
                    }
                    walsh_hadamard(&mut group[..size]);
                    let mut kept = 0usize;
                    for block in group[..size].iter_mut() {
                        for c in block.iter_mut() {
                            if c.abs() < threshold {
                                *c = 0.0;
                            } else {
                                kept += 1;
                            }
                        }
                    }
                    walsh_hadamard(&mut group[..size]);
                    let weight = 1.0 / kept.max(1) as f32;
                    for (g, &(_, bx, by)) in candidates.iter().take(size).enumerate() {
                        self.dct2(&mut group[g], true);
                        for j in 0..N {
                            let row = by + j - top;
                            for i in 0..N {
                                let k = self.kaiser[j * N + i] * weight;
                                num[row * w + bx + i] += k * group[g][j * N + i];
                                den[row * w + bx + i] += k;
                            }
                        }
                    }
                }
            }
            (top, num, den)
        });

        let mut num = vec![0.0f32; w * h];
        let mut den = vec![0.0f32; w * h];
        for (top, n, d) in partials {
            for (i, (nv, dv)) in n.iter().zip(&d).enumerate() {
                num[top * w + i] += nv;
                den[top * w + i] += dv;
            }
        }
        let mut out = src.clone();
        for ((o, n), d) in out.data.iter_mut().zip(&num).zip(&den) {
            if *d > 0.0 {
                *o = n / d;
            }
        }
        out
    }
}

/// In-place orthonormal Walsh-Hadamard transform across the blocks of a group (length a power of two). It is its
/// own inverse.
fn walsh_hadamard(group: &mut [[f32; AREA]]) {
    let n = group.len();
    if n < 2 {
        return;
    }
    let mut len = 1;
    while len < n {
        for start in (0..n).step_by(len * 2) {
            for k in start..start + len {
                let (lo, hi) = group.split_at_mut(k + len);
                let (a, b) = (&mut lo[k], &mut hi[0]);
                for i in 0..AREA {
                    let (x, y) = (a[i], b[i]);
                    a[i] = x + y;
                    b[i] = x - y;
                }
            }
        }
        len *= 2;
    }
    let scale = 1.0 / (n as f32).sqrt();
    for block in group.iter_mut() {
        block.iter_mut().for_each(|v| *v *= scale);
    }
}

/// Noise standard deviation from the median absolute diagonal detail of 2x2 cells (Donoho's MAD estimator).
pub fn estimate_sigma(p: &Plane) -> f32 {
    let mut details = Vec::with_capacity((p.w / 2) * (p.h / 2));
    let stride = if p.w * p.h > 1_000_000 { 4 } else { 2 };
    for y in (0..p.h.saturating_sub(1)).step_by(stride) {
        for x in (0..p.w.saturating_sub(1)).step_by(stride) {
            let d = (p.at(x, y) - p.at(x + 1, y) - p.at(x, y + 1) + p.at(x + 1, y + 1)) * 0.5;
            details.push(d.abs());
        }
    }
    if details.is_empty() {
        return 1.0;
    }
    let mid = details.len() / 2;
    let (_, median, _) = details.select_nth_unstable_by(mid, |a, b| a.total_cmp(b));
    (*median / 0.6745).clamp(0.5, 30.0)
}

impl Spatial for Bm3d {
    fn describe(&self) -> String {
        match self.sigma {
            Some(s) => format!("bm3d(sigma={s:.2})"),
            None => "bm3d(sigma=auto)".into(),
        }
    }

    fn apply(&mut self, frame: &mut Frame) {
        let sigma = self.sigma.unwrap_or_else(|| estimate_sigma(&frame.planes[0]));
        frame.planes[0] = self.denoise(&frame.planes[0], sigma);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::{clean, frame, rms};

    #[test]
    fn dct_round_trip() {
        let f = Bm3d::new(Some(1.0));
        let mut b = [0.0f32; AREA];
        for (i, v) in b.iter_mut().enumerate() {
            *v = (i * 31 % 17) as f32;
        }
        let orig = b;
        f.dct2(&mut b, false);
        f.dct2(&mut b, true);
        for (a, c) in b.iter().zip(&orig) {
            assert!((a - c).abs() < 1e-3);
        }
    }

    #[test]
    fn hadamard_is_involution() {
        let mut g = vec![[0.0f32; AREA]; 4];
        for (k, b) in g.iter_mut().enumerate() {
            b[0] = k as f32 + 1.0;
            b[5] = (k * k) as f32;
        }
        let orig = g.clone();
        walsh_hadamard(&mut g);
        walsh_hadamard(&mut g);
        for (a, b) in g.iter().zip(&orig) {
            assert!((a[0] - b[0]).abs() < 1e-4 && (a[5] - b[5]).abs() < 1e-4);
        }
    }

    #[test]
    fn reduces_noise() {
        let truth = clean(96, 64);
        let mut f = frame(96, 64, 12.0, 3, 0.0);
        let before = rms(&f.planes[0], &truth.planes[0]);
        Bm3d::new(Some(7.0)).apply(&mut f);
        let after = rms(&f.planes[0], &truth.planes[0]);
        assert!(after < before * 0.6, "{before} -> {after}");
    }

    #[test]
    fn estimates_noise_level() {
        // Uniform noise of amplitude 12 has standard deviation 12 / sqrt(3).
        let f = frame(256, 256, 12.0, 9, 0.0);
        let s = estimate_sigma(&f.planes[0]);
        assert!((4.0..10.0).contains(&s), "{s}");
    }
}
