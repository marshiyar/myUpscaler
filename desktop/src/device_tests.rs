//! Tests of the processing choice: the default, and the pick kept between runs.
use super::*;
use crate::processing::gpu_found;
use up60p::accel::Accelerator;

struct Stub;
impl Accelerator for Stub {
    fn name(&self) -> String {
        "Stub".into()
    }
}

fn found() -> Result<Arc<dyn Accelerator>, String> {
    Ok(Arc::new(Stub))
}

/// A window with its state, as `wire` builds them, remembering the processing pick in `file`.
fn start(file: &Path) -> (AppWindow, Rc<RefCell<State>>) {
    let ui = AppWindow::new().unwrap();
    let state = wire(&ui);
    {
        let mut s = state.borrow_mut();
        s.gpu_search = None;
        s.device_saved.set(device::load(file));
        s.device_file = Some(file.to_path_buf());
    }
    (ui, state)
}

#[test]
fn the_gpu_is_the_default_and_the_pick_is_remembered() {
    let _g = device::ACCEL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let dir = std::env::temp_dir().join(format!("myupscaler-main-{}", std::process::id()));
    let file = dir.join("device.txt");
    let _ = std::fs::remove_dir_all(&dir);
    let default = device::GPU_FIRST as i32;
    let processing = |ui: &AppWindow| ui.global::<Settings>().get_processing();
    i_slint_backend_testing::init_no_event_loop();

    // First start: the platform default, and nothing is written for it.
    let (ui, state) = start(&file);
    gpu_found(&ui, &mut state.borrow_mut(), found());
    assert_eq!(processing(&ui), default);
    assert_eq!(up60p::accel::current().is_some(), default == 1);
    assert!(!file.exists());

    // The user picks the CPU: it is in effect and kept.
    ui.global::<Settings>().set_processing(0);
    settings_changed(&ui, &state.borrow());
    assert!(up60p::accel::current().is_none());
    assert_eq!(device::load(&file), Some(device::Choice::Cpu));

    // Next start: the pick wins over the default.
    let (ui, state) = start(&file);
    gpu_found(&ui, &mut state.borrow_mut(), found());
    assert_eq!(processing(&ui), 0);
    assert!(up60p::accel::current().is_none());

    // Picking the GPU is kept, and a start without an adapter runs on the CPU and keeps the pick.
    ui.global::<Settings>().set_processing(1);
    settings_changed(&ui, &state.borrow());
    assert_eq!(up60p::accel::current().map(|a| a.name()).as_deref(), Some("Stub"));
    assert_eq!(device::load(&file), Some(device::Choice::Gpu));
    let (ui, state) = start(&file);
    gpu_found(&ui, &mut state.borrow_mut(), Err("no adapter".into()));
    assert_eq!(processing(&ui), 0);
    assert!(up60p::accel::current().is_none());
    assert_eq!(device::load(&file), Some(device::Choice::Gpu));
    let _ = std::fs::remove_dir_all(&dir);
}
