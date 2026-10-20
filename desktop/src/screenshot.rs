//! Renders the window to a PNG without a display, with Slint's software renderer:
//! `myupscaler --screenshot out.png [--size 1280x800] [--inspector] [--page 0-3] [--log] [--about | --settings]
//! [--dark | --light] [--run [--after SECONDS]] [input]`.
//! `--run` presses Run and waits for processing to finish before taking the picture.
//! Used to review the interface in CI and on machines without a screen.

use std::rc::Rc;
use std::time::{Duration, Instant};

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::platform::{Platform, WindowAdapter};
use slint::{ComponentHandle, PhysicalSize, PlatformError};

use crate::{Actions, App, AppWindow, Theme, ThemePreference};

struct Headless(Rc<MinimalSoftwareWindow>);

impl Platform for Headless {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, PlatformError> {
        Ok(self.0.clone())
    }
}

pub struct Shot {
    pub path: std::path::PathBuf,
    pub size: (u32, u32),
    pub page: i32,
    pub inspector: bool,
    pub log: bool,
    pub about: bool,
    pub settings: bool,
    pub dark: bool,
    pub light: bool,
    pub run: bool,
    /// With `--run`: take the picture this long after starting instead of at the end.
    pub after: Option<f64>,
    pub input: Option<std::path::PathBuf>,
}

impl Shot {
    /// Reads the arguments after `--screenshot`.
    pub fn parse(mut args: impl Iterator<Item = String>) -> Result<Shot, String> {
        let path = args.next().ok_or("--screenshot needs an output .png path")?.into();
        let mut shot = Shot {
            path,
            size: (1280, 800),
            page: 0,
            inspector: false,
            log: false,
            about: false,
            settings: false,
            dark: false,
            light: false,
            run: false,
            after: None,
            input: None,
        };
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--size" => {
                    let v = args.next().ok_or("--size needs WIDTHxHEIGHT")?;
                    let (w, h) = v.split_once('x').ok_or("--size needs WIDTHxHEIGHT")?;
                    shot.size = (w.parse().map_err(|_| "bad width")?, h.parse().map_err(|_| "bad height")?);
                }
                "--page" => {
                    shot.page = args.next().and_then(|p| p.parse().ok()).ok_or("--page needs 0-3")?;
                    shot.inspector = true;
                }
                "--inspector" => shot.inspector = true,
                "--log" => shot.log = true,
                "--about" => shot.about = true,
                "--settings" => shot.settings = true,
                "--dark" => shot.dark = true,
                "--light" => shot.light = true,
                "--run" => shot.run = true,
                "--after" => {
                    shot.after = Some(args.next().and_then(|s| s.parse().ok()).ok_or("--after needs seconds")?)
                }
                other if other.starts_with("--") => return Err(format!("unknown screenshot option {other}")),
                other => shot.input = Some(other.into()),
            }
        }
        Ok(shot)
    }
}

/// Opens the window headless, lets `setup` populate it, waits until the preview settles and writes the PNG.
pub fn take(shot: &Shot, setup: impl FnOnce(&AppWindow) -> Box<dyn FnMut(&AppWindow)>) -> Result<(), String> {
    let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
    slint::platform::set_platform(Box::new(Headless(window.clone()))).map_err(|e| e.to_string())?;
    let ui = AppWindow::new().map_err(|e| e.to_string())?;
    window.set_size(PhysicalSize::new(shot.size.0, shot.size.1));
    ui.show().map_err(|e| e.to_string())?;
    let app = ui.global::<App>();
    app.set_page(shot.page);
    app.set_inspector_visible(shot.inspector);
    app.set_log_open(shot.log);
    app.set_about_open(shot.about);
    app.set_settings_open(shot.settings);
    if shot.dark {
        ui.global::<Theme>().set_preference(ThemePreference::Dark);
    } else if shot.light {
        ui.global::<Theme>().set_preference(ThemePreference::Light);
    }
    let mut tick = setup(&ui);
    if shot.run {
        ui.global::<Actions>().invoke_run();
    }
    // Give the preview thread time to answer (the filtered preview can take seconds), and processing time to finish.
    let started = Instant::now();
    let deadline = started + Duration::from_secs(600);
    loop {
        slint::platform::update_timers_and_animations();
        tick(&ui);
        let waiting = app.get_preview_busy() || app.get_thumbnails_loading() || app.get_running();
        let captured = shot.after.is_some_and(|s| started.elapsed().as_secs_f64() >= s);
        if !waiting || captured || Instant::now() > deadline {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    slint::platform::update_timers_and_animations();
    let snapshot = ui.window().take_snapshot().map_err(|e| e.to_string())?;
    if app.get_running() {
        ui.global::<Actions>().invoke_cancel();
    }
    let rgba: Vec<u8> = snapshot.as_slice().iter().flat_map(|p| [p.r, p.g, p.b, p.a]).collect();
    up60p::png::write(&shot.path, &rgba, snapshot.width(), snapshot.height(), false).map_err(|e| e.to_string())
}
