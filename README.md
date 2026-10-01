myUpscaler
==========
macOS SwiftUI video upscaler. The app drives a custom C/FFmpeg pipeline with a Swift bridge. CoreML Real-ESRGAN is available when its model assets are included in the app.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" width="600">

Features
--------
- Apple Silicon–first; GPU/Neural Engine acceleration.
- End-to-end pipelines, interpolation, dual denoise/deblock/dering/sharpen/deband/grain stacks, color EQ.
  
Device Requirements
------------
Users:
- macOS 15.2+
- Apple Silicon recommended for CoreML
  
Troubleshooting
---------------
Before building on macOS,
run `bash scripts/prepare-bundled-ffmpeg.s`
This downloads and SHA-256-verifies the same Shaka FFmpeg 8.1.2 macOS binaries pinned by [mpvfx](https://github.com/marshiyar/mpvfx)

Contributing
---------------
Issues and pull requests are welcome.

Please ensure:
- Code builds with Xcode 26+
- Existing tests pass/Successful Build
- Xcode 26 or newer (to build with the project's current settings)
- New behavior includes tests where applicable
By contributing, you agree that your contributions will be licensed under the same license as this project.

License
-------
Licensed under the Apache License, Version 2.0.
See LICENSE for details.

Models were converted to CoreML by the author of this project.
Original license applies to the underlying weights.
See the Real-ESRGAN repository for full license terms.

The separately distributed FFmpeg executable is GPL-3.0-or-later. The GPL text
and a distribution notice are included as app resources.
FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.

Attributions ❤️
------------
Thank you to 
#### [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)
This project includes CoreML-converted versions of Real-ESRGAN models.
#### [FFmpeg](https://ffmpeg.org)
FFmpeg is licensed under the LGPL or GPL depending on the build configuration.
Users are responsible for installing FFmpeg and complying with its license terms.
