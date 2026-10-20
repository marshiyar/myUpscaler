# myUpscaler desktop (macOS, Windows, Linux)

The cross-platform version of myUpscaler: a [Slint](https://slint.dev) interface on the same Rust processing
backend (`../backend`) the macOS app uses, with the same settings. It looks and works like the macOS app
(`../myUpscaler/Views`): a toolbar (Import; the adjustments panel, Settings and About), the input card (the import
view, or the imported video's adjusted preview with a player and its frame strip), the processing details card, the adjustments
panel docked on the right (Upscale, Restore, Processor and Output pages as a grouped form, saved presets included),
and the bottom bar with the progress and the Export button. The controls are drawn like their macOS counterparts with
macOS system colours, in light and dark appearance, and Inter is embedded, so the app looks the same on macOS,
Windows and Linux. The macOS app's keyboard shortcuts work everywhere (Ctrl for ⌘).

```sh
bash ../scripts/prepare-media-engine.sh   # the media engine (macOS arm64, Linux x86_64, Windows x86_64)
cargo run --release                        # or: cargo run --release -- path/to/video.mp4
```

On Linux the build needs the fontconfig and ALSA development packages (`libfontconfig1-dev libasound2-dev` on
Debian and Ubuntu). On Windows, run the first line from Git Bash (it comes with Git for Windows) and build with the MSVC toolchain (Visual
Studio Build Tools, "Desktop development with C++"). The build copies the engine's `mpvfx_ffi.dll` next to
`target\release\myupscaler.exe`; the two files together are the app. CI builds the same pair as the
`myupscaler-windows-x64` artifact, after processing a test clip with it.

## Layout

- `ui/`: the interface. `theme.slint` holds the design tokens, `controls.slint` the controls (switch, slider, pop-up
  button, text field, buttons, progress, segmented picker, toolbar button), `components.slint` cards, form sections and
  rows, `inspector.slint` the adjustments panel (`finishing.slint` the second restoration pass, `output.slint` the
  Output page), `workspace.slint` the input and details cards and the bottom bar, `app.slint` the window, its shortcuts
  and the Settings and About sheets. `fonts/` holds Inter with its OFL licence; `icons/app-icon.png` is the macOS app's
  icon.
- `src/settings.rs`: interface settings ↔ the backend's `Options`; the interface starts from the backend's factory
  settings, so the defaults are defined once.
- `src/presets.rs`: saved presets, in `presets.txt` in the per-user settings folder (`field=value` lines).
- `src/preview.rs`: the preview thread (one frame through the export's spatial filters) and the frame strip.
- `src/player.rs`: the player thread: frames decoded at window size, sound through the system's output device
  (`cpal`), timed by the sound that has played. `src/playback.rs` connects it to the window: play / pause (also the
  space bar), the scrubber, the frame strip, and Original | Result once an export finished. Paused on the original,
  the preview shows the adjustments; playing or scrubbing, the video's own frames.
- `src/progress.rs`: the backend's progress lines → progress, FPS, time and ETA.
- `src/screenshot.rs`: headless rendering for review and CI:
  `myupscaler --screenshot out.png [--size 1280x800] [--inspector] [--page 0-3] [--log] [--about | --settings]
  [--dark | --light] [--run [--after SECONDS]] [input]`. `cargo run --example sample_clip -- clip.mp4` writes a test
  video for it.

## Status

Working: import (file or batch folder), every Lanczos-path setting, the adjusted preview and frame strip, playback
with sound of the original or the finished export, saved presets, processing with live progress and cancel, opening or revealing the result, light and dark appearance. Not yet:
Real-ESRGAN (AI) upscaling (planned as a GPU model runner: CoreML on macOS, wgpu elsewhere), dropping files on the
window, and installers. HEVC, 10-bit and the hardware options are kept with the settings and presets, as in the macOS
app; the Rust engine writes 8-bit H.264 on the CPU and says so in the log.

## Licence

Slint is used under its royalty-free desktop licence, which requires its `AboutSlint` panel in the app's About sheet
(present). Inter is under the SIL Open Font License 1.1 (`ui/fonts/Inter-OFL.txt`).
