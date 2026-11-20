//! Each GPU stage against the CPU stage in `up60p`, which is the reference. Without a graphics adapter (not even a
//! software one) the tests report that and pass.

use up60p::filters::scale::resize;
use up60p::frame::Plane;
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

/// BM3D picks groups and thresholds coefficients, so a sample can differ where two candidates match almost equally
/// or a coefficient sits on the threshold. The mean difference must stay tiny and the largest one bounded.
const BM3D_MEAN_TOLERANCE: f32 = 0.005;
const BM3D_MAX_TOLERANCE: f32 = 0.5;

#[test]
fn bm3d_matches_the_cpu() {
    let Some(gpu) = accelerator() else { return };
    use up60p::accel::Accelerator;
    use up60p::filters::bm3d::Bm3d;
    for (w, h, sigma) in [(96, 64, 7.0), (131, 77, 3.0), (200, 120, 12.0), (8, 8, 5.0), (7, 20, 5.0)] {
        let src = picture(w, h);
        let cpu = Bm3d::new(Some(sigma as f64)).denoise(&src, sigma);
        let fast = gpu.bm3d(&src, sigma).expect("the GPU denoises a small plane");
        let d = max_difference(&cpu, &fast);
        let mean = cpu.data.iter().zip(&fast.data).map(|(a, b)| (a - b).abs()).sum::<f32>() / cpu.data.len() as f32;
        eprintln!("bm3d {w}x{h} sigma {sigma}: max {d} mean {mean}");
        assert!(
            d <= BM3D_MAX_TOLERANCE && mean <= BM3D_MEAN_TOLERANCE,
            "{w}x{h} sigma {sigma}: max difference {d}, mean {mean} on {}",
            gpu.name()
        );
    }
}
