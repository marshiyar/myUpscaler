//! The choice between processing on the CPU and on the GPU. The CPU is the default, the reference and the fallback:
//! the GPU entry exists only when an adapter opened, and anything the GPU cannot do for a frame runs on the CPU
//! stage inside the backend (`up60p::accel`).

use std::sync::Arc;

use up60p::accel::{self, Accelerator};

/// The adapter found at startup, if any.
pub type Probe = Option<Arc<dyn Accelerator>>;

/// Opens a real graphics adapter (a software one would be slower than the CPU code).
pub fn open_gpu() -> Result<Arc<dyn Accelerator>, String> {
    up60p_gpu::GpuAccelerator::new(false).map(|a| Arc::new(a) as Arc<dyn Accelerator>)
}

/// The entries of the processing menu: the CPU, then the GPU when one was found.
pub fn choices(probe: &Probe) -> Vec<String> {
    let mut list = vec!["CPU".to_owned()];
    list.extend(probe.iter().map(|g| format!("GPU ({})", g.name())));
    list
}

/// Why the menu has no GPU entry.
pub fn note(probe: &Result<Arc<dyn Accelerator>, String>) -> String {
    match probe {
        Ok(_) => String::new(),
        Err(e) => format!("No usable GPU ({e}); processing runs on the CPU."),
    }
}

/// Makes the chosen entry the one the backend uses and returns the entry that is really in effect: choosing the
/// GPU without one available leaves the CPU.
pub fn apply(index: i32, probe: &Probe) -> i32 {
    match (index, probe) {
        (1, Some(gpu)) => {
            accel::install(gpu.clone());
            1
        }
        _ => {
            accel::clear();
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    /// The installed accelerator is process-wide, so the tests that change it run one at a time.
    static SERIAL: Mutex<()> = Mutex::new(());

    struct Stub;
    impl Accelerator for Stub {
        fn name(&self) -> String {
            "Stub".into()
        }
    }

    fn stub() -> Probe {
        Some(Arc::new(Stub))
    }

    #[test]
    fn without_a_gpu_only_the_cpu_is_offered_and_chosen() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(choices(&None), ["CPU"]);
        assert_eq!(apply(1, &None), 0);
        assert!(accel::current().is_none());
    }

    #[test]
    fn the_gpu_entry_installs_and_the_cpu_entry_clears() {
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(choices(&stub()), ["CPU", "GPU (Stub)"]);
        assert_eq!(apply(1, &stub()), 1);
        assert_eq!(accel::current().map(|a| a.name()).as_deref(), Some("Stub"));
        assert_eq!(apply(0, &stub()), 0);
        assert!(accel::current().is_none());
    }

    #[test]
    fn a_failed_probe_is_explained() {
        assert_eq!(note(&Ok(Arc::new(Stub))), "");
        assert!(note(&Err("no graphics adapter".into())).contains("runs on the CPU"));
    }

    #[test]
    fn a_stage_the_gpu_declines_runs_on_the_cpu() {
        use up60p::filters::scale::resize;
        use up60p::frame::Plane;
        let _g = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let plane = Plane::new(8, 6, 100.0);
        let cpu = resize(&plane, 16, 12);
        apply(1, &stub());
        let through_hook = accel::current().and_then(|a| a.resize(&plane, 16, 12));
        accel::clear();
        assert!(through_hook.is_none());
        assert_eq!(cpu.data.len(), 16 * 12);
    }
}
