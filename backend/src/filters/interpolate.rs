//! Retiming to a constant output frame rate, with three ways to make the frames between two source frames:
//!
//! - `dup`: repeat the earlier frame;
//! - `blend`: cross-fade the two frames;
//! - `mci`: motion-compensated interpolation. Motion is estimated symmetrically around the midpoint between the two
//!   frames: forward and backward block matching on a three-level pyramid give real motion candidates, and each
//!   block of the midpoint frame takes the candidate (its own or a neighbour's) that best explains its path. Each output pixel then mixes the predictions of its four nearest block vectors,
//!   weighted by distance and by how well each vector makes the two frames agree there (overlapped-block motion
//!   compensation). Blocks the motion does not explain fall back to blending, and scene cuts
//!   repeat the nearest frame instead of morphing.
//!
//! Timestamps come from the input frames, so frames dropped upstream (decimation) or variable-rate sources are
//! regenerated on the output grid.

use super::Filter;
use crate::frame::{Frame, Plane};
use crate::par;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Dup,
    Blend,
    Mci,
}

impl Mode {
    pub fn parse(s: &str) -> Mode {
        match s {
            "dup" => Mode::Dup,
            "blend" => Mode::Blend,
            _ => Mode::Mci,
        }
    }
}

pub struct Retimer {
    mode: Mode,
    out_fps: f64,
    /// Duration of the last input frame, used to finish the output after the final frame.
    src_frame_duration: f64,
    start: Option<f64>,
    next_index: u64,
    prev: Option<Frame>,
    motion: Option<MotionField>,
    emitted: u64,
}

const BLOCK: usize = 16;
/// Mean absolute luma difference (code values) above which two frames are treated as a scene cut.
const SCENE_CUT: f32 = 28.0;
/// Mean absolute matching error per pixel above which a block's motion is not trusted.
const UNRELIABLE: f32 = 14.0;

impl Retimer {
    pub fn new(mode: Mode, out_fps: f64, src_fps: f64) -> Retimer {
        let src = if src_fps > 0.0 { src_fps } else { out_fps };
        Retimer {
            mode,
            out_fps,
            src_frame_duration: 1.0 / src,
            start: None,
            next_index: 0,
            prev: None,
            motion: None,
            emitted: 0,
        }
    }

    pub fn emitted(&self) -> u64 {
        self.emitted
    }

    fn time(&self, index: u64) -> f64 {
        self.start.unwrap_or(0.0) + index as f64 / self.out_fps
    }

    fn emit(&mut self, mut f: Frame, out: &mut Vec<Frame>) {
        f.pts = self.time(self.next_index);
        self.next_index += 1;
        self.emitted += 1;
        out.push(f);
    }

    fn between(&mut self, prev: &Frame, cur: &Frame, t: f64) -> Frame {
        let span = cur.pts - prev.pts;
        let alpha = if span > 0.0 { ((t - prev.pts) / span) as f32 } else { 0.0 };
        if alpha <= 1e-3 || self.mode == Mode::Dup {
            return prev.clone();
        }
        if alpha >= 1.0 - 1e-3 {
            return cur.clone();
        }
        if prev.width() != cur.width() || prev.height() != cur.height() {
            return if alpha < 0.5 { prev.clone() } else { cur.clone() };
        }
        if self.mode == Mode::Blend {
            return blend(prev, cur, alpha);
        }
        if self.motion.is_none() {
            let m = MotionField::estimate(&prev.planes[0], &cur.planes[0]);
            self.motion = Some(m);
        }
        let m = self.motion.as_ref().map(|m| (m.scene_cut, m));
        match m {
            Some((true, _)) | None => {
                if alpha < 0.5 {
                    prev.clone()
                } else {
                    cur.clone()
                }
            }
            Some((false, m)) => m.interpolate(prev, cur, alpha),
        }
    }
}

impl Filter for Retimer {
    fn describe(&self) -> String {
        let mode = match self.mode {
            Mode::Dup => "dup",
            Mode::Blend => "blend",
            Mode::Mci => "mci",
        };
        format!("retime({mode}, {:.3} fps)", self.out_fps)
    }

