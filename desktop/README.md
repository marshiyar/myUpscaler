# myUpscaler desktop (macOS, Windows, Linux)

The cross-platform version of myUpscaler: a [Slint](https://slint.dev) interface on the same Rust processing
backend (`../backend`) the macOS app uses. It follows the macOS app's layout and design (toolbar, preview with the log
under it, the Upscale / Restore / Processor / Output adjustments panel, progress and Run / Cancel at the bottom), with
the Cupertino style on every platform so it looks the same everywhere, in light and dark.

```sh
bash ../scripts/prepare-media-engine.sh   # the media engine (macOS arm64, Linux x86_64)
cargo run --release                        # or: cargo run --release -- path/to/video.mp4
```

## Layout

- `ui/`: the interface. `theme.slint` holds the design tokens (DesignSystem.swift's spacing, type, radii and colours),
  `components.slint` the building blocks, `inspector.slint` the four adjustment pages, `app.slint` the window.
- `src/settings.rs`: interface settings ↔ the backend's `Options`; the interface starts from the backend's factory
  settings, so the defaults are defined once.
- `src/preview.rs`: the preview thread (one frame, decoded or through the export's spatial filters).
- `src/progress.rs`: the backend's progress lines → progress, FPS, time and ETA.
- `src/screenshot.rs`: headless rendering for review and CI:
  `myupscaler --screenshot out.png [--size 1180x780] [--page 0-3] [--dark] [--processed] [--run] [input]`.

## Status

Working: import (file or batch folder), every Lanczos-path setting, the frame preview with optional filters,
processing with live progress and cancel, light and dark appearance. Not yet: Real-ESRGAN (AI) upscaling (planned as a
GPU model runner: CoreML on macOS, wgpu elsewhere), the timeline editor, presets, and installers. The media engine has
no Windows package yet, so the Windows build runs the interface but cannot process files.

## Licence

Slint is used under its royalty-free desktop licence, which requires its `AboutSlint` panel in the app's About sheet
(present).
