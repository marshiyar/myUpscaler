//! myUpscaler for macOS, Windows and Linux: the Slint interface (`ui/`) on the Rust processing backend (`backend/`).
//! Processing and the preview run on their own threads and report back through channels that a timer on the
//! interface thread drains, so the window never waits on the engine.

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

mod preview;
mod progress;
mod screenshot;
mod settings;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use slint::{ComponentHandle, Image, SharedString, Timer, TimerMode};
use up60p::engine;
use up60p::job::{self, Job};
use up60p::options::Options;

use progress::Progress;

slint::include_modules!();

/// What the processing thread reports.
enum Report {
    Log(String),
    Finished { result: Result<(), String>, cancelled: bool },
}

/// Inputs the file dialog offers: what the backend processes.
const MEDIA_EXTENSIONS: [&str; 12] =
    ["mp4", "mov", "m4v", "mkv", "webm", "png", "jpg", "jpeg", "bmp", "webp", "tif", "tiff"];

/// The longest the log may grow before its oldest lines are dropped.
const LOG_LIMIT: usize = 200_000;

struct State {
    input: Option<PathBuf>,
    cancel: Arc<AtomicBool>,
    reports: Option<Receiver<Report>>,
    progress: Progress,
    preview: Sender<preview::Request>,
    replies: Receiver<preview::Reply>,
}

fn append_log(ui: &AppWindow, text: &str) {
    let app = ui.global::<App>();
    let mut log = app.get_log().to_string();
    log.push_str(text);
    if log.len() > LOG_LIMIT {
        let cut = log.len() - LOG_LIMIT;
        let start = log[cut..].find('\n').map_or(cut, |i| cut + i + 1);
        log.drain(..start);
    }
    app.set_log(log.into());
}

fn describe_input(path: &Path) -> (String, f64, bool) {
    let image = job::is_image(path);
    let size = engine::Video::open(path).map_or(String::new(), |v| format!("{}×{} · ", v.width, v.height));
    match engine::probe(path) {
        Ok(probe) => match probe.video {
            Some(v) if image => (format!("{size}{}", v.codec), 0.0, true),
            Some(v) => (
                format!(
                    "{size}{} · {} fps · {}{}",
                    v.codec,
                    (v.frame_rate * 1000.0).round() / 1000.0,
                    progress::clock(probe.duration),
                    probe.audio.map_or(String::new(), |a| format!(" · {}", a.codec))
                ),
                probe.duration,
                false,
            ),
            None => ("No video track".into(), 0.0, image),
        },
        Err(e) => (format!("Not readable: {e}"), 0.0, image),
    }
}

fn predicted_output(options: &Options, input: &Path) -> String {
    let cancel = AtomicBool::new(false);
    let log = |_: &str| {};
    let job = Job { options, log: &log, cancel: &cancel, dry_run: true };
    if input.is_dir() {
        "One <name>_[restored] file per video or image in the folder".into()
    } else {
        job.output_path(input).display().to_string()
    }
}

fn request_preview(ui: &AppWindow, state: &State) {
    let app = ui.global::<App>();
    let Some(input) = state.input.clone().filter(|p| p.is_file()) else {
        app.set_has_preview(false);
        app.set_preview_note("Folder selected: every video and image in it is processed.".into());
        return;
    };
    let filters = app.get_show_processed().then(|| Box::new(settings::options(&ui.global::<Settings>())));
    app.set_preview_busy(true);
    let _ = state.preview.send(preview::Request { path: input, seconds: app.get_position() as f64, filters });
}

fn select_input(ui: &AppWindow, state: &mut State, path: PathBuf) {
    let app = ui.global::<App>();
    let name = path.file_name().map_or_else(|| path.display().to_string(), |n| n.to_string_lossy().into_owned());
    let (info, duration, image) = if path.is_dir() { ("Folder".into(), 0.0, false) } else { describe_input(&path) };
    app.set_input_path(path.display().to_string().into());
    app.set_input_name(name.into());
    app.set_input_info(info.into());
    app.set_duration(duration as f32);
    app.set_duration_text(progress::clock(duration).into());
    app.set_position_text(progress::clock(0.0).into());
    app.set_is_image(image);
    app.set_position(0.0);
    app.set_error(SharedString::new());
    app.set_phase("Ready".into());
    app.set_progress(0.0);
    app.set_predicted_output(predicted_output(&settings::options(&ui.global::<Settings>()), &path).into());
    state.input = Some(path);
    request_preview(ui, state);
}

