myUpscaler
==========
macOS SwiftUI video upscaler. Processing runs in a Rust backend written for this app (`backend/`): every
restoration filter, the Lanczos scaler and motion-compensated frame interpolation are implemented there, and
decoding, H.264 encoding and MP4 muxing go through the MpVFX media engine, also written in Rust. There is no FFmpeg
and no helper process. The app also bundles CoreML Real-ESRGAN x4 and x8 models.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" width="600">

Features
--------
- Apple Silicon–first; GPU/Neural Engine acceleration.
- End-to-end pipelines, interpolation, dual denoise/deblock/dering/sharpen/deband/grain stacks, color EQ.
- Rust backend: BM3D, non-local means, hqdn3d and adaptive temporal denoising; deblocking; duplicate-frame
  decimation; motion-compensated, blended or repeated frame interpolation; Lanczos-3 scaling; CAS and unsharp
  sharpening; deband and gradfun; grain. Filters run multi-threaded in float precision with a dithered 8-bit output.
- Output: H.264 MP4 with lossless FLAC audio (videos), PNG with transparency kept (stills).
  
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

The MpVFX media engine (`libmpvfx_ffi.dylib`, from the
[mpvfx-media-binaries](https://github.com/marshiyar/mpvfx-media-binaries) releases) is proprietary and is
included with the app by permission of its author; its licence and third-party notices are included as app
resources (`MpVFX-Media-LICENSE.txt`, `MpVFX-Media-NOTICE.txt`). It is not covered by this repository's licence.

Attributions ❤️
------------
Thank you to 
#### [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)
This project includes CoreML-converted versions of Real-ESRGAN models.
#### [MpVFX media engine](https://github.com/marshiyar/mpvfx-media-binaries)
Hand-written Rust media engine used for decoding, encoding and muxing.
