# Source organization and ownership

The app keeps one authoritative settings object for the UI. A job captures a separate settings snapshot before leaving the UI executor. `UpscaleRunner` owns start/cancel/finish transitions; output file stability and view callbacks do not decide whether an engine is done.

`Processing/CoreMLEngine` owns one invocation at a time. `ProcessingControl` tracks cancellation through teardown. The worker is explicitly nonisolated because pixel conversion, prediction preparation and blending must not run on the default UI actor. Models retain at most one cached MLModel. Encoder buffers come from a reusable pool; a frame's weight map is reset and reused. `VideoIO` encapsulates the macOS 26+ asynchronous reader/writer APIs and the macOS 15.2 fallback.

`UpscaleGeometry` separates native model tile size from final output size. The model runs once per tile, never once per requested scale factor. Native output is resampled only when scales differ, and only the valid tile region is resized. Tensor output respects runtime strides and rejects nonfinite pixels.

`State/EditorState` owns preview request generations, cache identity and latest-only scheduling. Media loading publishes only if its input/frame generation still owns the request. The renderer receives immutable parameters; rendering does not read mutable UI state. The preview remains approximate rather than an export-equivalence guarantee.

`State/UpscaleSettings` holds observable values and resets. `SettingsNormalization` installs value/toggle subscriptions; `SettingsParameterRules` defines shared parameter bounds/validation; `SettingsFilterStacking` derives attenuation and warnings from the same settings. These are responsibilities of one configuration, not parallel copies of enabled flags. Preset snapshots retain legacy fields for decoding compatibility.

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