fn start(ui: &AppWindow, state: &mut State) {
    let Some(input) = state.input.clone() else { return };
    let app = ui.global::<App>();
    let options = settings::options(&ui.global::<Settings>());
    let (tx, rx) = channel();
    state.reports = Some(rx);
    state.progress = Progress::default();
    state.cancel.store(false, Ordering::SeqCst);
    let cancel = state.cancel.clone();
    app.set_running(true);
    app.set_cancelling(false);
    app.set_progress_known(false);
    app.set_progress(0.0);
    app.set_error(SharedString::new());
    app.set_phase("Starting…".into());
    app.set_fps_text("--".into());
    app.set_time_text("--:--".into());
    app.set_eta_text("--:--".into());
    append_log(ui, &format!("--- Starting Rust Engine: {} ---\n", input.display()));
    std::thread::spawn(move || {
        let sender = Mutex::new(tx.clone());
        let log = |line: &str| {
            let _ = sender.lock().map(|s| s.send(Report::Log(line.to_owned())));
        };
        job::configure_threads(&options);
        let job = Job { options: &options, log: &log, cancel: &cancel, dry_run: false };
        let result = job.run(&input);
        let cancelled = matches!(result, Err(job::JobError::Cancelled));
        let _ = tx.send(Report::Finished { result: result.map_err(|e| e.to_string()), cancelled });
    });
}

/// Applies what the processing and preview threads reported since the last tick.
fn drain(ui: &AppWindow, state: &mut State) {
    let app = ui.global::<App>();
    while let Ok(reply) = state.replies.try_recv() {
        app.set_preview_busy(false);
        match reply {
            preview::Reply::Frame(buffer) => {
                app.set_preview(Image::from_rgba8(buffer));
                app.set_has_preview(true);
                app.set_preview_note(SharedString::new());
            }
            preview::Reply::Failed(e) => {
                app.set_has_preview(false);
                app.set_preview_note(format!("No preview: {e}").into());
            }
        }
    }
    let Some(reports) = &state.reports else { return };
    let mut finished = None;
    let mut text = String::new();
    while let Ok(report) = reports.try_recv() {
        match report {
            Report::Log(line) => {
                state.progress.read(&line);
                text.push_str(&line);
            }
            Report::Finished { result, cancelled } => finished = Some((result, cancelled)),
        }
    }
    if !text.is_empty() {
        append_log(ui, &text);
    }
    let p = &state.progress;
    if let Some(phase) = p.phase {
        app.set_phase(phase.into());
    }
    app.set_progress_known(p.fraction.is_some());
    if let Some(f) = p.fraction {
        app.set_progress(f as f32);
    }
    if let Some(fps) = &p.fps {
        app.set_fps_text(fps.into());
    }
    if let Some(time) = &p.time {
        app.set_time_text(time.into());
    }
    if let Some(eta) = &p.eta {
        app.set_eta_text(eta.into());
    }
    if let Some((result, cancelled)) = finished {
        state.reports = None;
        app.set_running(false);
        app.set_cancelling(false);
        app.set_progress_known(true);
        match (result, cancelled) {
            (_, true) => {
                app.set_phase("Cancelled".into());
                app.set_progress(0.0);
            }
            (Ok(()), _) => {
                app.set_phase("Completed".into());
                app.set_progress(1.0);
            }
            (Err(e), _) => {
                app.set_phase(format!("Failed: {e}").into());
                app.set_error(e.into());
                app.set_progress(0.0);
            }
        }
    }
}

fn pick_input(folder: bool) -> Option<PathBuf> {
    let dialog =
        rfd::FileDialog::new().set_title(if folder { "Choose a batch folder" } else { "Choose a video or image" });
    if folder {
        dialog.pick_folder()
    } else {
        dialog.add_filter("Videos and images", &MEDIA_EXTENSIONS).pick_file()
    }
}

