import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

require(UpscalingModeSupport.scalers(bundledModelIDs: []) == ["lanczos"],
        "An app without models must expose only Lanczos")
require(UpscalingModeSupport.scalers(bundledModelIDs: ["RealESRGAN_x2"]) == ["lanczos", "coreml"],
        "CoreML must appear when a bundled model exists")
for mode in ["ai", "zscale", "hw", "unknown", ""] {
    require(UpscalingModeSupport.unavailableReason(scaler: mode, modelID: "RealESRGAN_x2",
                bundledModelIDs: ["RealESRGAN_x2"]) != nil,
            "Legacy or unknown mode \(mode) must be rejected")
}
require(UpscalingModeSupport.unavailableReason(scaler: "lanczos", modelID: "missing",
            bundledModelIDs: []) == nil, "Lanczos must work without AI models")
require(UpscalingModeSupport.unavailableReason(scaler: "coreml", modelID: "RealESRGAN_x2",
            bundledModelIDs: ["RealESRGAN_x2"]) == nil, "An included model must be selectable")
require(UpscalingModeSupport.unavailableReason(scaler: "coreml", modelID: "RealESRGAN_x4",
            bundledModelIDs: ["RealESRGAN_x2"]) != nil,
        "A saved preset cannot use a missing model when another model exists")
require(UpscalingModeSupport.unavailableReason(scaler: "coreml", modelID: "RealESRGAN_x2",
            bundledModelIDs: []) != nil, "CoreML cannot run without model resources")
print("11 upscaling availability checks passed")
