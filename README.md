myUpscaler
==========
macOS SwiftUI video upscaler. The app drives a custom C/FFmpeg pipeline with a Swift bridge. CoreML Real-ESRGAN is available when its model assets are included in the app.

License
-------
Licensed under the Apache License, Version 2.0.
See LICENSE for details.

Features
--------
- Apple Silicon–first; GPU/Neural Engine acceleration.
- End-to-end pipelines, interpolation, dual denoise/deblock/dering/sharpen/deband/grain stacks, color EQ.
  
<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" width="600">

Requirements
------------
- macOS 15.2+
- Xcode 26 or newer (to build with the project's current settings)
- Apple Silicon recommended for CoreML

Bundled FFmpeg
--------------
The app executes only `Contents/MacOS/ThirdParty/FFmpeg/ffmpeg` inside its own
bundle. System installations, `PATH`, and `UP60P_FFMPEG` overrides are ignored.
Missing, non-executable, or externally linked binaries stop processing; reinstall
the app instead of installing a separate FFmpeg.

Before building on macOS, run `bash scripts/prepare-bundled-ffmpeg.sh`. This
downloads and SHA-256-verifies the same Shaka FFmpeg 8.1.2 macOS binaries pinned
by [mpvfx](https://github.com/marshiyar/mpvfx), then combines the Apple Silicon
and Intel executables into a universal binary. Xcode copies and signs it in the
app bundle. These binaries require macOS 15.0+; this project's app target
currently requires macOS 15.2.

The shipped FFmpeg engine offers Lanczos upscaling. Unsupported legacy SR/DNN,
zscale, and hardware-scaler choices and their controls are removed. CoreML is
shown only when model assets are bundled, and its model picker lists only
included models. Older presets selecting an unavailable mode or missing model
show an explanation and cannot start until a supported choice is selected.
The native FFmpeg engine also rejects unsupported scaler values directly.
Hardware decode/encoding options are separate from the removed hardware scaler.

The separately distributed FFmpeg executable is GPL-3.0-or-later. The GPL text
and a distribution notice are included as app resources. Its provenance,
checksums, and corresponding-source requirements are documented in
[docs/FFMPEG.md](docs/FFMPEG.md). Include the upstream license and corresponding
source with public binary releases.

Run `python3 -m unittest discover -s tests -p 'test_bundled_ffmpeg*.py'` on Linux
or macOS to test bundle resolution, native engine execution, missing binaries,
and rejection of external paths and symlinks.
The macOS CI also runs the Swift upscaling-availability checks in
`tests/upscaling-mode-support/main.swift` before building the app.

Troubleshooting
---------------

# Contributing
---------------
Issues and pull requests are welcome.

Please ensure:
- Code builds with Xcode 26+
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
