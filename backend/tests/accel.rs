//! The accelerator hook: stages ask the installed accelerator first and fall back to the CPU. This file is its own
//! test binary, so the installed accelerator cannot affect other tests.

use std::sync::Arc;
use up60p::accel::{self, Accelerator};
use up60p::filters::scale::Lanczos;
use up60p::filters::Spatial;
use up60p::frame::{Frame, Plane};

struct Flat;
impl Accelerator for Flat {
    fn name(&self) -> String {
        "flat".into()
    }
    fn resize(&self, _p: &Plane, w: usize, h: usize) -> Option<Plane> {
        Some(Plane::new(w, h, 7.0))
    }
}

fn frame(v: f32) -> Frame {
    Frame { planes: [Plane::new(8, 8, v), Plane::new(8, 8, v), Plane::new(8, 8, v)], alpha: None, pts: 0.0 }
}

#[test]
fn stages_use_the_installed_accelerator_and_fall_back() {
    assert!(accel::current().is_none());
    let mut cpu = frame(50.0);
    Lanczos { factor: 2.0 }.apply(&mut cpu);
    assert!((cpu.planes[0].data[0] - 50.0).abs() < 1e-3);

    accel::install(Arc::new(Flat));
    assert_eq!(accel::current().unwrap().name(), "flat");
    // Not provided by `Flat`: `cas` is None, so the caller keeps its own result.
    assert!(accel::current().unwrap().cas(&Plane::new(4, 4, 1.0), 0.5).is_none());
    let mut fast = frame(50.0);
    Lanczos { factor: 2.0 }.apply(&mut fast);
    assert_eq!((fast.width(), fast.height()), (16, 16));
    assert!(fast.planes.iter().all(|p| p.data.iter().all(|v| *v == 7.0)));

    accel::clear();
    assert!(accel::current().is_none());
    let mut again = frame(50.0);
    Lanczos { factor: 2.0 }.apply(&mut again);
    assert!((again.planes[0].data[0] - 50.0).abs() < 1e-3);
}
