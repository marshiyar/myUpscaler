//! Each GPU stage against the CPU stage in `up60p`, which is the reference. Without a graphics adapter (not even a
//! software one) the tests report that and pass.

use up60p::filters::scale::resize;
use up60p::filters::sharpen::Cas;
use up60p::filters::Spatial;
use up60p::frame::{Frame, Plane};
use up60p_gpu::GpuAccelerator;

/// Largest allowed difference on the 0..255 sample scale.
const TOLERANCE: f32 = 0.01;

fn accelerator() -> Option<GpuAccelerator> {
    match GpuAccelerator::new(true) {
        Ok(a) => Some(a),
        Err(e) => {
            eprintln!("no GPU available, test skipped: {e}");
            None
        }
    }
}

/// A deterministic test image with edges, gradients and noise.
pub fn picture(w: usize, h: usize) -> Plane {
    let mut p = Plane::new(w, h, 0.0);
    let mut state = 12345u32;
    for y in 0..h {
        for x in 0..w {
            state = state.wrapping_mul(1664525).wrapping_add(1013904223);
            let noise = (state >> 24) as f32 / 255.0 * 20.0;
            let edge = if (x / 9 + y / 7) % 2 == 0 { 40.0 } else { 200.0 };
            p.data[y * w + x] = (edge + (x as f32 * 0.5) + noise).clamp(0.0, 255.0);
        }
    }
    p
}

fn max_difference(a: &Plane, b: &Plane) -> f32 {
    assert_eq!((a.w, a.h), (b.w, b.h));
    a.data.iter().zip(&b.data).map(|(x, y)| (x - y).abs()).fold(0.0, f32::max)
}

#[test]
fn lanczos_matches_the_cpu() {
    let Some(gpu) = accelerator() else { return };
    use up60p::accel::Accelerator;
    for (sw, sh, dw, dh) in [(97, 61, 194, 122), (200, 120, 76, 44), (64, 64, 96, 96), (33, 17, 100, 50)] {
        let src = picture(sw, sh);
        let cpu = resize(&src, dw, dh);
        let fast = gpu.resize(&src, dw, dh).expect("the GPU resizes a small plane");
        let d = max_difference(&cpu, &fast);
        assert!(d <= TOLERANCE, "{sw}x{sh} -> {dw}x{dh}: max difference {d} on {}", gpu.name());
    }
}

#[test]
fn cas_matches_the_cpu() {
    let Some(gpu) = accelerator() else { return };
    use up60p::accel::Accelerator;
    for (w, h) in [(1, 1), (5, 3), (15, 17), (16, 16), (33, 20), (97, 61), (200, 120)] {
        for strength in [0.0f32, 0.5, 1.0] {
            let src = picture(w, h);
            let chroma = Plane::new(1, 1, 128.0);
            let mut frame = Frame { planes: [src.clone(), chroma.clone(), chroma], alpha: None, pts: 0.0 };
            // No accelerator is installed in this process, so this runs the CPU code.
            Cas::new(strength as f64).apply(&mut frame);
            let fast = gpu.cas(&src, strength).expect("the GPU sharpens a small plane");
            let d = max_difference(&frame.planes[0], &fast);
            assert!(d <= TOLERANCE, "{w}x{h} strength {strength}: max difference {d} on {}", gpu.name());
        }
    }
}
