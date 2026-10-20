# myUpscaler

A native macOS app for restoring and upscaling video with its Rust engine (Lanczos and a full restoration filter stack) or Core ML Real-ESRGAN. Includes frame previews, saved presets, and batch export.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" alt="myUpscaler workspace" width="600">

**Requires:** Apple Silicon and macOS 15.2 or later. Building from source uses Xcode 27 with its Metal compiler component installed, and Rust (the toolchain is pinned in `rust-toolchain.toml`).

## Use

1. **Import** a video or folder, or drop a video into the workspace.
2. Open **Adjustments** and choose **Lanczos** or an included **Real-ESRGAN** model in the Scaler picker. Set the output scale.
3. Use **Restore** and **Processor** to adjust filters, then **Output** to choose encoding, presets, and an output folder.
4. Start the export. Use **Cancel** to stop processing.

Lanczos supports video and still images; Core ML supports video. Available controls depend on the selected engine. The frame preview approximates restoration and may differ from the export.

Shortcuts: **⌘O** imports, **⌘R** exports, and **⌘.** cancels. Customize bindings in **Settings → Shortcuts**.

## Engine

Lanczos processing runs in a Rust backend written for this app (`backend/`): BM3D, non-local means, hqdn3d and adaptive temporal denoising; deblocking and deringing; duplicate-frame decimation; motion-compensated, blended or repeated frame interpolation; Lanczos-3 scaling; CAS and unsharp sharpening; deband, f3kdb-style and gradfun debanding; color EQ and grain. Filters run multi-threaded in float precision with a dithered 8-bit output. Decoding, H.264 encoding and MP4 muxing go through the MpVFX media engine, also written in Rust. Videos are written as H.264 MP4 with lossless FLAC audio; stills as PNG with transparency kept. There is no FFmpeg and no helper process.

## Build and run

```sh
git clone https://github.com/marshiyar/myUpscaler.git
cd myUpscaler
bash scripts/check-environment.sh
bash scripts/prepare-media-engine.sh
bash scripts/prepare-bundled-models.sh
open myUpscaler.xcodeproj
```

The preparation scripts download and verify the required assets. In Xcode, select the **myUpscaler** scheme and run it on **My Mac**; the build compiles the Rust backend first.

For development checks and additional setup options, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License and credits

Application code: [Apache-2.0](LICENSE).

Core ML model assets are provided by Marshiyar. [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) weights retain their upstream [BSD 3-Clause license](myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt).

The MpVFX media engine (`libmpvfx_ffi.dylib`, from the [mpvfx-media-binaries](https://github.com/marshiyar/mpvfx-media-binaries) releases) is proprietary and is included with the app by permission of its author; its [licence](myUpscaler/ThirdParty/MpVFX-Media-LICENSE.txt) and [third-party notices](myUpscaler/ThirdParty/MpVFX-Media-NOTICE.txt) are included as app resources. It is not covered by this repository's licence.