    fn push(&mut self, frame: Frame, out: &mut Vec<Frame>) {
        let Some(prev) = self.prev.take() else {
            self.start = Some(frame.pts);
            self.prev = Some(frame);
            return;
        };
        self.motion = None;
        while self.time(self.next_index) < frame.pts - 1e-9 {
            let t = self.time(self.next_index);
            let f = self.between(&prev, &frame, t);
            self.emit(f, out);
        }
        self.prev = Some(frame);
    }

    fn flush(&mut self, out: &mut Vec<Frame>) {
        if let Some(last) = self.prev.take() {
            let end = last.pts + self.src_frame_duration;
            loop {
                let t = self.time(self.next_index);
                // Always emit at least one frame for the final input frame.
                if t >= end - 1e-9 && t > last.pts + 1e-9 {
                    break;
                }
                self.emit(last.clone(), out);
            }
        }
    }
}

fn blend(a: &Frame, b: &Frame, alpha: f32) -> Frame {
    let mut out = a.clone();
    for (o, p) in out.planes.iter_mut().zip(&b.planes) {
        for (x, y) in o.data.iter_mut().zip(&p.data) {
            *x += (y - *x) * alpha;
        }
    }
    if let (Some(o), Some(p)) = (out.alpha.as_mut(), b.alpha.as_ref()) {
        for (x, y) in o.data.iter_mut().zip(&p.data) {
            *x += (y - *x) * alpha;
        }
    }
    out
}

/// Motion per block of the midpoint frame: the content of block (bx, by) moves by `v` from the earlier frame to the
/// later one, passing through the block halfway.
struct MotionField {
    cols: usize,
    rows: usize,
    v: Vec<(f32, f32)>,
    scene_cut: bool,
}

impl MotionField {
    fn estimate(a: &Plane, b: &Plane) -> MotionField {
        let mad = a.data.iter().zip(&b.data).map(|(x, y)| (x - y).abs()).sum::<f32>() / a.data.len().max(1) as f32;
        let cols = a.w.div_ceil(BLOCK);
        let rows = a.h.div_ceil(BLOCK);
        if mad > SCENE_CUT {
            return MotionField { cols, rows, v: vec![(0.0, 0.0); cols * rows], scene_cut: true };
        }
        // Anchored searches are unambiguous: a block of real content is looked for in the other frame. Forward
        // vectors anchor blocks in the earlier frame, backward vectors in the later one.
        let forward = anchored_motion(a, b, cols, rows);
        let backward: Vec<(i32, i32)> = anchored_motion(b, a, cols, rows).into_iter().map(|(x, y)| (-x, -y)).collect();
        // Each block of the midpoint frame picks, among the anchored vectors of itself and its neighbours (and no
        // motion), the one that makes the two frames agree best along its path through the block.
        let v = par::map(rows, |r| {
            (0..cols)
                .map(|c| {
                    let (x0, y0) = ((c * BLOCK) as i32, (r * BLOCK) as i32);
                    let mut best = (path_cost(a, b, x0, y0, BLOCK, (0, 0)), (0, 0));
                    for dr in -1i32..=1 {
                        for dc in -1i32..=1 {
                            let (rr, cc) = (r as i32 + dr, c as i32 + dc);
                            if rr < 0 || cc < 0 || rr as usize >= rows || cc as usize >= cols {
                                continue;
                            }
                            let i = rr as usize * cols + cc as usize;
                            for cand in [forward[i], backward[i]] {
                                let cost = path_cost(a, b, x0, y0, BLOCK, cand);
                                if cost < best.0 {
                                    best = (cost, cand);
                                }
                            }
                        }
                    }
                    best.1
                })
                .collect::<Vec<_>>()
        })
        .into_iter()
        .flatten()
        .collect::<Vec<_>>();
        MotionField { cols, rows, v: v.iter().map(|p| (p.0 as f32, p.1 as f32)).collect(), scene_cut: false }
    }

