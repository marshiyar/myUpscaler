# Core Image Metal shaders

`myUpscaler/Native/Process/Shaders/` contains one `.ci.metal` translation unit
per effect. The 21 `extern "C"` entrypoints keep the names, sampler arguments,
scalar parameter order, return types and algorithms used by
`CoreMLProcessingJob.ShaderRegistry`. `ShaderCommon.h` shares Metal/Core Image includes
and color helpers with internal linkage. Bilateral tables and the unsharp box
blur stay with their owning effects.

The application target uses Xcode synchronized folder membership. All 21
`.ci.metal` files must participate in its Sources phase; the header is an
include, not an independently compiled shader. Xcode combines these units into
`Contents/Resources/default.metallib`, which the existing Swift registry loads
once. No individual library paths or Swift kernel names need to change.

The compiled library is required. The former runtime-source fallback referenced
the removed monolithic file and could not load its extern-C ABI: a local test of
the original source returned `CIKernel error 12`. Apple's runtime
[Metal-string API](https://developer.apple.com/documentation/coreimage/cikernel/kernels(withmetalstring:))
requires `[[stitchable]]` functions, as documented in the installed SDK header.
The stale fallback was removed; compiled kernel names and behavior are unchanged.

For Xcode 27, keep `MTL_COMPILER_FLAGS = -fcikernel` and
`MTLLINKER_FLAGS = -fcikernel`. Both phases use the **metal driver**. When invoking
the low-level **metallib** tool directly, its CI flag is `-cikernel`; the installed
version requires a single linked AIR input. Do not replace the driver's flag
with the low-level flag. Compile and link with the same deployment target, such
as `air64-apple-macos15.2`; mixing AIR targets can produce a library without its
kernels even when the linker exits successfully.

Apple describes the underlying Core Image compile/link distinction in
[Build Metal-based Core Image kernels with Xcode](https://developer.apple.com/videos/play/wwdc2020/10021/).
The current driver's flags were also checked against the installed Xcode 27
toolchain and the project's actual MetalLink command.

## Verification

On an Apple Silicon Mac with Xcode 27 and its existing Metal toolchain:

```sh
python3 tests/metal-kernels/run.py
```

The runner compiles and links both precise and fast math variants for macOS
15.2, then builds the app's current registry in an isolated test bundle under
Swift 6 complete concurrency checking, MainActor default isolation, and
warnings as errors. It requires the exact 21 exported entrypoints, verifies
`Bundle.main` loading, and renders 198 finite RGBAf outputs from gradients,
edges, banding and transparent pixels across kernel parameter boundaries.
It does not install tools or fetch assets. A missing GPU is a test failure,
not a runtime success or an implicit skip.

For paired comparison, save the original `Shaders.ci.metal` outside the source
tree before applying the split and pass it to the runner:

```sh
python3 tests/metal-kernels/run.py --baseline-source /path/to/original/Shaders.ci.metal
```

The baseline is compiled with identical flags and rendered with the same
fixtures, ROI, color spaces and parameters. The absolute float tolerance is
`1e-6`; exact-equality counts and maximum difference are reported. Use
`--output-dir /path/to/evidence` to retain libraries, compile logs, test bundles
and runtime reports. `--compile-only` prepares these artifacts without claiming
runtime verification. The executable paths are recorded in `compile-results.json`.

This focused test covers custom shader ABI, registry loading and synthetic
GPU output. Full packaged FFmpeg/CoreML processing, model inference, real video
encoding and execution on macOS 15.2 still require their separate integration
tests. The FFmpeg engine sources are unaffected by the shader split.
