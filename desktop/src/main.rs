//! myUpscaler for macOS, Windows and Linux: the Slint interface (`ui/`, laid out as the macOS app) on the Rust
//! processing backend (`backend/`). Processing, the preview, the frame strip and the player run on their own threads
//! and report back through channels that timers on the interface thread drain, so the window never waits on the
//! engine.

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

mod playback;
mod player;
mod presets;
mod preview;
mod progress;
mod screenshot;
mod settings;

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use slint::{ComponentHandle, Image, ModelRc, Rgba8Pixel, SharedPixelBuffer, SharedString, Timer, TimerMode, VecModel};
use up60p::engine;
use up60p::job::{self, Job};
use up60p::options::Options;

use presets::Preset;
use progress::Progress;

slint::include_modules!();

/// What the processing thread reports.
enum Report {
    Log(String),
    Finished { result: Result<(), String>, cancelled: bool },
}

/// A batch of the frame strip, for the input it was made for (its generation).
type Thumbnails = (u64, Vec<(SharedPixelBuffer<Rgba8Pixel>, f64)>);

/// Inputs the file dialog offers: what the backend processes.
const MEDIA_EXTENSIONS: [&str; 12] =
    ["mp4", "mov", "m4v", "mkv", "webm", "png", "jpg", "jpeg", "bmp", "webp", "tif", "tiff"];

/// The longest the log may grow before its oldest lines are dropped.
const LOG_LIMIT: usize = 200_000;

const WEBSITE: &str = "https://github.com/marshiyar/myUpscaler";