/// Connects the window to the backend: factory settings, the preview thread and every action.
fn wire(ui: &AppWindow) -> Arc<Mutex<State>> {
    settings::load(&ui.global::<Settings>(), &Options::default());
    ui.global::<App>().set_engine_version(engine::version().unwrap_or_else(|| "(not installed)".into()).into());
    if engine::version().is_none() {
        append_log(ui, "The MpVFX media engine is missing from this build; processing is unavailable.\n");
    }

    let (requests, worker_requests) = channel();
    let (worker_replies, replies) = channel();
    std::thread::spawn(move || preview::worker(worker_requests, worker_replies, || {}));
    let state = Arc::new(Mutex::new(State {
        input: None,
        cancel: Arc::new(AtomicBool::new(false)),
        reports: None,
        progress: Progress::default(),
        preview: requests,
        replies,
    }));

    let actions = ui.global::<Actions>();
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_import(move || {
        let Some(ui) = weak.upgrade() else { return };
        if let Some(path) = pick_input(false) {
            select_input(&ui, &mut st.lock().unwrap(), path);
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_import_folder(move || {
        let Some(ui) = weak.upgrade() else { return };
        if let Some(path) = pick_input(true) {
            select_input(&ui, &mut st.lock().unwrap(), path);
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_choose_output_folder(move || {
        let Some(ui) = weak.upgrade() else { return };
        if let Some(dir) = rfd::FileDialog::new().set_title("Choose the output folder").pick_folder() {
            let s = ui.global::<Settings>();
            s.set_output_folder(dir.display().to_string().into());
            s.set_custom_output(true);
            if let Some(input) = st.lock().unwrap().input.clone() {
                ui.global::<App>().set_predicted_output(predicted_output(&settings::options(&s), &input).into());
            }
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_run(move || {
        if let Some(ui) = weak.upgrade() {
            start(&ui, &mut st.lock().unwrap());
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_cancel(move || {
        if let Some(ui) = weak.upgrade() {
            st.lock().unwrap().cancel.store(true, Ordering::SeqCst);
            ui.global::<App>().set_cancelling(true);
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_reset_settings(move || {
        if let Some(ui) = weak.upgrade() {
            settings::load(&ui.global::<Settings>(), &Options::default());
            request_preview(&ui, &st.lock().unwrap());
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_settings_changed(move || {
        let Some(ui) = weak.upgrade() else { return };
        let s = ui.global::<Settings>();
        settings::update_ranges(&s);
        let state = st.lock().unwrap();
        if let Some(input) = &state.input {
            ui.global::<App>().set_predicted_output(predicted_output(&settings::options(&s), input).into());
        }
        if ui.global::<App>().get_show_processed() {
            request_preview(&ui, &state);
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_seek(move |seconds| {
        if let Some(ui) = weak.upgrade() {
            ui.global::<App>().set_position_text(progress::clock(seconds as f64).into());
            request_preview(&ui, &st.lock().unwrap());
        }
    });
    let (weak, st) = (ui.as_weak(), state.clone());
    actions.on_refresh_preview(move || {
        if let Some(ui) = weak.upgrade() {
            request_preview(&ui, &st.lock().unwrap());
        }
    });
    let weak = ui.as_weak();
    actions.on_clear_log(move || {
        if let Some(ui) = weak.upgrade() {
            ui.global::<App>().set_log(SharedString::new());
        }
    });

    state
}

fn main() -> Result<(), String> {
    let mut args = std::env::args().skip(1).peekable();
    if args.peek().map(String::as_str) == Some("--screenshot") {
        args.next();
        let shot = screenshot::Shot::parse(args)?;
        let input = shot.input.clone();
        return screenshot::take(&shot, |ui| {
            let state = wire(ui);
            if let Some(path) = input {
                select_input(ui, &mut state.lock().unwrap(), path);
            }
            Box::new(move |ui| drain(ui, &mut state.lock().unwrap()))
        });
    }

    let ui = AppWindow::new().map_err(|e| e.to_string())?;
    let state = wire(&ui);
    let timer = Timer::default();
    let (weak, st) = (ui.as_weak(), state.clone());
    timer.start(TimerMode::Repeated, Duration::from_millis(100), move || {
        if let Some(ui) = weak.upgrade() {
            drain(&ui, &mut st.lock().unwrap());
        }
    });

    if let Some(path) = args.next().map(PathBuf::from) {
        select_input(&ui, &mut state.lock().unwrap(), path);
    }
    ui.run().map_err(|e| e.to_string())
}
