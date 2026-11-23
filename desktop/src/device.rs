//! The choice between processing on the CPU and on the GPU. On Windows and macOS the GPU is the default once an
//! adapter opened; elsewhere, and whenever no adapter opened, it is the CPU. The CPU stays selectable, is the
//! reference, and runs anything the GPU cannot do for a frame (the stage falls back inside the backend,
//! `up60p::accel`). The entry the user picked last is kept in `device.txt` beside the presets and wins over the
//! default.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use up60p::accel::{self, Accelerator};

/// The adapter found at startup, if any.
pub type Probe = Option<Arc<dyn Accelerator>>;

/// Opens a real graphics adapter (a software one would be slower than the CPU code).
pub fn open_gpu() -> Result<Arc<dyn Accelerator>, String> {
    up60p_gpu::GpuAccelerator::new(false).map(|a| Arc::new(a) as Arc<dyn Accelerator>)
}

/// An entry the user picked.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Choice {
    Cpu,
    Gpu,
}

impl Choice {
    pub fn from_index(index: i32) -> Choice {
        if index == 1 {
            Choice::Gpu
        } else {
            Choice::Cpu
        }
    }
}

/// Platforms where an adapter that opened is used unless the user chose otherwise.
pub const GPU_FIRST: bool = cfg!(any(windows, target_os = "macos"));

/// The menu entry to start with: the user's last pick when there is one, else the platform default. The GPU entry
/// is chosen only when it exists.
pub fn initial(saved: Option<Choice>, probe: &Probe, gpu_first: bool) -> i32 {
    let wanted = saved.unwrap_or(if gpu_first { Choice::Gpu } else { Choice::Cpu });
    match (wanted, probe) {
        (Choice::Gpu, Some(_)) => 1,
        _ => 0,
    }
}

pub fn file() -> Option<PathBuf> {
    crate::presets::settings_dir().map(|d| d.join("device.txt"))
}

/// The remembered entry; a missing or unreadable file is no choice.
pub fn load(path: &Path) -> Option<Choice> {
    parse(&std::fs::read_to_string(path).ok()?)
}

pub fn parse(text: &str) -> Option<Choice> {
    match text.trim().to_ascii_lowercase().as_str() {
        "cpu" => Some(Choice::Cpu),
        "gpu" => Some(Choice::Gpu),
        _ => None,
    }
}

pub fn save(path: &Path, choice: Choice) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let partial = path.with_extension("txt.partial");
    std::fs::write(&partial, if choice == Choice::Gpu { "gpu\n" } else { "cpu\n" })?;
    std::fs::rename(partial, path)
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

/// The installed accelerator is process-wide, so the tests that change it run one at a time.
#[cfg(test)]
pub static ACCEL_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[cfg(test)]
mod tests {
    use super::*;

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
        let _g = ACCEL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(choices(&None), ["CPU"]);
        assert_eq!(apply(1, &None), 0);
        assert!(accel::current().is_none());
    }

    #[test]
    fn the_gpu_entry_installs_and_the_cpu_entry_clears() {
        let _g = ACCEL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(choices(&stub()), ["CPU", "GPU (Stub)"]);
        assert_eq!(apply(1, &stub()), 1);
        assert_eq!(accel::current().map(|a| a.name()).as_deref(), Some("Stub"));
        assert_eq!(apply(0, &stub()), 0);
        assert!(accel::current().is_none());
    }

    #[test]
    fn the_gpu_is_the_default_where_it_is_first_and_found() {
        assert_eq!(initial(None, &stub(), true), 1);
        assert_eq!(initial(None, &stub(), false), 0);
        assert_eq!(initial(None, &None, true), 0);
    }

    #[test]
    fn the_last_pick_wins_over_the_default() {
        assert_eq!(initial(Some(Choice::Cpu), &stub(), true), 0);
        assert_eq!(initial(Some(Choice::Gpu), &stub(), false), 1);
        // A remembered GPU with no adapter falls back to the CPU without being forgotten.
        assert_eq!(initial(Some(Choice::Gpu), &None, true), 0);
    }

    #[test]
    fn the_pick_is_remembered_in_a_file() {
        let dir = std::env::temp_dir().join(format!("myupscaler-device-{}", std::process::id()));
        let file = dir.join("device.txt");
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(load(&file), None);
        save(&file, Choice::Cpu).unwrap();
        assert_eq!(load(&file), Some(Choice::Cpu));
        save(&file, Choice::Gpu).unwrap();
        assert_eq!(load(&file), Some(Choice::Gpu));
        std::fs::write(&file, "unknown").unwrap();
        assert_eq!(load(&file), None);
        std::fs::remove_dir_all(&dir).unwrap();
        assert_eq!(
            (Choice::from_index(1), Choice::from_index(0), Choice::from_index(7)),
            (Choice::Gpu, Choice::Cpu, Choice::Cpu)
        );
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
        let _g = ACCEL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let plane = Plane::new(8, 6, 100.0);
        let cpu = resize(&plane, 16, 12);
        apply(1, &stub());
        let through_hook = accel::current().and_then(|a| a.resize(&plane, 16, 12));
        accel::clear();
        assert!(through_hook.is_none());
        assert_eq!(cpu.data.len(), 16 * 12);
    }
}
