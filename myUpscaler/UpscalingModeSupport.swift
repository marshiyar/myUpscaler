import Foundation

/// Modes implemented and supported by the pinned FFmpeg bundle. Legacy DNN,
/// zscale, and hardware-scaler presets remain decodable, but are not runnable.
enum UpscalingModeSupport {
    static func scalers(bundledModelIDs: [String]) -> [String] {
        bundledModelIDs.isEmpty ? ["lanczos"] : ["lanczos", "coreml"]
    }

    static func unavailableReason(scaler: String, modelID: String,
                                  bundledModelIDs: [String]) -> String? {
        if scaler == "lanczos" { return nil }
        if scaler == "coreml" {
            return bundledModelIDs.contains(modelID) ? nil :
                "The selected CoreML model is not included in this app. Choose Lanczos or an included model."
        }
        return "The saved upscaling mode is unavailable in this app. Choose Lanczos or an included CoreML model."
    }

    static func label(for scaler: String) -> String {
        scaler == "coreml" ? "CoreML" : "Lanczos"
    }
}