    /// The four blocks whose centres surround pixel (x, y), with their bilinear weights.
    #[inline]
    fn neighbours(&self, x: usize, y: usize) -> [((f32, f32), f32); 4] {
        let fx = ((x as f32 + 0.5) / BLOCK as f32 - 0.5).clamp(0.0, (self.cols - 1) as f32);
        let fy = ((y as f32 + 0.5) / BLOCK as f32 - 0.5).clamp(0.0, (self.rows - 1) as f32);
        let (c0, r0) = (fx as usize, fy as usize);
        let (c1, r1) = ((c0 + 1).min(self.cols - 1), (r0 + 1).min(self.rows - 1));
        let (tx, ty) = (fx - c0 as f32, fy - r0 as f32);
        let at = |c: usize, r: usize| self.v[r * self.cols + c];
        [
            (at(c0, r0), (1.0 - tx) * (1.0 - ty)),
            (at(c1, r0), tx * (1.0 - ty)),
            (at(c0, r1), (1.0 - tx) * ty),
            (at(c1, r1), tx * ty),
        ]
    }

    /// Overlapped-block motion compensation. Each output pixel mixes the predictions made with the vectors of the
    /// four nearest blocks, weighted by distance to the block centres and by how well each vector makes the two
    /// frames agree at that pixel, so object boundaries follow the vector that explains them. Where no vector
    /// explains a pixel (occlusions), it falls back to a cross-fade.
    fn interpolate(&self, prev: &Frame, cur: &Frame, alpha: f32) -> Frame {
        let (w, h) = (prev.width(), prev.height());
        let has_alpha = prev.alpha.is_some() && cur.alpha.is_some();
        let channels = if has_alpha { 4 } else { 3 };
        let source = |f: &Frame, k: usize| -> Plane {
            if k < 3 {
                f.planes[k].clone()
            } else {
                f.alpha.clone().unwrap_or_else(|| Plane::new(w, h, 255.0))
            }
        };
        let (pa, pb): (Vec<Plane>, Vec<Plane>) = (0..channels).map(|k| (source(prev, k), source(cur, k))).unzip();
        let rows = par::map(h, |y| {
            let mut line = vec![0.0f32; w * channels];
            for x in 0..w {
                let (xf, yf) = (x as f32, y as f32);
                let mut acc = [0.0f32; 4];
                let mut total = 0.0f32;
                let mut best_err = f32::MAX;
                // Neighbouring blocks usually share a vector: predict once per distinct vector.
                let mut distinct: [((f32, f32), f32); 4] = [((0.0, 0.0), 0.0); 4];
                let mut count = 0;
                for (vector, bw) in self.neighbours(x, y) {
                    match distinct[..count].iter_mut().find(|(v, _)| *v == vector) {
                        Some(entry) => entry.1 += bw,
                        None => {
                            distinct[count] = (vector, bw);
                            count += 1;
                        }
                    }
                }
                for &((mx, my), bw) in &distinct[..count] {
                    if bw <= 0.0 {
                        continue;
                    }
                    let (ax, ay) = (xf - alpha * mx, yf - alpha * my);
                    let (bx, by) = (xf + (1.0 - alpha) * mx, yf + (1.0 - alpha) * my);
                    let la = pa[0].bilinear(ax, ay);
                    let lb = pb[0].bilinear(bx, by);
                    let err = (la - lb).abs();
                    best_err = best_err.min(err);
                    let wgt = bw / (1.0 + (err / 6.0) * (err / 6.0));
                    total += wgt;
                    for k in 0..channels {
                        let (va, vb) = if k == 0 { (la, lb) } else { (pa[k].bilinear(ax, ay), pb[k].bilinear(bx, by)) };
                        acc[k] += wgt * (va + (vb - va) * alpha);
                    }
                }
                let fallback = ((best_err - UNRELIABLE * 0.5) / UNRELIABLE).clamp(0.0, 1.0);
                for k in 0..channels {
                    let mc = if total > 0.0 { acc[k] / total } else { pa[k].at(x, y) };
                    let plain = pa[k].at(x, y) + (pb[k].at(x, y) - pa[k].at(x, y)) * alpha;
                    line[x * channels + k] = mc + (plain - mc) * fallback;
                }
            }
            line
        });
        let mut out = prev.clone();
        for (y, line) in rows.into_iter().enumerate() {
            for x in 0..w {
                for k in 0..3 {
                    out.planes[k].data[y * w + x] = line[x * channels + k];
                }
                if let (true, Some(a)) = (has_alpha, out.alpha.as_mut()) {
                    a.data[y * w + x] = line[x * channels + 3];
                }
            }
        }
        out
    }
}

