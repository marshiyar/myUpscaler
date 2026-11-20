# AI upscaling in the desktop app

Design for Real-ESRGAN upscaling in `desktop/` on Windows, Linux and macOS. The macOS app keeps its Core ML path.

## Constraints

- `backend/` has no third-party crates; model code goes in a new crate (`ai/`) that depends on it.
- No FFmpeg and no C code, so no ONNX Runtime or other native runtime.
- The CPU path stays the reference: a GPU result must match it within a stated tolerance, proved by a test.
- Each package that ships a model ships its licence notice.

## Model format

The upstream Real-ESRGAN weights (BSD 3-Clause) are a stack of 3x3 convolutions, leaky ReLU, residual adds and
nearest-neighbour upsampling (RRDBNet). We store them in one flat file, `*.mupm`:

- a header: magic, version, model id, scale (2, 4 or 8), tile size, channel counts, block count, tensor count;
- per tensor: name, shape, dtype (f32 or f16), byte offset;
- the tensor data, little-endian, aligned to 16 bytes;
- a SHA-256 of the data, checked on load.

A converter (`ai/tools/convert`, run offline, not at install time) reads the upstream `.pth`, writes the `.mupm`, and
prints the checksum. The format is one we own and parse in plain Rust, so the crate needs no parser dependency.

## Runner

Crate `ai/` (`up60p-ai`), depending on `up60p` and, for the GPU part, `up60p-gpu`'s device context.

1. `Model` loads and validates a `.mupm`.
2. `cpu::run` is the reference: tiled inference (tile plus 16-pixel overlap, feathered blend) on f32 tensors. Slow, used by tests and as the fallback.
3. `gpu::run` runs the same layers as wgpu compute shaders (Vulkan, DX12, Metal), f16 weights with f32 accumulation. Test: PSNR against `cpu::run` on a fixed 64x64 image, tolerance stated in the test (target: max abs error under 2/255).
4. Both implement a small `Upscaler` trait: `fn upscale(&self, rgb: &Rgb, progress: &dyn Fn(f32)) -> Result<Rgb, Error>`.

Hook into the engine: `backend::accel::Accelerator` gains `ai_upscale(&self, model: &str, frame: &Frame) -> Option<Frame>`, returning `None` when it cannot run, as the other hooks do. The scale stage asks the accelerator first when the scaler setting names a model, and falls back to Lanczos at the requested factor when the answer is `None`. The runner converts planar YUV to RGB at the tile boundary and back, so the rest of the chain is unchanged. The model's native scale is resampled to the requested scale only when they differ, as the macOS engine does.

Settings: the engine already has `scaler`, `scale_factor`, and the legacy `ai_*` fields (listed as unused). The desktop shows a model choice only once the runner is installed and a `.mupm` is found, so it never shows a setting the engine ignores. The saved preset keeps the field either way.

## Where models and the licence ship

```
<app dir>/
  myupscaler[.exe]
  models/
    RealESRGAN_x2.mupm
    RealESRGAN_x4.mupm
    manifest.json          id, file, scale, sha256, licence file
  licenses/
    RealESRGAN-LICENSE.txt   same text as myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt
```

- The app reads `models/` next to the executable (inside `Contents/Resources` on macOS) and lists the models whose checksum matches the manifest.
- A package that contains a `.mupm` fails its CI check if `licenses/RealESRGAN-LICENSE.txt` is missing or differs from the repository copy.
- Weights are not committed to the repository. CI downloads the upstream weights, checks their SHA-256, converts them, and adds the result to the packages.

## Proposed pull requests

1. **Model runner** (`ai/`): `.mupm` format and loader, the converter, `cpu::run` with a tiled-vs-whole-image test and a tiny synthetic model for unit tests. No GPU, no app change.
2. **GPU runner**: `gpu::run` and the CPU-match test with its tolerance; the `ai_upscale` hook in `backend/accel.rs` and the scale stage, with Lanczos fallback tests.
3. **App selector** (`desktop/`): model picker and progress on the Upscale page, shown only when a model is available; preset field kept; CPU/GPU switch reused from the GPU slice. The matching Swift change is not needed, since the macOS app already has the picker.
4. **Packaging with the licence notice**: CI fetch and convert step, `models/` and `licenses/` in the Windows, Linux and macOS desktop packages, and the check that the notice ships with every model.

Open point: tile size and f16 versus f32 on devices without f16 storage; the first runner PR measures this and fixes the default.
