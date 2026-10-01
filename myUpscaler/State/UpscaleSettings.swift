import Foundation
import Combine

nonisolated class UpscaleSettings: ObservableObject {
     static var defaultHwAccel: String {
        #if arch(arm64)
        return "videotoolbox"
        #else
        return "none"
        #endif
    }

     static var defaultEncoder: String { "auto" }

    @Published private(set) var configuration = SettingsConfiguration()

    init() {}

    /// Restore the complete saved state without interactive toggle defaults.
    /// Identical presets produce identical state regardless of the prior target.
    func replaceConfiguration(_ candidate: SettingsConfiguration) {
        if candidate != configuration { configuration = candidate }
    }

    private func update<Value>(_ path: WritableKeyPath<SettingsConfiguration, Value>, _ value: Value) {
        var next = configuration
        next[keyPath: path] = value
        SettingsNormalization.normalize(&next, previous: configuration)
        if next != configuration { configuration = next }
    }

    var codec: CodecSettings {
        get { configuration.codec }
        set { update(\.codec, newValue) }
    }
    var hardware: HardwareSettings {
        get { configuration.hardware }
        set { update(\.hardware, newValue) }
    }
    var video: VideoSettings {
        get { configuration.video }
        set { update(\.video, newValue) }
    }
    var upscaling: UpscalingSettings {
        get { configuration.upscaling }
        set { update(\.upscaling, newValue) }
    }
    var primary: RestorationStage {
        get { configuration.primary }
        set { update(\.primary, newValue) }
    }
    var secondary: RestorationStage {
        get { configuration.secondary }
        set { update(\.secondary, newValue) }
    }
    var color: ColorSettings {
        get { configuration.color }
        set { update(\.color, newValue) }
    }
    var metal: MetalSettings {
        get { configuration.metal }
        set { update(\.metal, newValue) }
    }
    var output: OutputSettings {
        get { configuration.output }
        set { update(\.output, newValue) }
    }
    var modes: ModesSettings {
        get { configuration.modes }
        set { update(\.modes, newValue) }
    }

    // Computed property that builds the x265 params string
    var x265Params: String {
        var params: [String] = []
        if !codec.x265AqMode.text.isEmpty {
            params.append("aq-mode=\(codec.x265AqMode.text)")
        }
        if !codec.x265PsyRd.text.isEmpty {
            params.append("psy-rd=\(codec.x265PsyRd.text)")
        }
        if !codec.x265Deblock1.text.isEmpty || !codec.x265Deblock2.text.isEmpty {
            let deblock = "deblock=\(codec.x265Deblock1.text),\(codec.x265Deblock2.text)"
            params.append(deblock)
        }
        return params.joined(separator: ",")
    }


    // Constants
    let presets = ["veryfast", "faster", "medium"] // REMOVED  "slow", "slower", "veryslow"
    let interpolations = ["mci", "blend"]
    var coremlModels: [CoreMLModelSpec] { CoreMLModelRegistry.bundledModels }
    var scalers: [String] {
        UpscalingModeSupport.scalers(bundledModelIDs: coremlModels.map { $0.id.rawValue })
    }
    var upscalingUnavailableReason: String? {
        UpscalingModeSupport.unavailableReason(scaler: upscaling.scaler, modelID: upscaling.coremlModelId.rawValue,
                                               bundledModelIDs: coremlModels.map { $0.id.rawValue })
    }
    let denoisers = ["bm3d", "nlmeans", "hqdn3d", "atadenoise"]
    let sharpenMethods = ["cas", "unsharp"]
    let debandMethods = ["deband", "gradfun", "f3kdb"]
    #if arch(x86_64)
    // On Intel Macs, Quick Sync (qsv) and VideoToolbox are available; CUDA/VAAPI are not macOS‑friendly.
    let hwAccels = ["none", "qsv", "videotoolbox"]
    let encoders = ["auto", "cpu", "qsv", "videotoolbox"]
    #else
    // On Apple Silicon Macs, only software and VideoToolbox HW paths are valid.
    let hwAccels = ["none", "videotoolbox"]
    let encoders = ["auto", "cpu", "videotoolbox"]
    #endif
    let deblockModes = ["weak", "strong"]

    /// One mutation publishes a complete reset; defaults have one source of truth.
    func resetToDefaults() { configuration = SettingsConfiguration() }
}