/// Sum of absolute differences between the block of `a` at (ax, ay) and the block of `b` at (bx, by), with
/// clamped coordinates at the borders.
#[inline]
#[allow(clippy::too_many_arguments)]
fn sad(a: &Plane, ax: i32, ay: i32, b: &Plane, bx: i32, by: i32, block: usize) -> f32 {
    let inside = |p: &Plane, x: i32, y: i32| {
        x >= 0 && y >= 0 && x + block as i32 <= p.w as i32 && y + block as i32 <= p.h as i32
    };
    let mut total = 0.0f32;
    if inside(a, ax, ay) && inside(b, bx, by) {
        for j in 0..block {
            let ra = &a.data[(ay as usize + j) * a.w + ax as usize..][..block];
            let rb = &b.data[(by as usize + j) * b.w + bx as usize..][..block];
            total += ra.iter().zip(rb).map(|(p, q)| (p - q).abs()).sum::<f32>();
        }
    } else {
        for j in 0..block as i32 {
            for i in 0..block as i32 {
                let p = a.clamped((ax + i) as isize, (ay + j) as isize);
                let q = b.clamped((bx + i) as isize, (by + j) as isize);
                total += (p - q).abs();
            }
        }
    }
    total
}

/// Cost of motion `m` for the midpoint block at (x0, y0): the block's path starts at -m/2 in `a` and ends at +m/2
/// in `b` (odd components split one pixel unevenly), plus a slight preference for short vectors.
#[inline]
fn path_cost(a: &Plane, b: &Plane, x0: i32, y0: i32, block: usize, m: (i32, i32)) -> f32 {
    let (hx, hy) = (m.0.div_euclid(2), m.1.div_euclid(2));
    sad(a, x0 - hx, y0 - hy, b, x0 + m.0 - hx, y0 + m.1 - hy, block) + length_penalty(m, block)
}

#[inline]
fn length_penalty(m: (i32, i32), block: usize) -> f32 {
    0.01 * ((m.0 * m.0 + m.1 * m.1) as f32).sqrt() * (block * block) as f32
}

/// Block motion from `a` to `b` for blocks anchored in `a`, searched coarse to fine on a three-level pyramid.
fn anchored_motion(a: &Plane, b: &Plane, cols: usize, rows: usize) -> Vec<(i32, i32)> {
    let a1 = downsample(a);
    let b1 = downsample(b);
    let a2 = downsample(&a1);
    let b2 = downsample(&b1);
    let mut v = vec![(0i32, 0i32); cols * rows];
    for (level, (pa, pb), radius) in [(2u32, (&a2, &b2), 8i32), (1, (&a1, &b1), 2), (0, (a, b), 2)] {
        let scale = 1usize << level;
        let block = (BLOCK / scale).max(2);
        let prior = v.clone();
        v = par::map(rows, |r| {
            (0..cols)
                .map(|c| {
                    let (px, py) = prior[r * cols + c];
                    // Vectors from the coarser level double at each finer level.
                    let centre = if level == 2 { (0, 0) } else { (px * 2, py * 2) };
                    let (x0, y0) = ((c * BLOCK / scale) as i32, (r * BLOCK / scale) as i32);
                    let mut best = (f32::MAX, centre);
                    for dy in -radius..=radius {
                        for dx in -radius..=radius {
                            let m = (centre.0 + dx, centre.1 + dy);
                            let cost = sad(pa, x0, y0, pb, x0 + m.0, y0 + m.1, block) + length_penalty(m, block);
                            if cost < best.0 {
                                best = (cost, m);
                            }
                        }
                    }
                    best.1
                })
                .collect::<Vec<_>>()
        })
        .into_iter()
        .flatten()
        .collect();
    }
    v
}

