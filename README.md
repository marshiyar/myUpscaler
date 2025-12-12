myUpscaler
==========
macOS SwiftUI app for AI-powered video upscaling. The app drives a custom C/FFmpeg pipeline (`up60p_restore_beast_main.c`) with a Swift bridge (`Up60PEngine`) and can switch to an on-device CoreML Real-ESRGAN.

License
-------
Licensed under the Apache License, Version 2.0.
See LICENSE for details.

Features
--------
- Apple Silicon–first (Intel supported); GPU/Neural Engine acceleration when using Metal Shaders.
- End-to-end FFmpeg and pipeline, interpolation, dual denoise/deblock/dering/sharpen/deband/grain stacks, LUT support, color EQ.

Requirements
------------
- macOS 14.0+
- Xcode 15.7.2 or newer (to build)
- Apple Silicon recommended for CoreML

Project Layout
--------------
- `myUpscaler/` – app sources (SwiftUI UI in `ContentView`, state in `EditorState`, settings in `UpscaleSettings`, runner/orchestration in `UpscaleRunner`, FFmpeg parsing, keyboard shortcuts, etc.).
- `myUpscaler/upscaler/` – upscaling engines: `Up60PEngine.swift` (C bridge), `CoreMLEngine.swift` + `CoreMLEngine+Shaders.swift`, Metal shaders, Real-ESRGAN models, filter helpers, and docs (`CoreML_README.md`, `filters/README.md`).
- `myUpscaler/lib/` – Not included in this repository. Users must provide their own FFmpeg dylibs and binaries.
- `myUpscaler/Debug/` – test dashboard, fuzzer, and mock engine.
- `myUpscalerTests/`, `myUpscalerUITests/` – unit, integration, performance, stability, and test Targets

Build & Run
-----------
1) Open `myUpscaler.xcodeproj`, select the `myUpscaler` scheme, and run on `My Mac (macOS)`

Runtime Notes
-------------
- FFmpeg path: the bridge uses the bundled libs plus an executable. Set `UP60P_FFMPEG=/path/to/ffmpeg` if auto-detection fails (Debug defaults to `/opt/homebrew/bin/ffmpeg`).
- CoreML models: Real-ESRGAN models are bundled (`upscaler/models/`) and compiled on first use. See `upscaler/CoreML_README.md` for details.
- Filters: `f3kdb` is emulated via `deband` with parameter mapping; see `upscaler/filters/README.md`.
- Sandbox: the app requests read/write access to user-selected files, Downloads, and Movies as declared in `myUpscaler.entitlements`.

Troubleshooting
---------------
- Missing FFmpeg: install via `brew install ffmpeg` or point `UP60P_FFMPEG` to your binary.
- Model load/compile issues: confirm models are present and valid; re-open the app after the first compile.
- Build errors after Xcode upgrade: clean build folder, then re-run `xcodebuild -scheme myUpscaler -configuration Debug build`.
- Make sure you have the dylibs installed on your end

# Contributing
---------------
Issues and pull requests are welcome.

Please ensure:
- Code builds with Xcode 15+
- Existing tests pass/Successful Build
- New behavior includes tests where applicable

By contributing, you agree that your contributions will be licensed
under the same license as this project.

Attributions
------------
### Models

This project includes CoreML-converted versions of Real-ESRGAN models.

Original project:
https://github.com/xinntao/Real-ESRGAN

Models were converted to CoreML by the author of this project.
Original license applies to the underlying weights.
See the Real-ESRGAN repository for full license terms.

### FFmpeg

This project is designed to work with FFmpeg.

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

FFmpeg is licensed under the LGPL or GPL depending on the build configuration.
Users are responsible for installing FFmpeg and complying with its license terms.

Official website: https://ffmpeg.org