struct State {
    input: Option<PathBuf>,
    cancel: Arc<AtomicBool>,
    reports: Option<Receiver<Report>>,
    progress: Progress,
    /// Where the finished export is, once a run completed.
    completed: Option<PathBuf>,
    expected: Option<PathBuf>,
    preview: Sender<preview::Request>,
    replies: Receiver<preview::Reply>,
    thumbnail_tx: Sender<Thumbnails>,
    thumbnail_rx: Receiver<Thumbnails>,
    /// Bumped for every input, so a strip still loading for an earlier one stops and its batches are ignored.
    generation: Arc<AtomicU64>,
    thumbnail_times: Vec<f64>,
    thumbnails: Rc<VecModel<Image>>,
    thumbnail_labels: Rc<VecModel<SharedString>>,
    presets: Vec<Preset>,
    preset_file: Option<PathBuf>,
    player: Sender<player::Command>,
    player_events: Receiver<player::Event>,
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

fn output_path(options: &Options, input: &Path) -> PathBuf {
    let cancel = AtomicBool::new(false);
    let log = |_: &str| {};
    Job { options, log: &log, cancel: &cancel, dry_run: true }.output_path(input)
}

/// The output file's name, as the macOS app's Output page shows it.
fn predicted_output(options: &Options, input: &Path) -> String {
    if input.is_dir() {
        return "One <name>_[restored] file per video or image".into();
    }
    output_path(options, input).file_name().map_or_else(String::new, |n| n.to_string_lossy().into_owned())
}

/// The bottom bar's status line, in the macOS app's words.
fn update_status(ui: &AppWindow, state: &State) {
    let app = ui.global::<App>();
    let status = if app.get_cancelling() {
        "Stopping…"
    } else if app.get_running() {
        match state.progress.phase {
            Some("Finalizing") | Some("Done") => "Finalizing export…",
            Some(_) => "Processing frames",
            None => "Preparing video…",
        }
    } else if state.completed.is_some() {
        "Export complete"
    } else if state.input.is_none() {
        "Import a video to begin"
    } else {
        "Ready to export"
    };
    app.set_status(status.into());
}

fn request_preview(ui: &AppWindow, state: &State) {
    let app = ui.global::<App>();
    let Some(input) = state.input.clone().filter(|p| p.is_file()) else {
        app.set_has_preview(false);
        app.set_preview_note("Folder selected: every video and image in it is processed.".into());
        return;
    };
    let seconds = app.get_position() as f64;
    let filters = Some(Box::new(settings::options(&ui.global::<Settings>())));
    app.set_preview_busy(true);
    let _ = state.preview.send(preview::Request { path: input, seconds, filters });
}

fn select_input(ui: &AppWindow, state: &mut State, path: PathBuf) {
    let app = ui.global::<App>();
    let name = path.file_name().map_or_else(|| path.display().to_string(), |n| n.to_string_lossy().into_owned());
    app.set_input_path(path.display().to_string().into());
    app.set_input_name(name.into());
    app.set_is_image(job::is_image(&path));
    app.set_has_preview(false);
    app.set_preview_note(SharedString::new());
    app.set_selected_frame(0);
    let duration = engine::Video::open(&path).ok().filter(|v| !v.is_still).map_or(0.0, |v| v.duration);
    app.set_duration(duration as f32);
    app.set_duration_text(progress::clock(duration).into());
    app.set_position(0.0);
    app.set_position_text(progress::clock(0.0).into());
    app.set_playing(false);
    app.set_source(0);
    app.set_has_result(false);
    app.set_can_play(duration > 0.0);
    if duration > 0.0 {
        let _ = state.player.send(player::Command::Load(path.clone()));
    }
    state.completed = None;
    app.set_completed(false);
    app.set_completed_output(SharedString::new());
    app.set_progress(0.0);
    let options = settings::options(&ui.global::<Settings>());
    app.set_predicted_output(predicted_output(&options, &path).into());
    state.input = Some(path.clone());

    // The frame strip, decoded on its own thread.
    let generation = state.generation.fetch_add(1, Ordering::SeqCst) + 1;
    state.thumbnail_times.clear();
    state.thumbnails.set_vec(Vec::new());
    state.thumbnail_labels.set_vec(Vec::new());
    let videoish = path.is_file() && !job::is_image(&path);
    app.set_thumbnails_loading(videoish);
    if videoish {
        let (tx, current) = (state.thumbnail_tx.clone(), state.generation.clone());
        std::thread::spawn(move || {
            let still = || current.load(Ordering::SeqCst) == generation;
            let send = |batch| tx.send((generation, batch)).is_ok();
            let _ = preview::thumbnails(&path, send, still);
            let _ = tx.send((generation, Vec::new()));
        });
    }
    update_status(ui, state);
    request_preview(ui, state);
}

fn start(ui: &AppWindow, state: &mut State) {
    let Some(input) = state.input.clone() else { return };
    let app = ui.global::<App>();
    let options = settings::options(&ui.global::<Settings>());
    let (tx, rx) = channel();
    state.reports = Some(rx);
    state.progress = Progress::default();
    state.completed = None;
    state.cancel.store(false, Ordering::SeqCst);
    let cancel = state.cancel.clone();
    app.set_running(true);
    app.set_cancelling(false);
    app.set_completed(false);
    app.set_completed_output(SharedString::new());
    // The export replaces the result file, which the player must not hold open (Windows cannot replace an open
    // file), and playback is paused while the preview is frozen.
    let _ = state.player.send(player::Command::Pause);
    if app.get_source() == 1 {
        playback::set_source(ui, state, 0);
    }
    app.set_has_result(false);
    app.set_progress_known(false);
    app.set_progress(0.0);
    app.set_fps_text("0".into());
    app.set_time_text("0:00".into());
    app.set_eta_text("--:--".into());

    let output = output_path(&options, &input);
    let folder = output.parent().map(Path::to_path_buf).unwrap_or_default();
    state.expected = Some(if input.is_dir() { folder.clone() } else { output.clone() });
    app.set_log(SharedString::new());
    append_log(ui, "--- Starting Rust Engine ---\n");
    append_log(ui, &format!("Input: {}\nOutput: {}\n\n", input.display(), folder.display()));
    if !input.is_dir() {
        append_log(ui, &format!("Expected output file: {}\n\n", output.display()));
    }
    if engine::version().is_none() {
        append_log(ui, "The MpVFX media engine is missing from this build; processing is unavailable.\n");
    }
    update_status(ui, state);
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

/// Applies what the processing, preview and frame-strip threads reported since the last tick.
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
    while let Ok((generation, batch)) = state.thumbnail_rx.try_recv() {
        if generation != state.generation.load(Ordering::SeqCst) {
            continue;
        }
        if batch.is_empty() {
            app.set_thumbnails_loading(false);
        }
        for (buffer, time) in batch {
            state.thumbnail_times.push(time);
            state.thumbnails.push(Image::from_rgba8(buffer));
            state.thumbnail_labels.push(progress::clock(time).into());
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
    app.set_progress_known(p.fraction.is_some() && p.phase == Some("Processing"));
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
        match (result, cancelled) {
            (_, true) => app.set_progress(0.0),
            (Ok(()), _) => {
                state.completed = state.expected.take();
                app.set_completed(true);
                app.set_progress(1.0);
                app.set_eta_text("0:00".into());
                let path = state.completed.as_ref().map_or_else(String::new, |p| p.display().to_string());
                app.set_completed_output(path.into());
                let video = state.completed.as_ref().is_some_and(|p| p.is_file() && !job::is_image(p));
                app.set_has_result(video && app.get_can_play());
                append_log(ui, "\n--- Process Finished Successfully ---\n");
            }
            (Err(e), _) => {
                app.set_progress(0.0);
                append_log(ui, &format!("\n--- ERROR: {e} ---\n"));
                app.set_log_open(true);
            }
        }
    }
    update_status(ui, state);
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

/// Opens a file or web address with the system's default application, or shows a file in its folder.
fn open_with_system(target: &str, reveal: bool) {
    let mut command = if cfg!(target_os = "macos") {
        let mut c = std::process::Command::new("open");
        if reveal {
            c.arg("-R");
        }
        c.arg(target);
        c
    } else if cfg!(windows) {
        let mut c = std::process::Command::new("explorer");
        c.arg(if reveal { format!("/select,{target}") } else { target.to_owned() });
        c
    } else {
        let mut c = std::process::Command::new("xdg-open");
        let path = Path::new(target);
        c.arg(if reveal { path.parent().unwrap_or(path) } else { path });
        c
    };
    let _ = command.spawn();
}

fn settings_changed(ui: &AppWindow, state: &State) {
    settings::update_ranges(&ui.global::<Settings>());
    if let Some(input) = &state.input {
        let options = settings::options(&ui.global::<Settings>());
        ui.global::<App>().set_predicted_output(predicted_output(&options, input).into());
    }
    request_preview(ui, state);
}

/// Runs `f` with the window and the state, when the window still exists.
fn with(ui: &slint::Weak<AppWindow>, state: &Rc<RefCell<State>>, f: impl FnOnce(&AppWindow, &mut State)) {
    if let Some(ui) = ui.upgrade() {
        f(&ui, &mut state.borrow_mut());
    }
}

/// Connects the window to the backend: factory settings, the preview thread, presets and every action.
fn wire(ui: &AppWindow) -> Rc<RefCell<State>> {
    settings::load(&ui.global::<Settings>(), &Options::default());
    let app = ui.global::<App>();
    app.set_engine_version(engine::version().unwrap_or_else(|| "(not installed)".into()).into());
    app.set_version(env!("CARGO_PKG_VERSION").into());
    app.set_mac(cfg!(target_os = "macos"));
    let list = |items: &[&str]| ModelRc::new(VecModel::from(items.iter().map(|&i| i.into()).collect::<Vec<_>>()));
    app.set_hwaccels(list(settings::hwaccels()));
    app.set_encoders(list(settings::encoders()));
    let thumbnails = Rc::new(VecModel::default());
    let thumbnail_labels = Rc::new(VecModel::default());
    app.set_thumbnails(ModelRc::from(thumbnails.clone()));
    app.set_thumbnail_times(ModelRc::from(thumbnail_labels.clone()));

    let (requests, worker_requests) = channel();
    let (worker_replies, replies) = channel();
    std::thread::spawn(move || preview::worker(worker_requests, worker_replies, || {}));
    let (thumbnail_tx, thumbnail_rx) = channel();
    let (player, player_commands) = channel();
    let (player_send, player_events) = channel();
    std::thread::spawn(move || player::worker(player_commands, player_send));
    let preset_file = presets::file();
    let state = Rc::new(RefCell::new(State {
        input: None,
        cancel: Arc::new(AtomicBool::new(false)),
        reports: None,
        progress: Progress::default(),
        completed: None,
        expected: None,
        preview: requests,
        replies,
        thumbnail_tx,
        thumbnail_rx,
        generation: Arc::new(AtomicU64::new(0)),
        thumbnail_times: Vec::new(),
        thumbnails,
        thumbnail_labels,
        presets: preset_file.as_deref().map(presets::load).unwrap_or_default(),
        preset_file,
        player,
        player_events,
    }));
    presets::refresh(ui, &state.borrow());

    let actions = ui.global::<Actions>();
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_import(move || {
        if let Some(path) = pick_input(false) {
            with(&w, &st, |ui, s| select_input(ui, s, path));
        }
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_import_folder(move || {
        if let Some(path) = pick_input(true) {
            with(&w, &st, |ui, s| select_input(ui, s, path));
        }
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_choose_output_folder(move || {
        if let Some(dir) = rfd::FileDialog::new().set_title("Choose the output folder").pick_folder() {
            with(&w, &st, |ui, s| {
                let settings = ui.global::<Settings>();
                settings.set_output_folder(dir.display().to_string().into());
                settings.set_custom_output(true);
                settings_changed(ui, s);
            });
        }
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_run(move || with(&w, &st, start));
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_cancel(move || {
        with(&w, &st, |ui, s| {
            s.cancel.store(true, Ordering::SeqCst);
            ui.global::<App>().set_cancelling(true);
            append_log(ui, "\n--- User Canceled Process (stopping engine) ---\n");
            update_status(ui, s);
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_reset_settings(move || {
        with(&w, &st, |ui, s| {
            let settings = ui.global::<Settings>();
            let (custom, folder) = (settings.get_custom_output(), settings.get_output_folder());
            settings::load(&settings, &Options::default());
            settings.set_custom_output(custom);
            settings.set_output_folder(folder);
            settings_changed(ui, s);
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_settings_changed(move || with(&w, &st, |ui, s| settings_changed(ui, s)));
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_open_output(move || {
        with(&w, &st, |_, s| s.completed.iter().for_each(|p| open_with_system(&p.display().to_string(), false)))
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_reveal_output(move || {
        with(&w, &st, |_, s| s.completed.iter().for_each(|p| open_with_system(&p.display().to_string(), true)))
    });
    actions.on_open_website(|| open_with_system(WEBSITE, false));
    playback::wire(ui, &state);
    presets::wire(ui, &state);

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
                select_input(ui, &mut state.borrow_mut(), path);
            }
            Box::new(move |ui| {
                drain(ui, &mut state.borrow_mut());
                playback::drain(ui, &mut state.borrow_mut());
            })
        });
    }

    let ui = AppWindow::new().map_err(|e| e.to_string())?;
    let state = wire(&ui);
    let timer = Timer::default();
    let (w, st) = (ui.as_weak(), state.clone());
    timer.start(TimerMode::Repeated, Duration::from_millis(100), move || with(&w, &st, drain));
    // Frames from the player, at display rate.
    let player_timer = Timer::default();
    let (w, st) = (ui.as_weak(), state.clone());
    player_timer.start(TimerMode::Repeated, Duration::from_millis(8), move || with(&w, &st, playback::drain));

    if let Some(path) = args.next().map(PathBuf::from) {
        select_input(&ui, &mut state.borrow_mut(), path);
    }
    ui.run().map_err(|e| e.to_string())
}
