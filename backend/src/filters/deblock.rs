//! Block-edge smoothing for compressed sources: filters across the 8x8 block grid where the step at the edge is
//! small enough to be a coding artefact rather than real image structure.

use super::{number, Spatial};
use crate::frame::{Frame, Plane};
use crate::par;

const BLOCK: usize = 8;

#[derive(Debug, Clone, PartialEq)]
pub struct Deblock {
    pub strong: bool,
    /// Largest step across the edge that is still treated as an artefact (code values).
    pub alpha: f32,
    /// Largest step next to the edge on either side for the edge to count as flat.
    pub beta: f32,
    /// Largest correction of the weak filter.
    pub gamma: f32,
    /// Largest variation of the outer samples for the strong filter.
    pub delta: f32,
}

impl Deblock {
    /// `mode` is `weak` or `strong`; `thresh` is empty or `key=value` pairs separated by `:` with `alpha`, `beta`,
    /// `gamma` and `delta` as fractions of the full range.
    pub fn new(mode: &str, thresh: &str) -> Deblock {
        let mut f = Deblock {
            strong: mode != "weak",
            alpha: 0.098 * 255.0,
            beta: 0.05 * 255.0,
            gamma: 0.05 * 255.0,
            delta: 0.05 * 255.0,
        };
        for part in thresh.split([':', ',']) {
            let Some((key, value)) = part.split_once('=') else { continue };
            let Some(v) = number(value).filter(|v| (0.0..=1.0).contains(v)) else { continue };
            let v = v as f32 * 255.0;
            match key.trim() {
                "alpha" => f.alpha = v,
                "beta" => f.beta = v,
                "gamma" => f.gamma = v,
                "delta" => f.delta = v,
                _ => {}
            }
        }
        f
    }

    /// Filters the six samples p2 p1 p0 | q0 q1 q2 across one edge.
    #[inline]
    fn edge(&self, s: &mut [f32; 6]) {
        let [p2, p1, p0, q0, q1, q2] = *s;
        if (p0 - q0).abs() >= self.alpha || (p1 - p0).abs() >= self.beta || (q1 - q0).abs() >= self.beta {
            return;
        }
        if self.strong && (p2 - p0).abs() < self.delta && (q2 - q0).abs() < self.delta {
            s[1] = (p2 + p1 + p0 + q0) * 0.25;
            s[2] = (p2 + 2.0 * p1 + 2.0 * p0 + 2.0 * q0 + q1) * 0.125;
            s[3] = (p1 + 2.0 * p0 + 2.0 * q0 + 2.0 * q1 + q2) * 0.125;
            s[4] = (p0 + q0 + q1 + q2) * 0.25;
        } else {
            let d = (((q0 - p0) * 4.0 + (p1 - q1)) * 0.125).clamp(-self.gamma, self.gamma);
            s[2] = p0 + d;
            s[3] = q0 - d;
        }
    }

    fn plane(&self, p: &mut Plane) {
        let (w, h) = (p.w, p.h);
        if w < BLOCK * 2 && h < BLOCK * 2 {
            return;
        }
        // Vertical edges: each row is independent.
        par::for_each_row(&mut p.data, w, |_, row| {
            let mut x = BLOCK;
            while x + 3 <= w && x >= 3 {
                let mut s = [row[x - 3], row[x - 2], row[x - 1], row[x], row[x + 1], row[x + 2]];
                self.edge(&mut s);
                row[x - 3..x + 3].copy_from_slice(&s);
                x += BLOCK;
            }
        });
        // Horizontal edges: each edge row touches six rows; edges are eight rows apart, so they never overlap.
        let mut y = BLOCK;
        while y + 3 <= h {
            for x in 0..w {
                let idx = |dy: isize| ((y as isize + dy) as usize) * w + x;
                let mut s =
                    [p.data[idx(-3)], p.data[idx(-2)], p.data[idx(-1)], p.data[idx(0)], p.data[idx(1)], p.data[idx(2)]];
                self.edge(&mut s);
                for (k, v) in s.into_iter().enumerate() {
                    p.data[idx(k as isize - 3)] = v;
                }
            }
            y += BLOCK;
        }
    }
}

impl Spatial for Deblock {
    fn describe(&self) -> String {
        format!(
            "deblock({}, alpha={:.1}, beta={:.1})",
            if self.strong { "strong" } else { "weak" },
            self.alpha,
            self.beta
        )
    }

    fn apply(&mut self, frame: &mut Frame) {
        for p in frame.planes.iter_mut() {
            self.plane(p);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn blocky(w: usize, h: usize) -> Plane {
        let mut p = Plane::new(w, h, 0.0);
        for y in 0..h {
            for x in 0..w {
                // A gentle ramp quantised per 8x8 block: the steps at block edges are pure artefacts.
                p.data[y * w + x] = 100.0 + ((x / 8) as f32) * 3.0 + ((y / 8) as f32) * 2.0;
            }
        }
        p
    }

    fn edge_energy(p: &Plane) -> f32 {
        let mut e = 0.0;
        for y in 0..p.h {
            for x in (8..p.w).step_by(8) {
                e += (p.at(x, y) - p.at(x - 1, y)).abs();
            }
        }
        e
    }

    #[test]
    fn smooths_block_steps() {
        let mut p = blocky(64, 64);
        let before = edge_energy(&p);
        Deblock::new("strong", "").plane(&mut p);
        assert!(edge_energy(&p) < before * 0.5, "{} -> {}", before, edge_energy(&p));
    }

    #[test]
    fn keeps_real_edges() {
        let mut p = Plane::new(32, 16, 0.0);
        for y in 0..16 {
            for x in 16..32 {
                p.data[y * 32 + x] = 200.0;
            }
        }
        let before = p.clone();
        Deblock::new("weak", "").plane(&mut p);
        assert_eq!(p, before);
    }

    #[test]
    fn parses_thresholds() {
        let d = Deblock::new("weak", "alpha=0.2:beta=0.1");
        assert!(!d.strong);
        assert!((d.alpha - 51.0).abs() < 1e-3 && (d.beta - 25.5).abs() < 1e-3);
    }
}
