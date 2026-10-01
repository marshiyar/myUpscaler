# myUpscaler

A native macOS app for restoring and upscaling video, with a frame preview, saved presets, and two processing engines: FFmpeg/Lanczos and Core ML Real-ESRGAN.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" alt="myUpscaler workspace" width="600">

**Requirements:** Apple Silicon, macOS 15.2 or later. Intel Macs are unsupported. Development requires Xcode 26 or later and its Metal compiler component.

## Choose an engine

| Capability | FFmpeg / Lanczos | Core ML / Real-ESRGAN |
| --- | --- | --- |
| Scaling | Lanczos at the requested scale | One prediction per tile at the model's native scale, then resampling if needed |
| Input | Video and supported still images | Video |
| Output | MP4 video or PNG image | MP4 video, 8-bit |
| Audio | Audio is encoded with the video | Original audio tracks preserved through MP4 passthrough |
| Frame rate | Source timestamps, frame selection/duplication, or motion interpolation | Source timestamps; FPS controls do not apply |
| Restoration | Primary and optional second passes, EQ, grain | Primary denoise, sharpen and deband; model pipeline options |
| Encoding | CPU H.264/HEVC or VideoToolbox | AVFoundation H.264/HEVC |
| CPU encoding preset | Applies to CPU x264/x265 | Does not apply |

The preview approximates restoration with Core Image. It is useful for choosing settings but is not an exact FFmpeg or AI export preview. Unsupported controls are disabled or explained for the selected engine.

## Use the app

1. Use **Browse files** or drop a video or batch folder into the import area. Processing controls appear after import; **Configure before importing** keeps settings available earlier.
2. Choose **Lanczos** or an included **Core ML model**, then set the final output multiplier.
3. Adjust supported restoration settings using the approximate preview. Encoding details, additional restoration, processing details, and saved presets expand when needed.
4. Choose an output folder and start the export. Outputs use `<input>_[restored].mp4` or `.png`; an existing output with that name can be replaced.

The model multiplier and output multiplier are separate. For example, a native 4× model with 2× output predicts 4× tiles and resizes them once to 2×. Selecting an 8× model for 2× output still incurs its native inference cost; the app does not silently substitute a different model. Final video dimensions round down to even pixels. There is no custom width/height or aspect-ratio override.

Progress measures processed media timestamps when duration is known. Preparation and finalization are indeterminate. Completion requires engine success and a nonempty output file; cancellation keeps the job occupied until its resources stop. Remaining-time estimates depend on measured processing speed and can vary with the content.

**Encoding controls:** CPU presets trade encoding time against compression efficiency; they do not set bitrate or AI inference speed. VideoToolbox has a separate quality scale: the existing compression value maps to `100 − compression × 99/51`, not an equivalent CPU CRF. H.264 10-bit is rejected; 10-bit requires HEVC on the FFmpeg path.

## Build from source

```sh
git clone https://github.com/marshiyar/myUpscaler.git
cd myUpscaler
bash scripts/check-environment.sh
bash scripts/prepare-bundled-ffmpeg.sh
COREML_MODELS_DIR=/path/to/prebuilt/models bash scripts/prepare-bundled-models.sh
open myUpscaler.xcodeproj
```

Model preparation accepts compiled RGB Float32 NCHW `.mlmodelc` folders named `RealESRGAN_x2`, `RealESRGAN_x4` or `RealESRGAN_x8`. At least one compatible model is required. Assets are not stored in Git. Without an explicit model source, preparation downloads the pinned beta DMG; see [development setup](CONTRIBUTING.md) for that download and checksum-verified ZIP inputs. The released x2 asset is incompatible and is excluded by validation.

For a local Release build:

```sh
xcodebuild -project myUpscaler.xcodeproj -scheme myUpscaler \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= ENABLE_USER_SCRIPT_SANDBOXING=NO build
```

Release Swift code uses `-O`. The app bundles its own FFmpeg; PATH and external FFmpeg overrides are not used. On macOS 26+, the Core ML engine uses asynchronous AVFoundation providers/receivers, with a compatibility path for older supported macOS versions.

## Tests and project layout

```sh
bash scripts/check.sh
```

The source tests use synthetic media and do not download models. Packaged-app and actual model inference checks require prepared assets; see [CONTRIBUTING.md](CONTRIBUTING.md).

- `myUpscaler/App/` — app entry point.
- `myUpscaler/Views/` — native controls and media workspace.
- `myUpscaler/State/` — authoritative settings, normalization, presets and preview ownership.
- `myUpscaler/Processing/` — job lifecycle, Core ML worker, video I/O and scale geometry.
- `myUpscaler/Models/` and `Support/` — model contracts and shared parsing/protocols.
- `myUpscaler/Native/` — C FFmpeg pipeline and supervised subprocess lifecycle.
- `scripts/`, `tests/`, `docs/` — preparation, reproducible checks and design notes.

Maintained application source targets about 500 lines per file, with a 600-line ceiling checked by the test script. See [architecture](docs/architecture.md), [FPS audit](tests/FPS-AUDIT.md), and the [model optimization plan](docs/model-optimization.md).

## Current limitations

- Full Core ML throughput and temporal-quality benchmarks need compatible model assets and representative media. Synthetic kernel and video-I/O tests do not establish end-to-end AI speed.
- Numeric motion interpolation checks source sample timing. Verified constant-rate clips retain their duration through the final held frame; targets at or below source rate use frame selection. Variable-rate or unverified clips use conservative interpolation and may lose endpoint frames. Source/lock preserves original timestamps.
- Core ML preserves compatible MP4 audio without re-encoding it; unsupported audio fails visibly. Final muxing writes an additional compressed file. It omits FFmpeg-specific EQ, deblock, grain, second-pass restoration, FPS conversion and CPU codec options. Preview color EQ is not applied by that engine.
- CI app artifacts are ad hoc signed, not notarized. [Build artifacts](https://github.com/marshiyar/myUpscaler/actions/workflows/macos-build.yml) expire after 90 days; the workflow does not publish releases.

## License and credits

Application code is [Apache-2.0](LICENSE). The author converted the included model assets to Core ML; the underlying [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) weights retain their upstream BSD 3-Clause license, included as [`RealESRGAN-LICENSE.txt`](myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt).

The separately distributed [FFmpeg](https://ffmpeg.org/) executable is GPL-3.0-or-later. Its [license](myUpscaler/ThirdParty/FFmpeg-COPYING.txt) and [distribution notice](myUpscaler/ThirdParty/FFmpeg-NOTICE.txt) are included in app resources. FFmpeg is a trademark of Fabrice Bellard.
