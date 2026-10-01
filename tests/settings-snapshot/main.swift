import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

// Run uses this production snapshot/apply path to clone the selected settings.
// Model selection and requested output scale are independent values.
for model in CoreMLModelID.allCases {
    for scale in [2.0, 4.0, 8.0] {
        let selected = UpscaleSettings()
        selected.scaler = "coreml"
        selected.coremlModelId = model
        selected.scaleFactor = scale
        let snapshot = UpscaleSettingsSnapshot(settings: selected)
        let render = UpscaleSettings()
        snapshot.apply(to: render)
        require(render.coremlModelId == model, "Run must preserve the selected model")
        require(render.scaler == "coreml", "Run must preserve CoreML engine selection")
        require(render.scaleFactor == scale, "Output scale must survive Run independently of the model")
        require(CoreMLModelRegistry.model(for: render.coremlModelId).id == model,
                "The renderer must resolve the selected model")

        let preset = Preset(name: "Model selection", snapshot: snapshot)
        let data = try JSONEncoder().encode(preset)
        let restored = try JSONDecoder().decode(Preset.self, from: data)
        require(restored == preset, "Preset save/load must preserve model selection")
        let applied = UpscaleSettings()
        restored.snapshot.apply(to: applied)
        require(applied.coremlModelId == model, "Applying a saved preset must restore its model")
        require(applied.scaleFactor == scale, "Applying a saved preset must restore its output scale")
    }
}

let defaults = UpscaleSettings()
let selected = UpscaleSettings()
selected.coremlModelId = .realESRGANx2
selected.scaleFactor = 8
let data = try JSONEncoder().encode(UpscaleSettingsSnapshot(settings: selected))
var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacy.removeValue(forKey: "coremlModelId")
let legacyData = try JSONSerialization.data(withJSONObject: legacy)
let migrated = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: legacyData)
let applied = UpscaleSettings()
applied.coremlModelId = .realESRGANx2
migrated.apply(to: applied)
require(applied.coremlModelId == defaults.coremlModelId, "Old presets must keep their historical default model")
require(applied.scaleFactor == 8, "Old presets must retain their requested scale")

let minimal = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: Data("{}".utf8))
require(minimal.coremlModelId == defaults.coremlModelId, "Missing model field must decode using the historical default")
require(CoreMLModelRegistry.model(for: .realESRGANx4).nativeScale == 4,
        "An 8x output setting must not invent an 8x AI model")
print("Settings snapshot regression checks passed: model cloning, preset round trips, output scales, and old presets.")
