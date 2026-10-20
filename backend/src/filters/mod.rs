//! The restoration filters. Each one consumes frames and produces frames; temporal filters hold frames back and
//! release them on `flush`. A `Chain` runs them in order.

pub mod atadenoise;
pub mod bm3d;
pub mod deband;
pub mod deblock;
pub mod decimate;
pub mod eq;
pub mod grain;
pub mod hqdn3d;
pub mod interpolate;
pub mod nlmeans;
pub mod scale;
pub mod sharpen;

use crate::frame::{Frame, Plane};
use crate::par;

pub trait Filter: Send {
    /// Short description for the log, such as `hqdn3d(4.00:3.00:6.00:4.50)`.
    fn describe(&self) -> String;
    fn push(&mut self, frame: Frame, out: &mut Vec<Frame>);
    fn flush(&mut self, _out: &mut Vec<Frame>) {}
}

/// A filter that changes each frame on its own.
pub trait Spatial: Send {
    fn describe(&self) -> String;
    fn apply(&mut self, frame: &mut Frame);
}

impl<T: Spatial> Filter for T {
    fn describe(&self) -> String {
        Spatial::describe(self)
    }

    fn push(&mut self, mut frame: Frame, out: &mut Vec<Frame>) {
        self.apply(&mut frame);
        out.push(frame);
    }
}

#[derive(Default)]
pub struct Chain {
    stages: Vec<Box<dyn Filter>>,
    /// Time spent in each stage.
    spent: Vec<std::time::Duration>,
}

impl Chain {
    pub fn push_stage(&mut self, filter: Box<dyn Filter>) {
        self.stages.push(filter);
        self.spent.push(std::time::Duration::ZERO);
    }

    pub fn push_some(&mut self, filter: Option<Box<dyn Filter>>) {
        if let Some(f) = filter {
            self.push_stage(f);
        }
    }

    /// Seconds spent in each stage so far, with the stage's description.
    pub fn timings(&self) -> Vec<(String, f64)> {
        self.stages.iter().zip(&self.spent).map(|(s, t)| (s.describe(), t.as_secs_f64())).collect()
    }

    pub fn is_empty(&self) -> bool {
        self.stages.is_empty()
    }

    pub fn describe(&self) -> String {
        if self.stages.is_empty() {
            return "(none)".into();
        }
        self.stages.iter().map(|s| s.describe()).collect::<Vec<_>>().join(" -> ")
    }

    /// Runs one frame through every stage; returns the frames that left the last stage.
    pub fn push(&mut self, frame: Frame) -> Vec<Frame> {
        self.run_from(0, vec![frame])
    }

    /// Drains every stage in order.
    pub fn flush(&mut self) -> Vec<Frame> {
        let mut done = Vec::new();
        for i in 0..self.stages.len() {
            let mut held = Vec::new();
            let start = std::time::Instant::now();
            self.stages[i].flush(&mut held);
            self.spent[i] += start.elapsed();
            done.extend(self.run_from(i + 1, held));
        }
        done
    }

    fn run_from(&mut self, first: usize, mut frames: Vec<Frame>) -> Vec<Frame> {
        for (stage, spent) in self.stages.iter_mut().zip(self.spent.iter_mut()).skip(first) {
            let start = std::time::Instant::now();
            let mut next = Vec::with_capacity(frames.len());
            for f in frames {
                stage.push(f, &mut next);
            }
            *spent += start.elapsed();
            frames = next;
        }
        frames
    }
}

/// Which planes a filter touches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Planes {
    Luma,
    All,
}

impl Planes {
    pub fn includes(self, index: usize) -> bool {
        self == Planes::All || index == 0
    }
}

