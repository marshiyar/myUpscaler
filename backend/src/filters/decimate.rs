//! Drops frames that repeat the last kept frame (duplicated frames from telecine, frame-rate padding or frozen
//! sources). A frame is kept when any 8x8 luma block changed by more than `hi`, or when more than `frac` of the
//! blocks changed by more than `lo` (sums of absolute differences in code values). Kept frames keep their
//! timestamps, so the retimer later fills the gaps. Blocks at the right and bottom edges may be partial; their
//! thresholds scale with their area. When the stream ends on dropped frames, the last one is passed on at the end,
//! so the retimer knows how long the final picture is shown.

use super::Filter;
use crate::frame::{Frame, Plane};

pub struct Decimate {
    hi: f32,
    lo: f32,
    frac: f32,
    last: Option<Plane>,
    /// The latest dropped frame, while no frame has been kept after it.
    held: Option<Frame>,
    dropped: u64,
}

impl Default for Decimate {
    fn default() -> Self {
        Decimate { hi: 64.0 * 12.0, lo: 64.0 * 5.0, frac: 0.33, last: None, held: None, dropped: 0 }
    }
}

impl Decimate {
    pub fn dropped(&self) -> u64 {
        self.dropped
    }

    fn differs(&self, last: &Plane, cur: &Plane) -> bool {
        if last.w != cur.w || last.h != cur.h {
            return true;
        }
        let (bw, bh) = (cur.w.div_ceil(8), cur.h.div_ceil(8));
        let mut over_lo = 0usize;
        for by in 0..bh {
            let rows = by * 8..(by * 8 + 8).min(cur.h);
            for bx in 0..bw {
                let cols = bx * 8..(bx * 8 + 8).min(cur.w);
                let scale = (rows.len() * cols.len()) as f32 / 64.0;
                let mut sad = 0.0f32;
                for y in rows.clone() {
                    let a = &last.data[y * cur.w + cols.start..y * cur.w + cols.end];
                    let b = &cur.data[y * cur.w + cols.start..y * cur.w + cols.end];
                    sad += a.iter().zip(b).map(|(p, q)| (p - q).abs()).sum::<f32>();
                }
                if sad > self.hi * scale {
                    return true;
                }
                if sad > self.lo * scale {
                    over_lo += 1;
                }
            }
        }
        over_lo as f32 > self.frac * (bw * bh) as f32
    }
}

impl Filter for Decimate {
    fn describe(&self) -> String {
        format!("decimate(hi={}, lo={}, frac={})", self.hi, self.lo, self.frac)
    }

    fn push(&mut self, frame: Frame, out: &mut Vec<Frame>) {
        let keep = self.last.as_ref().is_none_or(|last| self.differs(last, &frame.planes[0]));
        if keep {
            self.last = Some(frame.planes[0].clone());
            self.held = None;
            out.push(frame);
        } else {
            self.dropped += 1;
            self.held = Some(frame);
        }
    }

    fn flush(&mut self, out: &mut Vec<Frame>) {
        out.extend(self.held.take());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::frame;

    #[test]
    fn drops_repeats_and_keeps_changes() {
        let mut d = Decimate::default();
        let mut out = Vec::new();
        let a = frame(64, 64, 0.0, 0, 0.0);
        let mut a2 = a.clone();
        a2.pts = 1.0;
        a2.planes[0].data[5] += 1.0; // invisible change
        let mut b = frame(64, 64, 0.0, 0, 2.0);
        for v in b.planes[0].data[..64 * 8].iter_mut() {
            *v += 40.0; // one strip of blocks changes a lot
        }
        d.push(a, &mut out);
        d.push(a2, &mut out);
        d.push(b, &mut out);
        assert_eq!(out.iter().map(|f| f.pts).collect::<Vec<_>>(), vec![0.0, 2.0]);
        assert_eq!(d.dropped(), 1);
    }

    #[test]
    fn edge_blocks_count_and_a_static_tail_is_passed_on() {
        // 68x68: the last four columns form partial blocks; a change only there is a change.
        let mut d = Decimate::default();
        let mut out = Vec::new();
        let a = frame(68, 68, 0.0, 0, 0.0);
        let mut b = a.clone();
        b.pts = 1.0;
        for y in 0..68 {
            for x in 64..68 {
                b.planes[0].data[y * 68 + x] += 60.0;
            }
        }
        let mut c = b.clone();
        c.pts = 2.0;
        d.push(a, &mut out);
        d.push(b, &mut out);
        d.push(c, &mut out);
        assert_eq!(out.iter().map(|f| f.pts).collect::<Vec<_>>(), vec![0.0, 1.0]);
        d.flush(&mut out);
        assert_eq!(out.iter().map(|f| f.pts).collect::<Vec<_>>(), vec![0.0, 1.0, 2.0]);
    }
}
