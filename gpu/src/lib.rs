//! GPU versions of the heaviest processing stages, through wgpu. [`install`] makes them the first choice of the
//! backend's stages; anything the GPU cannot do (no adapter, planes too large for its buffers) runs on the CPU
//! code in `up60p`, which is also the reference every stage here is tested against.

mod cas;
mod context;
mod lanczos;

pub use context::Gpu;

use std::sync::Arc;
use up60p::accel::Accelerator;
use up60p::frame::Plane;

pub struct GpuAccelerator {
    gpu: Gpu,
    lanczos: lanczos::Lanczos,
    cas: cas::Cas,
}

impl GpuAccelerator {
    pub fn new(allow_software: bool) -> Result<GpuAccelerator, String> {
        let gpu = Gpu::new(allow_software)?;
        let lanczos = lanczos::Lanczos::new(&gpu);
        let cas = cas::Cas::new(&gpu);
        Ok(GpuAccelerator { gpu, lanczos, cas })
    }
}

impl Accelerator for GpuAccelerator {
    fn name(&self) -> String {
        self.gpu.adapter_name.clone()
    }

    fn resize(&self, plane: &Plane, w: usize, h: usize) -> Option<Plane> {
        self.lanczos.resize(&self.gpu, plane, w, h)
    }

    fn cas(&self, plane: &Plane, strength: f32) -> Option<Plane> {
        self.cas.apply(&self.gpu, plane, strength)
    }
}

/// Opens the GPU and installs it into the backend; returns the adapter's name.
pub fn install(allow_software: bool) -> Result<String, String> {
    let accelerator = GpuAccelerator::new(allow_software)?;
    let name = accelerator.name();
    up60p::accel::install(Arc::new(accelerator));
    Ok(name)
}
