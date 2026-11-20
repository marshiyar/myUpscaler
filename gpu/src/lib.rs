//! GPU versions of the heaviest processing stages, through wgpu. [`install`] makes them the first choice of the
//! backend's stages; anything the GPU cannot do (no adapter, planes too large for its buffers) runs on the CPU
//! code in `up60p`, which is also the reference every stage here is tested against.

mod bm3d;
mod context;
mod lanczos;

pub use context::Gpu;

use std::sync::Arc;
use up60p::accel::Accelerator;
use up60p::frame::Plane;

pub struct GpuAccelerator {
    gpu: Gpu,
    lanczos: lanczos::Lanczos,
    bm3d: bm3d::Bm3dStage,
}

impl GpuAccelerator {
    pub fn new(allow_software: bool) -> Result<GpuAccelerator, String> {
        let gpu = Gpu::new(allow_software)?;
        let lanczos = lanczos::Lanczos::new(&gpu);
        let bm3d = bm3d::Bm3dStage::new(&gpu);
        Ok(GpuAccelerator { gpu, lanczos, bm3d })
    }
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
}

/// Opens the GPU and installs it into the backend; returns the adapter's name.
pub fn install(allow_software: bool) -> Result<String, String> {
    let accelerator = GpuAccelerator::new(allow_software)?;
    let name = accelerator.name();
    up60p::accel::install(Arc::new(accelerator));
    Ok(name)
}
