//! Drops frames that repeat the last kept frame (duplicated frames from telecine, frame-rate padding or frozen
//! sources). A frame is kept when any 8x8 luma block changed by more than `hi`, or when more than `frac` of the
//! blocks changed by more than `lo` (sums of absolute differences in code values). Kept frames keep their
//! timestamps, so the retimer later fills the gaps.

use super::Filter;
use crate::frame::{Frame, Plane};

pub struct Decimate {
    hi: f32,
    lo: f32,
    frac: f32,
    last: Option<Plane>,
    dropped: u64,
}

impl Default for Decimate {
    fn default() -> Self {
        Decimate { hi: 64.0 * 12.0, lo: 64.0 * 5.0, frac: 0.33, last: None, dropped: 0 }
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
        let (bw, bh) = (cur.w / 8, cur.h / 8);
        if bw == 0 || bh == 0 {
            return last.data != cur.data;
        }
        let mut over_lo = 0usize;
        for by in 0..bh {
            for bx in 0..bw {
                let mut sad = 0.0f32;
                for y in by * 8..by * 8 + 8 {
                    let a = &last.data[y * cur.w + bx * 8..y * cur.w + bx * 8 + 8];
                    let b = &cur.data[y * cur.w + bx * 8..y * cur.w + bx * 8 + 8];
                    sad += a.iter().zip(b).map(|(p, q)| (p - q).abs()).sum::<f32>();
                }
                if sad > self.hi {
                    return true;
                }
                if sad > self.lo {
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
            out.push(frame);
        } else {
            self.dropped += 1;
        }
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
}
