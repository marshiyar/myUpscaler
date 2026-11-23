//! Deterministic models and images shared by the AI tests.
#![allow(dead_code)]

use up60p_gpu::ai::{Layer, Model, Rgb};

pub struct Rng(pub u64);

impl Rng {
    /// Uniform in -1..1.
    pub fn next(&mut self) -> f32 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((self.0 >> 40) as f32 / 16777216.0) * 2.0 - 1.0
    }
}

/// `convs` convolutions, `channels` wide except the last, which has `3 * scale * scale` outputs.
pub fn random_model(channels: usize, convs: usize, scale: usize, seed: u64) -> Model {
    let mut rng = Rng(seed);
    let mut layers = Vec::new();
    let mut cin = 3;
    for i in 0..convs {
        let last = i + 1 == convs;
        let cout = if last { 3 * scale * scale } else { channels };
        let k = (2.0 / (cin * 9) as f32).sqrt();
        layers.push(Layer {
            cin,
            cout,
            weights: (0..cout * cin * 9).map(|_| rng.next() * k).collect(),
            bias: (0..cout).map(|_| rng.next() * 0.05).collect(),
            slopes: if last { None } else { Some((0..cout).map(|_| 0.1 + 0.1 * rng.next()).collect()) },
        });
        cin = cout;
    }
    Model::new(layers, scale).unwrap()
}

/// Smooth gradients, hard edges and noise on the 0..255 scale.
pub fn picture(w: usize, h: usize, seed: u64) -> Rgb {
    let mut rng = Rng(seed);
    let mut img = Rgb::new(w, h, 0.0);
    for (c, plane) in img.planes.iter_mut().enumerate() {
        for y in 0..h {
            for x in 0..w {
                let edge = if (x / 7 + y / 5 + c) % 2 == 0 { 40.0 } else { 190.0 };
                plane[y * w + x] = (edge + x as f32 * 0.8 + rng.next() * 10.0).clamp(0.0, 255.0);
            }
        }
    }
    img
}

pub fn max_difference(a: &Rgb, b: &Rgb) -> f32 {
    assert_eq!((a.w, a.h), (b.w, b.h));
    a.planes.iter().zip(&b.planes).flat_map(|(p, q)| p.iter().zip(q)).map(|(x, y)| (x - y).abs()).fold(0.0, f32::max)
}
