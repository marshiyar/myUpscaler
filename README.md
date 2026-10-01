# myUpscaler

A native macOS app for restoring and upscaling video, with a frame preview, saved presets, and two processing engines: FFmpeg/Lanczos and Core ML Real-ESRGAN.

<img src="https://github.com/user-attachments/assets/0c40540b-d83c-4f9b-bad5-07c0baa4b978" alt="myUpscaler workspace" width="600">

**Requirements:** Apple Silicon, macOS 15.2 or later. Intel Macs are unsupported. Development uses Xcode 27 and its Metal compiler component.

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

1. Use **Import** to choose a video or batch folder, or drop an individual video into the import area. Open **Adjustments** in the toolbar to configure the docked side panel before or after importing; it starts collapsed and never covers the video.
2. Choose **Lanczos** or an included named model such as **Real-ESRGAN x4** or **Real-ESRGAN x8** in the single **Scaler** picker, then set the final output multiplier.
3. Adjust supported restoration settings using the approximate preview. The side panel groups **Upscale**, **Restore**, and **Output** controls. Encoding details, additional restoration, processing details, and saved presets expand when needed.
4. Choose an output folder and start the export. Individual outputs use `<input>_[restored].mp4` or `.png`; an existing individual output with that name can be replaced. Folder jobs preserve existing files as described below.

The model multiplier and output multiplier are separate. For example, a native 4× model with 2× output predicts 4× tiles and resizes them once to 2×. Selecting an 8× model for 2× output still incurs its native inference cost; the app does not silently substitute a different model. Final video dimensions round down to even pixels. There is no custom width/height or aspect-ratio override.

Single-file progress measures processed media timestamps when duration is known. Folder progress counts verified completed files. Preparation and finalization are indeterminate. Completion requires engine success and a nonempty output file; cancellation keeps the job occupied until its resources stop. Remaining-time estimates depend on measured processing speed and can vary with the content.

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

Debug and Release use Complete Swift concurrency checking and treat Swift/C warnings as errors. Swift language mode remains 5. The Metal compiler and linker driver both use `-fcikernel`; the individual kernel sources produce one bundled `default.metallib`.

## Tests and project layout

```sh
bash scripts/check.sh
```

The source tests use synthetic media and do not download models. Packaged-app and actual model inference checks require prepared assets; see [CONTRIBUTING.md](CONTRIBUTING.md).

Additional checks run independently:

```sh
bash tests/test-native-sanitizers.sh
python3 tests/metal-kernels/run.py
bash tests/test-model-ownership.sh build/Build/Products/Release/myUpscaler.app/Contents/Resources
bash tests/test-batch-real.sh build/Build/Products/Release/myUpscaler.app
```

The model check uses existing assets to test repeated inference, UI responsiveness, a small video export and cancellation. The real batch check uses the app’s bundled FFmpeg and existing models to decode and verify tiny nested folder exports through both engines. The native sanitizer script runs Address/Undefined Behavior Sanitizer checks separately from Thread Sanitizer.

- `myUpscaler/App/` — app entry point.
- `myUpscaler/Views/` — native controls and media workspace.
- `myUpscaler/State/` — authoritative settings, normalization, presets and preview ownership.
- `myUpscaler/Processing/` — job lifecycle, Core ML worker, video I/O and scale geometry.
- `myUpscaler/Models/` and `Support/` — model contracts and shared parsing/protocols.
- `myUpscaler/Native/` — C FFmpeg pipeline and supervised subprocess lifecycle.
- `scripts/`, `tests/`, `docs/` — preparation, reproducible checks and design notes.

Maintained application source targets about 500 lines per file, with a 600-line ceiling checked by the test script. See [architecture](docs/architecture.md), [FPS audit](tests/FPS-AUDIT.md), and the [model optimization plan](docs/model-optimization.md).

## Finishing filters (FFmpeg)

