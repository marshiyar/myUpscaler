//! Frame-rate conversion by repetition, for videos retimed without interpolation.

/// Retiming by repeating frames (`dup` without making new pictures), as counts: how many times each frame is shown
/// on the output grid, by the same rules as `Retimer` in `dup` mode. The job repeats the finished picture itself, so a
/// repeat costs neither filtering nor a copy.
pub struct Repeater {
    out_fps: f64,
    src_frame_duration: f64,
    start: f64,
    /// The time of the frame whose count is not known yet.
    held: Option<f64>,
    next_index: u64,
    limit: Option<u64>,
}

impl Repeater {
    pub fn new(out_fps: f64, src_fps: f64) -> Repeater {
        let src = if src_fps > 0.0 { src_fps } else { out_fps };
        Repeater { out_fps, src_frame_duration: 1.0 / src, start: 0.0, held: None, next_index: 0, limit: None }
    }

    /// Makes the output exactly `frames` long (at least one).
    pub fn with_frame_limit(mut self, frames: u64) -> Repeater {
        self.limit = Some(frames.max(1));
        self
    }

    pub fn describe(&self) -> String {
        match self.limit {
            Some(n) => format!("retime(dup, {:.3} fps, {n} frames)", self.out_fps),
            None => format!("retime(dup, {:.3} fps)", self.out_fps),
        }
    }

    fn time(&self, index: u64) -> f64 {
        self.start + index as f64 / self.out_fps
    }

    fn take(&mut self, count: u64) -> u64 {
        let count = self.limit.map_or(count, |l| count.min(l.saturating_sub(self.next_index)));
        self.next_index += count;
        count
    }

    /// A frame at `pts` arrived: how many times the previous frame is shown (none before the first frame).
    pub fn push(&mut self, pts: f64) -> u64 {
        let Some(_) = self.held.replace(pts) else {
            self.start = pts;
            return 0;
        };
        let mut count = 0;
        while self.time(self.next_index + count) < pts - 1e-9 {
            count += 1;
        }
        self.take(count)
    }

    /// The input ended: how many times the last frame is shown (at least once, or up to the frame limit).
    pub fn finish(&mut self) -> u64 {
        let Some(last) = self.held.take() else { return 0 };
        if let Some(limit) = self.limit {
            return self.take(limit.saturating_sub(self.next_index));
        }
        let end = last + self.src_frame_duration;
        let mut count = 0;
        loop {
            let t = self.time(self.next_index + count);
            if t >= end - 1e-9 && t > last + 1e-9 {
                break;
            }
            count += 1;
        }
        self.take(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::interpolate::{Mode, Retimer};
    use crate::filters::testutil::frame;
    use crate::filters::Filter;

    #[test]
    fn repeater_counts_match_the_dup_retimer() {
        // Steady, decimated and variable-rate inputs, with and without a frame limit.
        let cases: [(&[f64], f64, f64, Option<u64>); 5] = [
            (&[0.0, 1.0, 2.0], 2.0, 1.0, None),
            (&[0.0, 0.3], 10.0, 10.0, None),
            (&[0.0, 0.042, 0.083, 0.2, 0.21, 0.25], 60.0, 24.0, None),
            (&[0.0, 1.0, 2.0], 2.0, 1.0, Some(3)),
            (&[0.0, 1.0], 2.0, 1.0, Some(8)),
        ];
        for (times, out_fps, src_fps, limit) in cases {
            let mut retimer = Retimer::new(Mode::Dup, out_fps, src_fps);
            let mut repeater = Repeater::new(out_fps, src_fps);
            if let Some(n) = limit {
                retimer = retimer.with_frame_limit(n);
                repeater = repeater.with_frame_limit(n);
            }
            let (mut frames, mut shown) = (Vec::new(), Vec::new());
            for (i, &t) in times.iter().enumerate() {
                let mut f = frame(16, 16, 0.0, 0, t);
                f.planes[0].data[0] = i as f32;
                retimer.push(f, &mut frames);
                let n = repeater.push(t);
                shown.extend(std::iter::repeat_n(i.saturating_sub(1) as f32, n as usize));
            }
            retimer.flush(&mut frames);
            shown.extend(std::iter::repeat_n((times.len() - 1) as f32, repeater.finish() as usize));
            let expected: Vec<f32> = frames.iter().map(|f| f.planes[0].data[0]).collect();
            assert_eq!(shown, expected, "{times:?} at {out_fps} fps, limit {limit:?}");
        }
    }
}
