# myUpscaler

A native macOS app for restoring and upscaling video with FFmpeg/Lanczos or Core ML Real-ESRGAN. Includes frame previews, saved presets, and batch export.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" alt="myUpscaler workspace" width="600">

**Requires:** Apple Silicon and macOS 15.2 or later. Building from source uses Xcode 27 with its Metal compiler component installed.

## Use

1. **Import** a video or folder, or drop a video into the workspace.
2. Open **Adjustments** and choose **Lanczos** or an included **Real-ESRGAN** model in the Scaler picker. Set the output scale.
3. Use **Restore** and **Processor** to adjust filters, then **Output** to choose encoding, presets, and an output folder.
4. Start the export. Use **Cancel** to stop processing.

Lanczos supports video and still images; Core ML supports video. Available controls depend on the selected engine. The frame preview approximates restoration and may differ from the export.

Shortcuts: **⌘O** imports, **⌘R** exports, and **⌘.** cancels. Customize bindings in **Settings → Shortcuts**.

## Build and run

```sh
git clone https://github.com/marshiyar/myUpscaler.git
cd myUpscaler
bash scripts/check-environment.sh
bash scripts/prepare-bundled-ffmpeg.sh
bash scripts/prepare-bundled-models.sh
open myUpscaler.xcodeproj
```

The preparation scripts download and verify the required assets. In Xcode, select the **myUpscaler** scheme and run it on **My Mac**. The app includes its own FFmpeg.

For development checks and additional setup options, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License and credits

Application code: [Apache-2.0](LICENSE).

Core ML model assets are provided by Marshiyar. [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) weights retain their upstream [BSD 3-Clause license](myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt).

The separately distributed [FFmpeg](https://ffmpeg.org/) executable is GPL-3.0-or-later; see its [license](myUpscaler/ThirdParty/FFmpeg-COPYING.txt) and [distribution notice](myUpscaler/ThirdParty/FFmpeg-NOTICE.txt). FFmpeg is a trademark of Fabrice Bellard.