Additional Filters uses **Off** to bypass Deblock. Deband strength and grain amount at zero bypass their effects while their editors remain visible. Deblock has four optional fields, alpha/beta/gamma/delta, each from 0 to 1; blank uses FFmpeg defaults (0.098/0.05/0.05/0.05). Stored disabled filters retain their saved values.

The **Interpolation** picker offers Off, MCI and Blend. New/reset settings use Off; saved enabled choices are preserved. Target FPS can still select or duplicate frames with interpolation Off.

The optional finishing filters run after scaling and the primary sharpen/deband filters. Each switch enables its filter independently of the primary set. Deringing uses one switch and an `hqdn3d` smoothing filter; it does not detect ringing artifacts. Finishing grain replaces primary grain rather than adding a second noise filter. These controls do not apply to Core ML exports, and the Core Image preview is an approximation of FFmpeg processing.

When a filter runs in both sets, fixed multipliers reduce finishing strength: CAS/CAS 0.6, mixed CAS/unsharp 0.5, unsharp/unsharp 0.35, denoise 0.55, and deband 0.6. Unsharp matrix size also shrinks, retaining an odd size. This is a parameter heuristic, not image analysis or a guarantee against artifacts. `auto` denoise keeps FFmpeg's automatic setting without numeric attenuation. Reducing strength still runs the filter and does not remove its processing cost.

## Current limitations

- Folder export plans `.mp4`, `.mkv`, `.mov` and supported images by case-insensitive extension, skips hidden files and symlinks, and preserves subfolders inside `<folder>_[restored]` under the chosen output location. Core ML folder jobs accept videos only; any supported image rejects the plan before processing. Colliding names or existing destinations reject the plan; choose another output location. Files run sequentially, stop on the first failure or cancellation, and retain verified completed outputs. Limits: 10,000 media files and 100,000 directory entries per job. Unknown extensions are skipped. The completion action opens the output folder.

- Full Core ML throughput and temporal-quality benchmarks need compatible model assets and representative media. Synthetic kernel and video-I/O tests do not establish end-to-end AI speed.
- Numeric motion interpolation checks source sample timing. Verified constant-rate clips retain their duration through the final held frame; targets at or below source rate use frame selection. Variable-rate or unverified clips use conservative interpolation and may lose endpoint frames. Source/lock preserves original timestamps.
- Core ML preserves compatible MP4 audio without re-encoding it; unsupported audio fails visibly. Final muxing writes an additional compressed file. It omits FFmpeg-specific EQ, deblock, grain, second-pass restoration, FPS conversion and CPU codec options. Preview color EQ is not applied by that engine.
- CI app artifacts are ad hoc signed, not notarized. [Build artifacts](https://github.com/marshiyar/myUpscaler/actions/workflows/macos-build.yml) expire after 90 days; the workflow does not publish releases.

## License and credits

Application code is [Apache-2.0](LICENSE). The author converted the included model assets to Core ML; the underlying [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) weights retain their upstream BSD 3-Clause license, included as [`RealESRGAN-LICENSE.txt`](myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt).

The separately distributed [FFmpeg](https://ffmpeg.org/) executable is GPL-3.0-or-later. Its [license](myUpscaler/ThirdParty/FFmpeg-COPYING.txt) and [distribution notice](myUpscaler/ThirdParty/FFmpeg-NOTICE.txt) are included in app resources. FFmpeg is a trademark of Fabrice Bellard.

### Keyboard controls

The **Video** menu and workspace buttons share the same command dispatcher. Defaults: ⌘O imports, ⌘R exports, ⌘. cancels, ⌘⇧O chooses the output folder, ⌘, opens Settings, ⌘⇧I opens About, and ⌘⌥I toggles the docked adjustments panel. Change bindings in Settings; use Edit to record a combination, then Save or Cancel. A conflicting recording opens one resolver showing both commands and bindings: Swap exchanges them, Clear both leaves both explicitly unassigned, and Cancel changes nothing. Unassigned commands remain available in the Video menu. Recording one binding does not activate other commands.
