//! A hook for running heavy stages on other hardware. The crate itself has no accelerator: a separate crate
//! implements [`Accelerator`] and installs it with [`install`]. Each method returns `None` when it cannot handle
//! the request, and the stage then runs its own CPU code, which is also the reference the accelerated result is
//! tested against.

use crate::frame::Plane;
use std::sync::{Arc, RwLock};

pub trait Accelerator: Send + Sync {
    /// Short name for the log, such as the graphics adapter.
    fn name(&self) -> String;

    /// Lanczos resampling of one plane to `w` x `h` (see `filters::scale::resize`).
    fn resize(&self, _plane: &Plane, _w: usize, _h: usize) -> Option<Plane> {
        None
    }

    /// Contrast-adaptive sharpening of a luma plane on the 0..255 scale (see `filters::sharpen::Cas`).
    fn cas(&self, _plane: &Plane, _strength: f32) -> Option<Plane> {
        None
    }

    /// BM3D denoising of one plane with noise level `sigma` (see `filters::bm3d::Bm3d`).
    fn bm3d(&self, _plane: &Plane, _sigma: f32) -> Option<Plane> {
        None
    }
}

static INSTALLED: RwLock<Option<Arc<dyn Accelerator>>> = RwLock::new(None);

/// Makes `accelerator` the one the stages ask first.
pub fn install(accelerator: Arc<dyn Accelerator>) {
    *INSTALLED.write().unwrap_or_else(|e| e.into_inner()) = Some(accelerator);
}

/// Goes back to the CPU for every stage.
pub fn clear() {
    *INSTALLED.write().unwrap_or_else(|e| e.into_inner()) = None;
}

pub fn current() -> Option<Arc<dyn Accelerator>> {
    INSTALLED.read().unwrap_or_else(|e| e.into_inner()).clone()
}
