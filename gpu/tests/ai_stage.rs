//! The model stage of the backend on the GPU: a frame goes in as planar YUV, through the network as RGB tiles and
//! comes out as a larger frame. Without a graphics adapter the test reports that and passes.

mod common;

use common::{picture, random_model};
use std::sync::Arc;
use up60p::accel;
use up60p::filters::scale::AiScale;
use up60p::filters::Spatial;
use up60p::frame::Frame;
use up60p_gpu::ai::{AiScaler, Model, Rgb, TileOptions};
use up60p_gpu::{Gpu, GpuAccelerator};

fn frame(w: usize, h: usize) -> Frame {
    let img = picture(w, h, 9);
    Frame::from_rgb_planes(&img.planes, w, h, 1.5, None)
}

#[test]
fn model_stage_runs_on_the_gpu_and_falls_back_without_a_model() {
    let Ok(accelerator) = GpuAccelerator::new(true) else {
        eprintln!("no GPU available, test skipped");
        return;
    };
    accel::install(Arc::new(accelerator));
    let dir = std::env::temp_dir().join(format!("up60p-ai-stage-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("m.bin");
    std::fs::write(&path, random_model(8, 3, 2, 21).to_bytes()).unwrap();
    // The file keeps the weights as 16-bit floats, so the reference is the model read back from it.
    let model = Model::from_bytes(&std::fs::read(&path).unwrap()).unwrap();
    let path = path.to_string_lossy().into_owned();

    // The stage output is the network's output on the frame's RGB values, back in YUV.
    let mut f = frame(40, 30);
    let input = Rgb { w: 40, h: 30, planes: f.rgb_planes() };
    let gpu = Gpu::new(true).unwrap();
    let want = AiScaler::new(&gpu, &model, TileOptions::for_model(&model)).unwrap().upscale(&gpu, &input).unwrap();
    let mut stage = AiScale::new(2.0, path.clone());
    stage.apply(&mut f);
    assert_eq!((f.width(), f.height()), (80, 60));
    assert_eq!(f.pts, 1.5);
    let got = f.rgb_planes();
    let worst = (0..3)
        .flat_map(|c| got[c].iter().zip(&want.planes[c]).map(|(a, b)| (a - b.clamp(0.0, 255.0)).abs()))
        .fold(0.0f32, f32::max);
    assert!(worst < 0.01, "worst difference {worst}");
    assert!(!stage.describe().contains("lanczos instead"));

    // A factor the model's own scale does not match is reached by resampling its output.
    let mut f = frame(40, 30);
    AiScale::new(1.0, path).apply(&mut f);
    assert_eq!((f.width(), f.height()), (40, 30));

    // A model that cannot be loaded leaves Lanczos at the requested factor.
    let mut f = frame(40, 30);
    let mut stage = AiScale::new(2.0, dir.join("missing.bin").to_string_lossy().into_owned());
    stage.apply(&mut f);
    assert_eq!((f.width(), f.height()), (80, 60));
    assert!(stage.describe().contains("lanczos instead"));

    accel::clear();
    std::fs::remove_dir_all(&dir).ok();
}
