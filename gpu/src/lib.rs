//! GPU versions of the heaviest processing stages, through wgpu. [`install`] makes them the first choice of the
//! backend's stages; anything the GPU cannot do (no adapter, planes too large for its buffers) runs on the CPU
//! code in `up60p`, which is also the reference every stage here is tested against.

pub mod ai;
mod bm3d;
mod cas;
mod context;
mod lanczos;

pub use context::Gpu;

use std::path::Path;
use std::sync::{Arc, Mutex};
use up60p::accel::Accelerator;
use up60p::filters::scale::resize;
use up60p::frame::{Frame, Plane};

pub struct GpuAccelerator {
    gpu: Gpu,
    lanczos: lanczos::Lanczos,
    bm3d: bm3d::Bm3dStage,
    cas: cas::Cas,
    /// The model last asked for, with `None` when its file could not be loaded.
    model: Mutex<Option<(String, Option<Arc<ai::AiScaler>>)>>,
}

impl GpuAccelerator {
    pub fn new(allow_software: bool) -> Result<GpuAccelerator, String> {
        let gpu = Gpu::new(allow_software)?;
        let lanczos = lanczos::Lanczos::new(&gpu);
        let bm3d = bm3d::Bm3dStage::new(&gpu);
        let cas = cas::Cas::new(&gpu);
        Ok(GpuAccelerator { gpu, lanczos, bm3d, cas, model: Mutex::new(None) })
    }

    /// The model in `path`, uploaded to the device once and kept while the same path is asked for. A `.param` file
    /// is an ncnn model with its `.bin` beside it; any other file is the container written by `Model::to_bytes`.
    fn model(&self, path: &str) -> Option<Arc<ai::AiScaler>> {
        let mut cached = self.model.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((p, scaler)) = cached.as_ref() {
            if p == path {
                return scaler.clone();
            }
        }
        let loaded = load_model(&self.gpu, path);
        if let Err(e) = &loaded {
            eprintln!("model {path}: {e}");
        }
        let scaler = loaded.ok().map(Arc::new);
        *cached = Some((path.to_owned(), scaler.clone()));
        scaler
    }
}

fn load_model(gpu: &Gpu, path: &str) -> Result<ai::AiScaler, String> {
    let path = Path::new(path);
    let model = if path.extension().is_some_and(|e| e.eq_ignore_ascii_case("param")) {
        let param = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
        let bin = std::fs::read(path.with_extension("bin")).map_err(|e| e.to_string())?;
        ai::Model::from_ncnn(&param, &bin)?
    } else {
        ai::Model::from_bytes(&std::fs::read(path).map_err(|e| e.to_string())?)?
    };
    let options = ai::TileOptions::for_model(&model);
    ai::AiScaler::new(gpu, &model, options)
}

impl Accelerator for GpuAccelerator {
    fn name(&self) -> String {
        self.gpu.adapter_name.clone()
    }

    fn resize(&self, plane: &Plane, w: usize, h: usize) -> Option<Plane> {
        self.lanczos.resize(&self.gpu, plane, w, h)
    }

    fn bm3d(&self, plane: &Plane, sigma: f32) -> Option<Plane> {
        self.bm3d.denoise(&self.gpu, plane, sigma)
    }

    fn cas(&self, plane: &Plane, strength: f32) -> Option<Plane> {
        self.cas.apply(&self.gpu, plane, strength)
    }

    fn ai_upscale(&self, model: &str, frame: &Frame) -> Option<Frame> {
        let scaler = self.model(model)?;
        let (w, h) = (frame.width(), frame.height());
        let input = ai::Rgb { w, h, planes: frame.rgb_planes() };
        let out = scaler.upscale(&self.gpu, &input)?;
        let alpha = frame.alpha.as_ref().map(|a| {
            let mut a = resize(a, out.w, out.h);
            a.data.iter_mut().for_each(|v| *v = v.clamp(0.0, 255.0));
            a
        });
        Some(Frame::from_rgb_planes(&out.planes, out.w, out.h, frame.pts, alpha))
    }
}

/// Opens the GPU and installs it into the backend; returns the adapter's name.
pub fn install(allow_software: bool) -> Result<String, String> {
    let accelerator = GpuAccelerator::new(allow_software)?;
    let name = accelerator.name();
    up60p::accel::install(Arc::new(accelerator));
    Ok(name)
}
