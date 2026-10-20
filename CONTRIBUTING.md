# Contributing

Issues and pull requests are welcome.

Please ensure:

- Code builds with Xcode 26+
- Existing tests pass
- New behavior includes tests where applicable

By contributing, you agree that your contributions will be licensed under the same license as this project.

## Building locally

Building needs Rust (install from https://rustup.rs; Xcode builds the backend with `cargo` in its first build
phase). Before building on macOS, run `bash scripts/prepare-media-engine.sh`. It downloads the pinned MpVFX media
engine package from the mpvfx-media-binaries releases, verifies its SHA-256 and unpacks it into the ignored
`third_party/mpvfx-media/` directory; Xcode links it and embeds it in `Contents/Frameworks`.

The processing backend lives in `backend/` (see its README). It builds and tests on its own:

```sh
bash scripts/prepare-media-engine.sh   # also works on Linux x86_64, for the tests
cd backend
cargo test --release                   # unit tests, ABI check against up60p.h, end-to-end renders
cargo clippy --all-targets -- -D warnings
cargo run --release --example bench    # timings per filter on a synthetic 720p clip
cargo run --release -- --set scale_factor=2 input.mp4   # the backend from the command line
```

Models are prepared outside this repository. Supply a directory of prebuilt
`.mlmodelc` folders with
`COREML_MODELS_DIR=/path/to/models bash scripts/prepare-bundled-models.sh`.
Use the registered resource names (`RealESRGAN_x2`, `RealESRGAN_x4`,
`RealESRGAN_x8`); their native scales are defined in `CoreMLModelRegistry.swift`.
At least one compatible model is required. Updated weights and square tile
sizes do not require an asset manifest or hash changes in the app repository.
Preparation loads each supplied model through CoreML and runs a real prediction,
checking Float32 RGB input/output, native scale, output layout and finite pixels.
It does not train, create or convert models.

For a downloaded model ZIP, set `COREML_MODEL_ARCHIVE_URL` and
`COREML_MODEL_ARCHIVE_SHA256` instead. The ZIP must contain the `.mlmodelc`
folders at its root. These inputs are also available on manual Actions runs.
The checksum verifies the supplied download, without pinning individual weights
or compiled metadata files. Explicit sources replace any existing cache after
validation. Xcode's **Embed CoreML models** phase loads and checks the prepared
assets, copies them into Resources, and removes models dropped from the set.

Without an explicit source, `bash scripts/prepare-bundled-models.sh` reuses a
validated cache or extracts the prebuilt x4/x8 models from the checksum-verified
[v0.0.2-beta DMG](https://github.com/marshiyar/myUpscaler/releases/tag/v0.0.2-beta).
That particular release's x2 model expects 12 channels and is excluded; a future
RGB x2 supplied explicitly can pass validation. Assets are stored in the ignored
`third_party/CoreML/` directory. Builds report the preparation command for missing
or incompatible assets. Native model scale and final output scale remain separate
settings. CI tests the supplied set and predicts with the packaged models.

## Actions app builds

The **macOS build, test and bundle** Actions workflow runs for pull requests,
pushes to `main`, and manual runs. It builds a Release app and uploads a unique
`myUpscaler-macos-arm64-<run>-<attempt>` artifact containing a DMG, an inner ZIP
that preserves app permissions, checksums, and build information. Artifacts are
retained for 90 days and are never overwritten or deleted by the workflow.
GitHub expires them after that period. These builds are ad hoc signed and are
not notarized. The workflow has read-only repository permissions and does not
publish to GitHub Releases.
