//! Adaptive temporal averaging: each pixel is averaged with the same pixel in neighbouring frames, walking outwards
//! from the current frame in both directions and stopping as soon as a frame differs too much (threshold A) or the
//! accumulated difference grows too large (threshold B). Static areas are averaged over the whole window; motion
//! stops the walk early, so moving edges do not ghost.

use std::collections::VecDeque;

use super::Filter;
use crate::frame::{Frame, Plane};
use crate::par;

pub struct AtaDenoise {
    /// Frames in the window (odd).
    pub frames: usize,
    /// Thresholds A and B in code values for luma and chroma.
    pub luma: (f32, f32),
    pub chroma: (f32, f32),
    window: VecDeque<Frame>,
    /// Index in `window` of the next frame to emit.
    next: usize,
}

impl AtaDenoise {
    /// `frames` is rounded to an odd count in 3..=21; `a` and `b` are luma thresholds as fractions of the range.
    pub fn new(frames: f64, a: f64, b: f64) -> AtaDenoise {
        let n = (frames.round().clamp(3.0, 21.0) as usize) | 1;
        AtaDenoise {
            frames: n,
            luma: ((a * 255.0) as f32, (b * 255.0) as f32),
            chroma: (0.02 * 255.0, 0.04 * 255.0),
            window: VecDeque::new(),
            next: 0,
        }
    }

    fn half(&self) -> usize {
        self.frames / 2
    }

    fn filter_frame(&self, centre: usize) -> Frame {
        let mut out = self.window[centre].clone();
        let n = self.window.len();
        for (pi, dst) in out.planes.iter_mut().enumerate() {
            let (ta, tb) = if pi == 0 { self.luma } else { self.chroma };
            let planes: Vec<&Plane> = self.window.iter().map(|f| &f.planes[pi]).collect();
            let half = self.half();
            let w = dst.w;
            par::for_each_row(&mut dst.data, w, |y, row| {
                let base = y * w;
                for (x, v) in row.iter_mut().enumerate() {
                    let c = planes[centre].data[base + x];
                    let (mut acc, mut count) = (c, 1.0f32);
                    for dir in [-1isize, 1] {
                        let mut sum = 0.0f32;
                        for k in 1..=half as isize {
                            let j = centre as isize + dir * k;
                            if j < 0 || j >= n as isize {
                                break;
                            }
                            let s = planes[j as usize].data[base + x];
                            let d = (s - c).abs();
                            sum += d;
                            if d > ta || sum > tb {
                                break;
                            }
                            acc += s;
                            count += 1.0;
                        }
                    }
                    *v = acc / count;
                }
            });
        }
        out
    }

    fn emit_ready(&mut self, out: &mut Vec<Frame>, flushing: bool) {
        while self.next < self.window.len() && (flushing || self.window.len() - self.next > self.half()) {
            out.push(self.filter_frame(self.next));
            self.next += 1;
            // Keep `half` frames of history behind the next frame.
            while self.next > self.half() {
                self.window.pop_front();
                self.next -= 1;
            }
        }
    }
}

impl Filter for AtaDenoise {
    fn describe(&self) -> String {
        format!("atadenoise(frames={}, a={:.1}, b={:.1})", self.frames, self.luma.0, self.luma.1)
    }

    fn push(&mut self, frame: Frame, out: &mut Vec<Frame>) {
        if let Some(last) = self.window.back() {
            if last.width() != frame.width() || last.height() != frame.height() {
                self.emit_ready(out, true);
                self.window.clear();
                self.next = 0;
            }
        }
        self.window.push_back(frame);
        self.emit_ready(out, false);
    }

    fn flush(&mut self, out: &mut Vec<Frame>) {
        self.emit_ready(out, true);
        self.window.clear();
        self.next = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::{clean, frame, rms};

    #[test]
    fn emits_every_frame_in_order() {
        let mut f = AtaDenoise::new(9.0, 0.02, 0.04);
        let mut out = Vec::new();
        for i in 0..12 {
            f.push(frame(16, 8, 3.0, i, i as f64), &mut out);
        }
        f.flush(&mut out);
        assert_eq!(out.iter().map(|f| f.pts).collect::<Vec<_>>(), (0..12).map(|i| i as f64).collect::<Vec<_>>());
    }

    #[test]
    fn averages_static_noise() {
        let truth = clean(48, 32);
        let mut f = AtaDenoise::new(9.0, 0.05, 0.3);
        let mut out = Vec::new();
        for i in 0..9 {
            f.push(frame(48, 32, 4.0, i, i as f64), &mut out);
        }
        f.flush(&mut out);
        let mid = &out[4];
        let before = rms(&frame(48, 32, 4.0, 4, 0.0).planes[0], &truth.planes[0]);
        let after = rms(&mid.planes[0], &truth.planes[0]);
        assert!(after < before * 0.6, "{before} -> {after}");
    }
}
