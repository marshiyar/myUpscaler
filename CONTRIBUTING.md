# Contributing

Issues and pull requests are welcome.

Before opening a pull request:

- the code builds with Xcode 27 or later;
- existing tests pass;
- new behavior has tests where they apply.

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
cargo test --release                   # unit tests, C API and header checks, end-to-end renders
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
validation. Xcode's Embed CoreML models phase loads and checks the prepared
assets, copies them into Resources, and removes models dropped from the set.

Without an explicit source, `bash scripts/prepare-bundled-models.sh` reuses a
validated cache or extracts the prebuilt x4/x8 models from the checksum-verified
[v0.0.2-beta DMG](https://github.com/marshiyar/myUpscaler/releases/tag/v0.0.2-beta).
That particular release's x2 model expects 12 channels and is excluded; a future
RGB x2 supplied explicitly can pass validation. Assets are stored in the ignored
`third_party/CoreML/` directory. Builds report the preparation command for missing
or incompatible assets. Native model scale and final output scale remain separate
settings. CI tests the supplied set and predicts with the packaged models.

## Actions workflows

Workflows are in `.github/workflows/`. Each runs on pull requests and pushes to `main`, and by hand. All except
`build.yml` and `release.yml` are limited to the paths they cover; `build.yml` skips changes that only touch
Markdown files. Jobs labelled `ubuntu-24.04` and `windows-2025` run on hosted runners; jobs labelled `xcode-27` run on
macOS with Xcode 27 and a Metal device.

- `rust.yml` (Ubuntu): jobs `format`, `lints` (clippy, warnings denied), `unit-tests`, `engine-tests` (C API, engine
  wrapper and end-to-end renders through the media engine; skipped tests fail the job) and `without-engine` (the crate
  builds and its filter tests pass without the engine library).
- `swift-tests.yml`: `source-lint` (Ubuntu: shell syntax, whitespace, the source size ceiling), then `swift` (`xcode-27`:
  every logic test and the XCTest scheme).
- `regression.yml` (`xcode-27`): the finishing chain through the Rust dry run, native media tests on generated clips and
  the Metal kernels.
- `desktop.yml`: the Slint app. `linux` (format, clippy, tests, screenshots), `windows` (tests, then a build that
  processes a test clip) and `macos` (`xcode-27`: tests, then a build that renders a finished run).
- `build.yml` (`xcode-27`): `release-app` (Release app build; verifies the engine, signature, models and inference;
  packages the app) and `model-sets` (model-set preparation). The jobs report the Metal device and fail if there is none.
- `release.yml`: for `v*` tags (or by hand for an existing tag): `smoke` builds and smoke-tests the desktop app on
  Linux (`ubuntu-24.04`), Windows (`windows-2025`) and macOS (`xcode-27`), then `publish` (Ubuntu) uploads the packaged apps
  and screenshots to the tag's release.

The `xcode-27` jobs need Xcode 27 in `/Applications` and Rust through rustup (the pinned release in
`rust-toolchain.toml` installs itself). Inside a job, `scripts/run-parallel.sh` runs the scripts at the same time, one
per CPU core.

The media engine is a precompiled, pinned binary: it is downloaded and verified
once, then restored from the cache. The compiled Rust backend (`libup60p.a` and
its header) is stored the same way, keyed by the backend's sources, and is only
recompiled when those change; `scripts/build-rust-backend.sh` (also Xcode's first
build phase) skips Cargo entirely when nothing it depends on changed. CoreML
models are cached too.

The Release job uploads a unique `myUpscaler-macos-arm64-<run>-<attempt>`
artifact containing a DMG, an inner ZIP that preserves app permissions,
checksums, and build information. Artifacts are retained for 90 days and are
never overwritten or deleted by the workflow. These builds are ad hoc signed and
are not notarized.

The Release workflow runs for a pushed `v*` tag (or by hand for an existing
tag). On each platform it builds the desktop app and runs its smoke test
(`desktop/scripts/smoke-test.sh`): the real window rendered headless on the
import view, on the adjustments panel with a generated clip, and after that clip
is exported end to end, with the exported file checked. The packaged apps
(`myupscaler-<tag>-<platform>-<arch>`, with the media engine library beside the
program) and the screenshots go on the tag's GitHub release, whose description
gets a "Smoke tests" section showing each platform's result and screenshots
(`scripts/release-notes.py`). An existing release keeps its own text and
assets: only that section, between its markers, is added or replaced. A platform
whose smoke test failed is shown as failed rather than left out. Only this
job has write access to the repository (to publish the release); every other
workflow is read-only.

## Fast checks without downloaded assets

Run `bash scripts/check.sh` on an Apple Silicon Mac. It checks the 600-line
maintained-source ceiling, runs the Rust backend's format, lint and test suite,
the dry-run filter-chain and native media/FPS/preview/scale/progress regressions
(their test videos are generated with AVFoundation, so no external tool is
needed), and the independent `myUpscalerUnitTests` XCTest scheme. The test scheme
does not build the app or require Core ML model files. The backend tests and the
Swift tests that link the backend need the media engine from
`scripts/prepare-media-engine.sh`; packaged-app verification
(`tests/verify-packaged-engine.sh`) remains a separate requirement.

On Windows, Linux or macOS without Xcode, `bash scripts/check-portable.sh` runs the source budget and the backend and desktop format, clippy and test checks (`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test`). It needs the media engine from `scripts/prepare-media-engine.sh` for the engine-backed tests.

`bash scripts/check-environment.sh` reports Xcode/SDK, the Metal compiler
component and Rust. It does not install tools or download assets. Xcode may be present
while its separately supplied Metal compiler component is missing.

For focused checks:

```sh
bash tests/test-editor-state.sh
bash tests/test-processing-lifecycle.sh
bash tests/apple-api/run.sh
xcodebuild -project myUpscaler.xcodeproj -scheme myUpscalerUnitTests \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

The native video-I/O test exercises both the modern and compatibility paths on
macOS 26+. This is not a macOS 15.2 runtime test or a model-throughput benchmark.
The processing test includes a blend microbenchmark; avoid treating its result
as end-to-end AI speed. Keep quality, frame counts, timestamps and audio checks
alongside performance measurements.

## Source changes

Follow [architecture and ownership](docs/architecture.md). Keep observable UI
state on its owning actor, background pixel work out of the UI executor, and
superseded preview requests unable to publish. Split maintained source by
responsibility around 500 lines, with a 600-line ceiling. Add new settings files
to the independent XCTest source list as needed; the application target uses
Xcode synchronized folders.

Legacy preset fields, dynamically loaded Metal kernels and valid OS fallback
paths must not be removed merely because a direct reference search is empty.
Keep license notices and avoid committing prepared models, binaries or build
outputs. Stage logic/performance and structural/UI changes separately when
possible.
