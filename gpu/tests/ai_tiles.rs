//! Tiled GPU upscaling against the whole-image CPU reference. Without a graphics adapter the tests report that and
//! pass.

mod common;

use common::{max_difference, picture, random_model};
use up60p_gpu::ai::{cpu_forward, AiScaler, Model, Rgb, TileOptions};
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

fn reflect(i: isize, n: usize) -> usize {
    if n == 1 {
        return 0;
    }
    let period = 2 * (n as isize - 1);
    let m = i.rem_euclid(period);
    (if m >= n as isize { period - m } else { m }) as usize
}

/// The reference. The network zero-pads, so near the image border the tiled result (which sees a mirrored image
/// there) is not comparable to `cpu_forward` on the image itself. The reference is therefore `cpu_forward` on the
/// image mirrored by `pad` pixels on every side, cropped back to the image: the same input the tiles see.
fn reference(model: &Model, img: &Rgb, pad: usize) -> Rgb {
    let s = model.scale();
    let mut padded = Rgb::new(img.w + 2 * pad, img.h + 2 * pad, 0.0);
    for (dst, src) in padded.planes.iter_mut().zip(&img.planes) {
        for y in 0..padded.h {
            for x in 0..padded.w {
                let (sy, sx) = (reflect(y as isize - pad as isize, img.h), reflect(x as isize - pad as isize, img.w));
                dst[y * padded.w + x] = src[sy * img.w + sx];
            }
        }
    }
    let full = cpu_forward(model, &padded);
    let mut out = Rgb::new(img.w * s, img.h * s, 0.0);
    for (dst, src) in out.planes.iter_mut().zip(&full.planes) {
        for y in 0..out.h {
            let from = (pad * s + y) * full.w + pad * s;
            dst[y * out.w..(y + 1) * out.w].copy_from_slice(&src[from..from + out.w]);
        }
    }
    out
}

fn check(gpu: &Gpu, model: &Model, w: usize, h: usize, options: TileOptions) {
    let img = picture(w, h, 9);
    let scaler = AiScaler::new(gpu, model, options).unwrap();
    let got = scaler.upscale(gpu, &img).expect("the tiles fit");
    assert_eq!((got.w, got.h), (w * model.scale(), h * model.scale()));
    let want = reference(model, &img, model.radius());
    let d = max_difference(&want, &got);
    println!("{w}x{h}, x{}, {options:?}: max difference {d:e} on {}", model.scale(), gpu.adapter_name);
    assert!(d <= TOLERANCE, "max difference {d}");
}

#[test]
fn tiles_match_the_whole_image() {
    let Some(gpu) = gpu() else { return };
    let model = random_model(4, 2, 2, 21);
    assert_eq!(model.radius(), 2);
    check(&gpu, &model, 70, 50, TileOptions { tile: 32, overlap: 2 });
}

#[test]
fn larger_overlap_and_other_scales_match() {
    let Some(gpu) = gpu() else { return };
    let model = random_model(6, 3, 3, 4);
    check(&gpu, &model, 41, 23, TileOptions { tile: 20, overlap: 5 });
    let model = random_model(8, 4, 4, 8);
    check(&gpu, &model, 33, 37, TileOptions::for_model(&model));
}

#[test]
fn an_image_smaller_than_a_tile_and_a_single_pixel_work() {
    let Some(gpu) = gpu() else { return };
    let model = random_model(4, 2, 2, 2);
    check(&gpu, &model, 9, 6, TileOptions { tile: 32, overlap: 2 });
    check(&gpu, &model, 1, 1, TileOptions { tile: 32, overlap: 2 });
}

#[test]
fn options_are_validated() {
    let Some(gpu) = gpu() else { return };
    let model = random_model(4, 2, 2, 2);
    assert!(AiScaler::new(&gpu, &model, TileOptions { tile: 4, overlap: 2 }).is_err());
    assert_eq!(TileOptions::for_model(&model), TileOptions { tile: 256, overlap: 2 });
    let scaler = AiScaler::new(&gpu, &model, TileOptions::for_model(&model)).unwrap();
    let (small, large) = (scaler.estimate_seconds(100, 100), scaler.estimate_seconds(2000, 2000));
    assert!(small > 0.0 && large > 10.0 * small);
}

#[test]
fn an_image_whose_tiles_do_not_fit_gives_none() {
    let Some(mut gpu) = gpu() else { return };
    let model = random_model(8, 2, 2, 3);
    let img = picture(70, 50, 1);
    let scaler = AiScaler::new(&gpu, &model, TileOptions { tile: 32, overlap: 2 }).unwrap();
    assert!(scaler.upscale(&gpu, &img).is_some());
    // A 32x32 tile with 12 channels of 4 bytes needs 49152 bytes in one buffer.
    gpu.limits.max_storage_buffer_binding_size = 40_000;
    assert!(scaler.upscale(&gpu, &img).is_none());
}