fn downsample(p: &Plane) -> Plane {
    let (w, h) = (p.w.div_ceil(2).max(1), p.h.div_ceil(2).max(1));
    let mut out = Plane::new(w, h, 0.0);
    for y in 0..h {
        for x in 0..w {
            let (sx, sy) = ((x * 2) as isize, (y * 2) as isize);
            out.data[y * w + x] =
                (p.clamped(sx, sy) + p.clamped(sx + 1, sy) + p.clamped(sx, sy + 1) + p.clamped(sx + 1, sy + 1)) * 0.25;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A textured square on a gradient, displaced by `shift` pixels to the right.
    pub(super) fn scene(w: usize, h: usize, shift: f32, pts: f64) -> Frame {
        let mut y = Plane::new(w, h, 0.0);
        for yy in 0..h {
            for xx in 0..w {
                let x = xx as f32 - shift;
                let inside = (20.0..44.0).contains(&x) && (16..40).contains(&yy);
                let tex = ((x * 0.7).sin() * 20.0 + (yy as f32 * 0.9).cos() * 20.0) * f32::from(u8::from(inside));
                y.data[yy * w + xx] = 40.0 + xx as f32 * 0.5 + if inside { 120.0 + tex } else { 0.0 };
            }
        }
        Frame { planes: [y, Plane::new(w, h, 128.0), Plane::new(w, h, 128.0)], alpha: None, pts }
    }

    #[test]
    fn doubles_the_frame_rate() {
        let mut r = Retimer::new(Mode::Blend, 2.0, 1.0);
        let mut out = Vec::new();
        for i in 0..3 {
            r.push(scene(32, 32, 0.0, i as f64), &mut out);
        }
        r.flush(&mut out);
        assert_eq!(out.iter().map(|f| f.pts).collect::<Vec<_>>(), vec![0.0, 0.5, 1.0, 1.5, 2.0, 2.5]);
    }

    #[test]
    fn fills_gaps_left_by_decimation() {
        let mut r = Retimer::new(Mode::Dup, 10.0, 10.0);
        let mut out = Vec::new();
        r.push(scene(16, 16, 0.0, 0.0), &mut out);
        r.push(scene(16, 16, 0.0, 0.3), &mut out);
        r.flush(&mut out);
        assert_eq!(out.len(), 4);
    }

    #[test]
    fn motion_compensation_beats_blending() {
        let (a, b) = (scene(96, 64, 0.0, 0.0), scene(96, 64, 8.0, 1.0));
        let truth = scene(96, 64, 4.0, 0.5);
        let m = MotionField::estimate(&a.planes[0], &b.planes[0]);
        assert!(!m.scene_cut);
        let mc = m.interpolate(&a, &b, 0.5);
        let bl = blend(&a, &b, 0.5);
        let err = |f: &Frame| crate::filters::testutil::rms(&f.planes[0], &truth.planes[0]);
        assert!(err(&mc) < err(&bl) * 0.5, "mci {} vs blend {}", err(&mc), err(&bl));
    }

    #[test]
    fn scene_cuts_are_not_morphed() {
        let a = scene(64, 64, 0.0, 0.0);
        let mut b = scene(64, 64, 0.0, 1.0);
        b.planes[0].data.iter_mut().for_each(|v| *v = 255.0 - *v);
        let mut r = Retimer::new(Mode::Mci, 4.0, 1.0);
        let mut out = Vec::new();
        r.push(a.clone(), &mut out);
        r.push(b, &mut out);
        assert_eq!(out.len(), 4);
        assert_eq!(out[1].planes[0], a.planes[0]);
    }
}
