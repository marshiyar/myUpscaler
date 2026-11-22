//! The file dialog and the system's default applications.
use std::path::{Path, PathBuf};

use crate::dropped::MEDIA_EXTENSIONS;

pub fn pick_input(folder: bool) -> Option<PathBuf> {
    let dialog =
        rfd::FileDialog::new().set_title(if folder { "Choose a batch folder" } else { "Choose a video or image" });
    if folder {
        dialog.pick_folder()
    } else {
        dialog.add_filter("Videos and images", &MEDIA_EXTENSIONS).pick_file()
    }
}

/// Opens a file or web address with the system's default application, or shows a file in its folder.
pub fn open_with_system(target: &str, reveal: bool) {
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
