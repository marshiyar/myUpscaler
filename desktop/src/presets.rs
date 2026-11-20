//! Saved presets, as in the macOS app's Output page: named copies of every processing setting. They live in
//! `presets.txt` in the per-user settings folder, one `[name]` header per preset followed by `field=value` lines
//! (the backend's option names), so the file is readable and survives new options: a field it lacks keeps its
//! factory value. The output folder and per-file timing are not part of a preset.

use std::path::{Path, PathBuf};

use std::cell::RefCell;
use std::rc::Rc;

use slint::{ComponentHandle, ModelRc, SharedString, VecModel};
use up60p::options::{Options, FIELDS};

use crate::{append_log, settings, settings_changed, with, Actions, App, AppWindow, Settings, State};

/// Fields that describe one run or one machine rather than a look.
const EXCLUDED: [&str; 8] = [
    "outdir",
    "ai_model",
    "preview",
    "source_video_duration",
    "source_rate_num",
    "source_rate_den",
    "source_cfr_verified",
    "source_frame_count",
];

#[derive(Clone)]
pub struct Preset {
    pub name: String,
    pub options: Options,
}

/// The per-user settings folder: Application Support on macOS, %APPDATA% on Windows, XDG_CONFIG_HOME elsewhere.
pub fn settings_dir() -> Option<PathBuf> {
    let var = |name: &str| std::env::var_os(name).filter(|v| !v.is_empty()).map(PathBuf::from);
    let base = if cfg!(target_os = "macos") {
        var("HOME").map(|h| h.join("Library/Application Support"))
    } else if cfg!(windows) {
        var("APPDATA")
    } else {
        var("XDG_CONFIG_HOME").or_else(|| var("HOME").map(|h| h.join(".config")))
    }?;
    Some(base.join(if cfg!(any(target_os = "macos", windows)) { "myUpscaler" } else { "myupscaler" }))
}

pub fn file() -> Option<PathBuf> {
    settings_dir().map(|d| d.join("presets.txt"))
}

pub fn parse(text: &str) -> Vec<Preset> {
    let mut presets: Vec<Preset> = Vec::new();
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            presets.push(Preset { name: name.to_owned(), options: Options::default() });
        } else if let (Some(preset), Some((key, value))) = (presets.last_mut(), line.split_once('=')) {
            if !EXCLUDED.contains(&key.trim()) {
                // A value that no longer parses keeps the factory one.
                let _ = preset.options.set_field(key.trim(), value);
            }
        }
    }
    presets
}

pub fn format(presets: &[Preset]) -> String {
    let mut out = String::from("# myUpscaler presets: [name], then field=value lines (backend option names).\n");
    for p in presets {
        out.push_str(&format!("\n[{}]\n", p.name.replace(['[', ']', '\n'], "")));
        for (name, _) in FIELDS.iter().filter(|(n, _)| !EXCLUDED.contains(n)) {
            out.push_str(&format!("{name}={}\n", p.options.get(name).unwrap_or_default()));
        }
    }
    out
}

/// The saved presets and, when the file had to be set aside, a message for the user.
pub struct Loaded {
    pub presets: Vec<Preset>,
    pub message: Option<String>,
}

/// Reads the presets. A missing file is an empty list. A file that is unreadable, not UTF-8 text or holds no preset
/// is moved to `presets.txt.bad` (replacing an older one) so the next save cannot overwrite it.
pub fn load(path: &Path) -> Loaded {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Loaded { presets: Vec::new(), message: None },
        Err(e) => return set_aside(path, &format!("could not be read ({e})")),
    };
    let presets = parse(&text);
    if presets.is_empty()
        && !text.trim().is_empty()
        && !text.lines().all(|l| l.trim().is_empty() || l.trim().starts_with('#'))
    {
        return set_aside(path, "held no presets");
    }
    Loaded { presets, message: None }
}

