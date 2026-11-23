//! The processing choice (CPU or GPU): the entry to start with and the user's pick kept between runs.
use std::sync::Arc;

use slint::{ComponentHandle, ModelRc, SharedString, VecModel};

use crate::{append_log, device, settings_changed, App, AppWindow, Settings, State};

/// Applies the result of the startup adapter search: the menu, and the entry to start with. That is the GPU where
/// the platform prefers it, unless the user picked otherwise. A run that started before the search ended keeps the
/// CPU it started on.
pub fn gpu_found(ui: &AppWindow, state: &mut State, found: Result<Arc<dyn up60p::accel::Accelerator>, String>) {
    let app = ui.global::<App>();
    app.set_device_note(device::note(&found).into());
    state.gpu = found.ok();
    let names = device::choices(&state.gpu);
    app.set_devices(ModelRc::new(VecModel::from(names.into_iter().map(SharedString::from).collect::<Vec<_>>())));
    if !app.get_running() {
        let index = device::initial(state.device_saved.get(), &state.gpu, device::GPU_FIRST);
        ui.global::<Settings>().set_processing(index);
        state.processing.set(index);
        settings_changed(ui, state);
    }
}

/// Keeps `asked` as the user's pick when it differs from the entry in effect (the search sets it through
/// `processing`).
pub fn remember(ui: &AppWindow, state: &State, asked: i32) {
    if asked == state.processing.get() || state.gpu.is_none() {
        return;
    }
    let choice = device::Choice::from_index(asked);
    state.device_saved.set(Some(choice));
    if let Some(file) = &state.device_file {
        if let Err(e) = device::save(file, choice) {
            append_log(
                ui,
                &format!(
                    "The processing choice could not be saved to {}: {e}
",
                    file.display()
                ),
            );
        }
    }
}
