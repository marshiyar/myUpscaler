myUpscaler
==========
macOS SwiftUI video upscaler. The app drives a custom C/FFmpeg pipeline with a Swift bridge. The app bundles CoreML Real-ESRGAN x4 and x8 models.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" width="600">

Features
--------
- Apple Silicon–first; GPU/Neural Engine acceleration.
- End-to-end pipelines, interpolation, dual denoise/deblock/dering/sharpen/deband/grain stacks, color EQ.
  
Device Requirements
------------
Users:
- macOS 15.2+
- Apple Silicon required; Intel Macs are unsupported
  
Troubleshooting
---------------
Before building on macOS,
run `bash scripts/prepare-bundled-ffmpeg.sh`
This downloads and SHA-256-verifies the same Shaka FFmpeg 8.1.2 macOS binaries pinned by [mpvfx](https://github.com/marshiyar/mpvfx).

Also run `bash scripts/prepare-bundled-models.sh`. It verifies the pinned
[v0.0.2-beta DMG](https://github.com/marshiyar/myUpscaler/releases/tag/v0.0.2-beta)
and extracts its compiled x4 and x8 models into the ignored `third_party/CoreML/`
directory. Xcode's **Embed CoreML models** phase verifies and copies them into
the app's Resources before signing. Builds fail with a setup command if the
assets are missing or corrupt; no manual target-membership changes are needed.

The released x2 model expects 12 input channels, which the engine's RGB tensor
conversion does not support, so it is excluded. Native model scale and final
output scale are separate settings. CI verifies the packaged models and runs
a real prediction with each, alongside the XCTest unit tests.

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
The upstream BSD 3-Clause license is included in the app resources as
`RealESRGAN-LICENSE.txt`.

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
FFmpeg is bundled with the app; system installations and PATH overrides are not used.
