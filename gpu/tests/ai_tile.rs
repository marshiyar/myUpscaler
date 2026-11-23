//! One tile through the GPU network against the CPU reference. Without a graphics adapter the tests report that
//! and pass.

mod common;

use common::{max_difference, picture, random_model};
use up60p_gpu::ai::{cpu_forward, run_tile};
use up60p_gpu::Gpu;

/// Largest allowed difference on the 0..255 scale.
const TOLERANCE: f32 = 1e-3;

fn gpu() -> Option<Gpu> {
    match Gpu::new(true) {
        Ok(g) => Some(g),
        Err(e) => {
            eprintln!("no GPU available, test skipped: {e}");
            None
        }
    }
}

fn check(gpu: &Gpu, channels: usize, convs: usize, scale: usize, w: usize, h: usize) {
    let model = random_model(channels, convs, scale, 11);
    let tile = picture(w, h, 5);
    let want = cpu_forward(&model, &tile);
    let got = run_tile(gpu, &model, &tile).expect("a small tile fits");
    let d = max_difference(&want, &got);
    println!("{channels} channels, {convs} convs, x{scale}, {w}x{h}: max difference {d:e} on {}", gpu.adapter_name);
    assert!(d <= TOLERANCE, "max difference {d}");
}

#[test]
fn tiny_model_matches_the_cpu() {
    let Some(gpu) = gpu() else { return };
    check(&gpu, 5, 2, 2, 32, 32);
}

#[test]
fn wider_deeper_model_matches_the_cpu() {
    let Some(gpu) = gpu() else { return };
    check(&gpu, 16, 4, 4, 32, 32);
}

#[test]
fn odd_sizes_and_channel_counts_match_the_cpu() {
    let Some(gpu) = gpu() else { return };
    check(&gpu, 3, 3, 3, 17, 9);
    check(&gpu, 11, 2, 2, 1, 1);
    check(&gpu, 8, 2, 2, 5, 70);
}

#[test]
fn a_tile_that_does_not_fit_gives_none() {
    let Some(mut gpu) = gpu() else { return };
    let model = random_model(8, 2, 2, 3);
    let tile = picture(32, 32, 1);
    assert!(run_tile(&gpu, &model, &tile).is_some());
    gpu.limits.max_storage_buffer_binding_size = 1000;
    assert!(run_tile(&gpu, &model, &tile).is_none());
}