/// Separable box sum of radius `r` (window 2r+1) with clamped edges, as a new plane of sums.
pub fn box_sum(p: &Plane, r: usize) -> Plane {
    let (w, h) = (p.w, p.h);
    let mut tmp = Plane::new(w, h, 0.0);
    par::for_each_row(&mut tmp.data, w, |y, row| {
        let src = p.row(y);
        let ri = r as isize;
        let mut acc: f32 = (-ri..=ri).map(|dx| src[dx.clamp(0, w as isize - 1) as usize]).sum();
        for (x, o) in row.iter_mut().enumerate() {
            *o = acc;
            let leave = (x as isize - ri).clamp(0, w as isize - 1) as usize;
            let enter = (x as isize + ri + 1).clamp(0, w as isize - 1) as usize;
            acc += src[enter] - src[leave];
        }
    });
    let mut out = Plane::new(w, h, 0.0);
    // Vertical pass by row bands: each band recomputes its running sums from the column tops it needs.
    par::for_each_row_chunk(&mut out.data, w, |y0, band| {
        let rows = band.len() / w;
        let ri = r as isize;
        let mut acc = vec![0.0f32; w];
        for dy in -ri..=ri {
            let yy = (y0 as isize + dy).clamp(0, h as isize - 1) as usize;
            for (a, v) in acc.iter_mut().zip(tmp.row(yy)) {
                *a += v;
            }
        }
        for i in 0..rows {
            let y = y0 + i;
            band[i * w..(i + 1) * w].copy_from_slice(&acc);
            let leave = (y as isize - ri).clamp(0, h as isize - 1) as usize;
            let enter = (y as isize + ri + 1).clamp(0, h as isize - 1) as usize;
            let (lr, er) = (tmp.row(leave), tmp.row(enter));
            for x in 0..w {
                acc[x] += er[x] - lr[x];
            }
        }
    });
    out
}

/// Parses a decimal option such as `"2.5"`; `None` for empty or invalid text.
pub fn number(s: &str) -> Option<f64> {
    let t = s.trim();
    if t.is_empty() {
        return None;
    }
    t.parse::<f64>().ok().filter(|v| v.is_finite())
}

#[cfg(test)]
pub(crate) mod testutil {
    use crate::frame::{Frame, Plane};

    /// A smooth test image with a few edges, plus deterministic noise of the given amplitude.
    pub fn frame(w: usize, h: usize, noise: f32, seed: u32, pts: f64) -> Frame {
        let mut planes = [Plane::new(w, h, 0.0), Plane::new(w, h, 128.0), Plane::new(w, h, 128.0)];
        for y in 0..h {
            for x in 0..w {
                let base = 60.0 + 100.0 * (x as f32 / w as f32) + if (x / 16 + y / 16) % 2 == 0 { 30.0 } else { 0.0 };
                let n = (crate::frame::unit(crate::frame::hash3(x as u32, y as u32, seed)) - 0.5) * 2.0 * noise;
                planes[0].data[y * w + x] = base + n;
                planes[1].data[y * w + x] = 128.0 + 20.0 * (y as f32 / h as f32) + n * 0.5;
                planes[2].data[y * w + x] = 120.0 + n * 0.5;
            }
        }
        Frame { planes, alpha: None, pts }
    }

    pub fn clean(w: usize, h: usize) -> Frame {
        frame(w, h, 0.0, 0, 0.0)
    }

    /// Root-mean-square difference between two luma planes.
    pub fn rms(a: &Plane, b: &Plane) -> f32 {
        let sum: f32 = a.data.iter().zip(&b.data).map(|(x, y)| (x - y) * (x - y)).sum();
        (sum / a.data.len() as f32).sqrt()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn box_sum_matches_direct_sum() {
        let mut p = Plane::new(9, 7, 0.0);
        for (i, v) in p.data.iter_mut().enumerate() {
            *v = (i * 37 % 11) as f32;
        }
        let s = box_sum(&p, 2);
        for y in 0..7isize {
            for x in 0..9isize {
                let mut direct = 0.0;
                for dy in -2..=2 {
                    for dx in -2..=2 {
                        direct += p.clamped(x + dx, y + dy);
                    }
                }
                assert!((s.at(x as usize, y as usize) - direct).abs() < 1e-3);
            }
        }
    }

    #[test]
    fn number_parsing() {
        assert_eq!(number(" 2.5 "), Some(2.5));
        assert_eq!(number(""), None);
        assert_eq!(number("auto"), None);
    }
}
