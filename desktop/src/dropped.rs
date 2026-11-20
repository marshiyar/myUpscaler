//! Files dropped on the window: which dropped item becomes the import.
//!
//! Slint's own `DropArea` does not receive files from the operating system in 1.18, so the window's winit events
//! are used (see `accept_drops` in `main.rs`): `HoveredFile` / `HoveredFileCancelled` drive the highlight and
//! `DroppedFile` the import. winit reports file drops on Windows, macOS and X11; Wayland sessions send none.

use std::path::{Path, PathBuf};

/// Extensions the Import button's file dialog offers.
pub const MEDIA_EXTENSIONS: [&str; 12] =
    ["mp4", "mov", "m4v", "mkv", "webm", "png", "jpg", "jpeg", "bmp", "webp", "tif", "tiff"];

/// A dropped item as a path: a plain path, or a `file://` URI with percent-encoding (as file managers on Linux
/// send them). Returns `None` for other URI schemes and for empty items.
pub fn item_path(item: &str) -> Option<PathBuf> {
    let item = item.trim();
    let Some(rest) = item.strip_prefix("file://") else {
        return if item.is_empty() || item.contains("://") { None } else { Some(PathBuf::from(item)) };
    };
    // `file://host/path` and `file:///path`; a Windows URI is `file:///C:/dir/clip.mp4`.
    let path = &rest[rest.find('/')?..];
    let decoded = percent_decode(path);
    let bytes = decoded.as_bytes();
    let drive = bytes.len() >= 3 && bytes[0] == b'/' && bytes[1].is_ascii_alphabetic() && bytes[2] == b':';
    Some(PathBuf::from(if drive { &decoded[1..] } else { decoded.as_str() }))
}

fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let hex = |i: usize| bytes.get(i).and_then(|&b| (b as char).to_digit(16)).map(|d| d as u8);
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match (bytes[i], hex(i + 1), hex(i + 2)) {
            (b'%', Some(high), Some(low)) => {
                out.push(high * 16 + low);
                i += 3;
            }
            (byte, ..) => {
                out.push(byte);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Whether the Import button would accept this file: a video or image extension.
fn is_media(path: &Path) -> bool {
    path.extension().is_some_and(|e| MEDIA_EXTENSIONS.iter().any(|m| e.eq_ignore_ascii_case(m)))
}

/// The import for a drop: the first item that is a folder (imported as a batch folder) or a video or image file.
pub fn import_target<S: AsRef<str>>(items: &[S]) -> Option<PathBuf> {
    items.iter().filter_map(|i| item_path(i.as_ref())).find(|p| p.is_dir() || (p.is_file() && is_media(p)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("myupscaler-drop-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn touch(path: &Path) {
        std::fs::write(path, b"x").unwrap();
    }

    #[test]
    fn plain_path() {
        let clip = temp("plain").join("clip.MP4");
        touch(&clip);
        assert_eq!(import_target(&[clip.display().to_string()]), Some(clip));
    }

    #[test]
    fn file_uri_with_spaces() {
        let clip = temp("uri").join("my clip.mkv");
        touch(&clip);
        let path = clip.display().to_string().replace('\\', "/").replace(' ', "%20");
        let uri = format!("file:///{}", path.trim_start_matches('/'));
        // On Unix the leading slash is part of the path, on Windows the drive letter follows the three slashes.
        let uri = if cfg!(windows) { uri } else { format!("file://{path}") };
        assert_eq!(import_target(&[uri]), Some(clip));
    }

    #[test]
    fn uri_forms() {
        assert_eq!(item_path("file:///home/me/a%20b.mp4"), Some(PathBuf::from("/home/me/a b.mp4")));
        assert_eq!(item_path("file://localhost/tmp/a.mp4"), Some(PathBuf::from("/tmp/a.mp4")));
        assert_eq!(item_path("file:///C:/Users/me/a%20b.mp4"), Some(PathBuf::from("C:/Users/me/a b.mp4")));
        assert_eq!(item_path("file:///tmp/100%25.mp4"), Some(PathBuf::from("/tmp/100%.mp4")));
        assert_eq!(item_path("https://example.com/a.mp4"), None);
    }

    #[test]
    fn windows_drive_path() {
        assert_eq!(item_path(r"C:\Users\me\clip.mp4"), Some(PathBuf::from(r"C:\Users\me\clip.mp4")));
    }

    #[test]
    fn directory_imports_as_folder() {
        let dir = temp("folder");
        assert_eq!(import_target(&[dir.display().to_string()]), Some(dir));
    }

    #[test]
    fn empty_list() {
        assert_eq!(import_target::<String>(&[]), None);
        assert_eq!(import_target(&[""]), None);
    }

    #[test]
    fn other_files_are_rejected() {
        let dir = temp("other");
        let text = dir.join("notes.txt");
        touch(&text);
        assert_eq!(import_target(&[text.display().to_string()]), None);
        assert_eq!(import_target(&[dir.join("missing.mp4").display().to_string()]), None);
    }

    #[test]
    fn first_accepted_item_wins() {
        let dir = temp("many");
        let (a, b) = (dir.join("a.mov"), dir.join("b.mp4"));
        touch(&a);
        touch(&b);
        let items = [dir.join("n.txt").display().to_string(), a.display().to_string(), b.display().to_string()];
        assert_eq!(import_target(&items), Some(a));
    }
}
