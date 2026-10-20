//! Film-grain style noise: uniform noise of the given amplitude (code values) on every plane, different in every
//! frame, which masks residual banding and the plastic look of heavy denoising.

use super::Spatial;
use crate::frame::{hash3, unit, Frame};
use crate::par;

pub struct Grain {
    pub strength: f32,
    frame_index: u32,
}

impl Grain {
    pub fn new(strength: f64) -> Grain {
        Grain { strength: strength.clamp(0.0, 100.0) as f32, frame_index: 0 }
    }
}

impl Spatial for Grain {
    fn describe(&self) -> String {
        format!("grain({:.2})", self.strength)
    }

    fn apply(&mut self, frame: &mut Frame) {
        let seed = self.frame_index;
        self.frame_index = self.frame_index.wrapping_add(1);
        if self.strength <= 0.0 {
            return;
        }
        for (pi, plane) in frame.planes.iter_mut().enumerate() {
            let w = plane.w;
            let s = self.strength;
            par::for_each_row(&mut plane.data, w, |y, row| {
                for (x, v) in row.iter_mut().enumerate() {
                    let n = unit(hash3(x as u32, y as u32, seed.wrapping_mul(3).wrapping_add(pi as u32)));
                    *v += (n * 2.0 - 1.0) * s;
                }
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::filters::testutil::clean;

    #[test]
    fn adds_bounded_changing_noise() {
        let mut g = Grain::new(2.0);
        let base = clean(32, 32);
        let (mut a, mut b) = (base.clone(), base.clone());
        g.apply(&mut a);
        g.apply(&mut b);
        let diff: Vec<f32> = a.planes[0].data.iter().zip(&base.planes[0].data).map(|(x, y)| x - y).collect();
        assert!(diff.iter().all(|d| d.abs() <= 2.0));
        assert!(diff.iter().map(|d| d.abs()).sum::<f32>() / diff.len() as f32 > 0.5);
        assert_ne!(a.planes[0], b.planes[0], "grain must change from frame to frame");
    }
}