fn set_aside(path: &Path, why: &str) -> Loaded {
    let bad = path.with_extension("txt.bad");
    let _ = std::fs::remove_file(&bad);
    let kept = std::fs::rename(path, &bad).or_else(|_| std::fs::copy(path, &bad).map(|_| ()));
    let message = match kept {
        Ok(()) => format!("The saved presets file {why}. It was kept as {}.", bad.display()),
        Err(e) => format!("The saved presets file {why}, and a copy could not be made: {e}."),
    };
    Loaded { presets: Vec::new(), message: Some(message) }
}

pub fn save(path: &Path, presets: &[Preset]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    // Written beside and renamed, so a failed write never loses the saved presets.
    let partial = path.with_extension("txt.partial");
    std::fs::write(&partial, format(presets))?;
    std::fs::rename(partial, path)
}

/// A name not yet used: `name`, or `name 2`, `name 3`…
pub fn unique_name(presets: &[Preset], name: &str) -> String {
    let taken = |n: &str| presets.iter().any(|p| p.name == n);
    if !taken(name) {
        return name.to_owned();
    }
    (2..).map(|i| format!("{name} {i}")).find(|n| !taken(n)).expect("an unused name")
}

// The Saved Presets section's actions.

/// Shows the saved presets' names.
pub fn refresh(ui: &AppWindow, state: &State) {
    let names: Vec<SharedString> = state.presets.iter().map(|p| p.name.as_str().into()).collect();
    ui.global::<App>().set_presets(ModelRc::new(VecModel::from(names)));
}

fn store(ui: &AppWindow, state: &State) {
    if let Some(file) = &state.preset_file {
        if let Err(e) = save(file, &state.presets) {
            append_log(ui, &format!("The presets could not be saved to {}: {e}\n", file.display()));
        }
    }
    refresh(ui, state);
}

/// Shows a preset's settings, keeping the current output folder.
fn apply(ui: &AppWindow, state: &State, preset: &Preset) {
    let s = ui.global::<Settings>();
    let mut options = preset.options.clone();
    up60p::options::set(&mut options.outdir, &if s.get_custom_output() { s.get_output_folder() } else { "".into() });
    settings::load(&s, &options);
    settings_changed(ui, state);
}

