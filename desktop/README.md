# myUpscaler desktop (macOS, Windows, Linux)

The cross-platform version of myUpscaler: a [Slint](https://slint.dev) interface on the same Rust processing
backend (`../backend`) the macOS app uses, with the same settings. It is laid out like a professional media editor: a top
bar with three workspaces (Import, Edit, Export) and the document title, flat panels
tiled on a black window, and a status bar. Edit pairs the Program monitor (preview, blue timecode, original or
filtered view, scrubber) with the adjustments panel, whose effects are collapsible sections with an on/off switch and
one-line slider rows; Export holds the destination, the format summary and the Export button. Every control is drawn
from one set of design tokens (`ui/theme.slint`), dark with a light variant, and the fonts are embedded (Inter, and
Geist Mono for timecodes), so it looks the same on macOS, Windows and Linux.

```sh
bash ../scripts/prepare-media-engine.sh   # the media engine (macOS arm64, Linux x86_64, Windows x86_64)
cargo run --release                        # or: cargo run --release -- path/to/video.mp4
```

On Windows, run the first line from Git Bash (it comes with Git for Windows) and build with the MSVC toolchain (Visual
Studio Build Tools, "Desktop development with C++"). The build copies the engine's `mpvfx_ffi.dll` next to
`target\release\myupscaler.exe`; the two files together are the app. CI builds the same pair as the
`myupscaler-windows-x64` artifact, after processing a test clip with it.

## Layout

- `ui/`: the interface. `theme.slint` holds the design tokens, `controls.slint` the inputs (switch, slider, dropdown,
  text field), `components.slint` panels, tabs, sections, rows and buttons, `inspector.slint` the adjustments panel,
  `edit.slint` the Edit workspace, `workspaces.slint` Import and Export, `app.slint` the window. `fonts/` holds Inter and
  Geist Mono with their OFL licences.
- `src/settings.rs`: interface settings ↔ the backend's `Options`; the interface starts from the backend's factory
  settings, so the defaults are defined once.
- `src/preview.rs`: the preview thread (one frame, decoded or through the export's spatial filters).
- `src/progress.rs`: the backend's progress lines → progress, FPS, time and ETA.
- `src/screenshot.rs`: headless rendering for review and CI:
  `myupscaler --screenshot out.png [--size 1280x800] [--workspace 0-2] [--page 0-2] [--dark | --light] [--processed]
  [--run [--after SECONDS]] [input]`. `cargo run --example sample_clip -- clip.mp4` writes a test video for it.

## Status

Working: import (file or batch folder), every Lanczos-path setting, the frame preview with optional filters,
processing with live progress and cancel, light and dark appearance. Not yet: Real-ESRGAN (AI) upscaling (planned as a
GPU model runner: CoreML on macOS, wgpu elsewhere), the timeline editor, presets, and installers.

## Licence

Slint is used under its royalty-free desktop licence, which requires its `AboutSlint` panel in the app's About sheet
(present). Inter and Geist Mono are under the SIL Open Font License 1.1 (`ui/fonts/*-OFL.txt`).
