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
  
Contributing
---------------
See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and contribution guidelines.

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