/// Connects the Saved Presets actions.
pub fn wire(ui: &AppWindow, state: &Rc<RefCell<State>>) {
    let actions = ui.global::<Actions>();
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_save_preset(move |name| {
        with(&w, &st, |ui, s| {
            let name = name.trim();
            if name.is_empty() {
                return;
            }
            let name = unique_name(&s.presets, name);
            s.presets.push(Preset { name, options: settings::options(&ui.global::<Settings>()) });
            store(ui, s);
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_apply_preset(move |i| {
        with(&w, &st, |ui, s| {
            if let Some(preset) = s.presets.get(i as usize).cloned() {
                apply(ui, s, &preset);
            }
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_update_preset(move |i| {
        with(&w, &st, |ui, s| {
            if let Some(preset) = s.presets.get_mut(i as usize) {
                preset.options = settings::options(&ui.global::<Settings>());
                store(ui, s);
            }
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_rename_preset(move |i, name| {
        with(&w, &st, |ui, s| {
            let name = name.trim();
            let i = i as usize;
            if name.is_empty() || i >= s.presets.len() || s.presets[i].name == name {
                return;
            }
            let others: Vec<Preset> =
                s.presets.iter().enumerate().filter(|(j, _)| *j != i).map(|(_, p)| p.clone()).collect();
            s.presets[i].name = unique_name(&others, name);
            store(ui, s);
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_duplicate_preset(move |i| {
        with(&w, &st, |ui, s| {
            if let Some(preset) = s.presets.get(i as usize).cloned() {
                let name = unique_name(&s.presets, &format!("{} copy", preset.name));
                s.presets.insert(i as usize + 1, Preset { name, ..preset });
                store(ui, s);
            }
        })
    });
    let (w, st) = (ui.as_weak(), state.clone());
    actions.on_delete_preset(move |i| {
        with(&w, &st, |ui, s| {
            if (i as usize) < s.presets.len() {
                s.presets.remove(i as usize);
                store(ui, s);
            }
        })
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use up60p::options::{set, text};

    #[test]
    fn presets_round_trip_and_skip_per_run_fields() {
        let mut o = Options::default();
        set(&mut o.denoiser, "nlmeans");
        set(&mut o.outdir, "/somewhere");
        o.no_grain = 1;
        let presets = vec![Preset { name: "Clean [film]".into(), options: o }];
        let back = parse(&format(&presets));
        assert_eq!(back.len(), 1);
        assert_eq!(back[0].name, "Clean film");
        assert_eq!(text(&back[0].options.denoiser), "nlmeans");
        assert_eq!(back[0].options.no_grain, 1);
        assert_eq!(text(&back[0].options.outdir), "");
    }

    #[test]
    fn unknown_or_bad_lines_keep_the_factory_value() {
        let back = parse("[A]\nno_grain=maybe\nnot_an_option=1\ncrf=18\n");
        assert_eq!((back[0].options.no_grain, text(&back[0].options.crf).as_str()), (0, "18"));
    }

    #[test]
    fn names_are_made_unique() {
        let p = |n: &str| Preset { name: n.into(), options: Options::default() };
        let presets = [p("Film"), p("Film 2")];
        assert_eq!(unique_name(&presets, "Film"), "Film 3");
        assert_eq!(unique_name(&presets, "Video"), "Video");
    }

    #[test]
    fn saving_creates_the_folder() {
        let dir = std::env::temp_dir().join(format!("myupscaler-presets-{}", std::process::id()));
        let path = dir.join("nested/presets.txt");
        save(&path, &[Preset { name: "A".into(), options: Options::default() }]).unwrap();
        assert_eq!(load(&path).presets.len(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("myupscaler-presets-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn set_aside_case(name: &str, bytes: &[u8]) {
        let dir = temp(name);
        let path = dir.join("presets.txt");
        std::fs::write(&path, bytes).unwrap();
        let loaded = load(&path);
        assert!(loaded.presets.is_empty());
        assert!(loaded.message.is_some());
        assert!(!path.exists());
        assert_eq!(std::fs::read(dir.join("presets.txt.bad")).unwrap(), bytes);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_non_utf8_file_is_kept_as_bad() {
        set_aside_case("binary", &[0xff, 0xfe, 0x00, 0x9f, 0x92]);
    }

    #[test]
    fn a_file_without_presets_is_kept_as_bad() {
        set_aside_case(
            "garbage",
            b"this is not a preset file
at all
",
        );
    }

    #[test]
    fn an_older_bad_file_is_replaced() {
        let dir = temp("replace");
        std::fs::write(dir.join("presets.txt.bad"), "old").unwrap();
        std::fs::write(dir.join("presets.txt"), "junk").unwrap();
        assert!(load(&dir.join("presets.txt")).message.is_some());
        assert_eq!(std::fs::read_to_string(dir.join("presets.txt.bad")).unwrap(), "junk");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_missing_file_is_empty_without_a_message() {
        let dir = temp("missing");
        let loaded = load(&dir.join("presets.txt"));
        assert!(loaded.presets.is_empty() && loaded.message.is_none());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_valid_file_is_left_alone() {
        let dir = temp("valid");
        let path = dir.join("presets.txt");
        save(&path, &[Preset { name: "A".into(), options: Options::default() }]).unwrap();
        let loaded = load(&path);
        assert_eq!(loaded.presets.len(), 1);
        assert!(loaded.message.is_none() && path.exists() && !dir.join("presets.txt.bad").exists());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn saving_under_a_regular_file_fails() {
        let dir = temp("unwritable");
        let blocker = dir.join("file");
        std::fs::write(&blocker, "x").unwrap();
        assert!(save(&blocker.join("presets.txt"), &[]).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
