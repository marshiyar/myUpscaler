# Source organization and ownership

The app keeps one authoritative settings object for the UI. A job captures a separate settings snapshot before leaving the UI executor. `UpscaleRunner` owns start/cancel/finish transitions; output file stability and view callbacks do not decide whether an engine is done.

`Processing/CoreMLEngine` owns one invocation at a time. `ProcessingControl` tracks cancellation through teardown. A per-run `CoreMLProcessingJob` actor owns I/O, conversion and blending away from the UI actor. `ModelManager` owns at most one cached MLModel on its own actor; prediction receives fresh transferred tensors and returns fresh pixel storage. Encoder buffers come from a reusable pool; a frame's weight map is reset and reused. `VideoIO` encapsulates the macOS 26+ asynchronous reader/writer APIs and the macOS 15.2 fallback.

`UpscaleGeometry` separates native model tile size from final output size. The model runs once per tile, never once per requested scale factor. Native output is resampled only when scales differ, and only the valid tile region is resized. Tensor output respects runtime strides and rejects nonfinite pixels.

`State/EditorState` owns preview request generations, cache identity and latest-only scheduling. Media loading publishes only if its input/frame generation still owns the request. The renderer receives immutable parameters; rendering does not read mutable UI state. The preview remains approximate rather than an export-equivalence guarantee.

`State/UpscaleSettings` is explicitly MainActor-isolated and holds published UI values and resets. `SettingsConfiguration` is a Sendable value; `SettingsNormalization` transforms that value before a single publication; `SettingsParameterRules` defines shared parameter bounds/validation; `SettingsFilterStacking` derives attenuation and warnings from the same settings. These are responsibilities of one configuration, not parallel copies of enabled flags. Preset snapshots retain legacy fields for decoding compatibility. Their nonisolated decoding and configuration initializer do not create a UI observable; only capture/application of UI settings requires MainActor.

`Views` contains focused panels. SwiftUI state stays with its owning component. Native sliders replace overlapping custom gestures. Encoding choices are conditional on the actual selected engine and codec, and the persistent footer reads runner-owned progress.

`Native` retains the C engine and supervised FFmpeg process boundary. `Native/Process` includes the Objective-C bridge and process/path helpers. The Xcode app target uses synchronized folder membership; the independent XCTest target explicitly lists its required source files. Scripts and tests must be updated alongside file moves.

## File budget

Maintained application `.swift`, `.c`, `.h`, `.m` and `.metal` files target roughly 500 lines and must stay within 600 lines. `scripts/check-source-budget.py` enforces the ceiling. Focused files can be shorter. Vendor material, licenses, compiled models and generated/build outputs are not split or rewritten to satisfy this rule. The current maintained source has no ceiling exemptions.

Split by an identifiable responsibility and explicit ownership boundary, not arbitrary line numbers. Keep request generations and cancellation handles with their coordinator. Keep dynamically loaded shader entry points, valid OS fallbacks, preset migration fields and upstream notices even when a simple static reference search finds no direct call.

## Dead code removed

- File-size completion polling and view-triggered completion checks: engine return now owns completion and validates the output.
- Unused regex extraction helper: the parser uses its combined expression.
- Unused `QualityAnalyzer` implementation and synchronous preview-filter wrapper: no source callers remained; preview rendering uses the bounded background path. Legacy preset fields remain decodable.
- Declaration-only x265 string parser, drop area, duplicate slider and unused scroll-background wrapper: actual controls use the maintained bindings and native slider implementation.

The engine/logic fixes and UI changes are local commits preceding the source reorganization, so this batch can be reviewed or reverted independently. No remote publication is part of these changes.

## Executor boundaries

The app target keeps its existing MainActor default isolation and Swift language mode. Explicit boundaries describe ownership rather than suppress diagnostics. Complete concurrency checking and warnings-as-errors remain enabled.

| Boundary | Work and ownership |
| --- | --- |
| MainActor: settings, runner, editor, preset/shortcut stores and views | UI publications, immutable snapshot capture, command validation and start/cancel/finish state. Settings normalization and preset decoding remain pure value operations. |
| CoreMLProcessingJob actor | One run's reader/writer, frame conversion, sequential tile blending and cancellation. A cancellation check immediately after prediction prevents cancelled work from continuing into resampling/blending. |
| ModelManager actor | Model preparation, cached model and prediction. Fresh input/output ownership transfers at the actor boundary; mutable MLModel does not escape. |
| VideoIO nonisolated(nonsending) async methods | Stay on the owning caller's executor. Mutable frame access is synchronous; completed frames are read-only before writer/previous-frame use. |
| VideoAudioMuxer @concurrent | AVFoundation audio muxing away from UI ownership, with cancellation and immutable URL/log inputs. |
| Native engine detached task | Source timing and blocking supervised FFmpeg processing. Short MainActor hops report diagnostics and lifecycle state; callbacks and reads do not hold ownership locks. |
| Preview renderer queue | Render immutable filter parameters. Request generation/cache publication stays with the editor; stale results are discarded. |
| Nonisolated value/helper types | Configuration, normalization, codec checks, geometry, tensor metadata, progress gate, checked buffer access and immutable shader registry. They do not read mutable UI state. |

The existing small x4 inference/export harness measures main-actor heartbeat progress while model work runs. It does not prove responsiveness for every workload. Still-image loading, initial CIContext/Metal setup and cache image extraction have potential synchronous UI costs; they need bounded measurements before changing their implementation. No unchecked Sendable, unsafe isolation annotation or preconcurrency suppression is used.
