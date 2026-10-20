//! Renders the window to a PNG without a display, with Slint's software renderer:
//! `myupscaler --screenshot out.png [--size 1180x780] [--page 0-3] [--dark] [--processed] [--run] [input]`.
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
    pub dark: bool,
    pub processed: bool,
    pub run: bool,
    pub input: Option<std::path::PathBuf>,
}

impl Shot {
    /// Reads the arguments after `--screenshot`.
    pub fn parse(mut args: impl Iterator<Item = String>) -> Result<Shot, String> {
        let path = args.next().ok_or("--screenshot needs an output .png path")?.into();
        let mut shot =
            Shot { path, size: (1180, 780), page: 0, dark: false, processed: false, run: false, input: None };
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--size" => {
                    let v = args.next().ok_or("--size needs WIDTHxHEIGHT")?;
                    let (w, h) = v.split_once('x').ok_or("--size needs WIDTHxHEIGHT")?;
                    shot.size = (w.parse().map_err(|_| "bad width")?, h.parse().map_err(|_| "bad height")?);
                }
                "--page" => shot.page = args.next().and_then(|p| p.parse().ok()).ok_or("--page needs 0-3")?,
                "--dark" => shot.dark = true,
                "--processed" => shot.processed = true,
                "--run" => shot.run = true,
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
    app.set_show_processed(shot.processed);
    if shot.dark {
        ui.global::<Theme>().set_preference(ThemePreference::Dark);
    }
    let mut tick = setup(&ui);
    if shot.run {
        ui.global::<Actions>().invoke_run();
    }
    // Give the preview thread time to answer (the filtered preview can take seconds), and processing time to finish.
    let deadline = Instant::now() + Duration::from_secs(600);
    loop {
        slint::platform::update_timers_and_animations();
        tick(&ui);
        let waiting = app.get_preview_busy() || app.get_running();
        if !waiting || Instant::now() > deadline {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    slint::platform::update_timers_and_animations();
    let snapshot = ui.window().take_snapshot().map_err(|e| e.to_string())?;
    let rgba: Vec<u8> = snapshot.as_slice().iter().flat_map(|p| [p.r, p.g, p.b, p.a]).collect();
    up60p::png::write(&shot.path, &rgba, snapshot.width(), snapshot.height(), false).map_err(|e| e.to_string())
}
