myUpscaler
==========
macOS SwiftUI app for AI-powered video upscaling. The app drives a custom C/FFmpeg pipeline with a Swift bridge and can switch to an on-device CoreML Real-ESRGAN.

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
- macOS 14.0+
- Xcode 15.7.2 or newer (to build)
- Apple Silicon recommended for CoreML

Troubleshooting
---------------

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
