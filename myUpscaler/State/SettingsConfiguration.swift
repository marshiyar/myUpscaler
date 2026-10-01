import Foundation

/// Editable numeric draft: preserve partial input until a render snapshot parses it.
nonisolated struct NumericDraft: Equatable {
    var text: String
    var finiteValue: Double? { guard let value = Double(text), value.isFinite else { return nil }; return value }
}

nonisolated struct RestorationStage: Equatable {
    var denoiser: String = "bm3d"
    var denoiseStrength: NumericDraft = NumericDraft(text: "2.5")
    var deblockMode: String = "strong"
    var deblockThresh: NumericDraft = NumericDraft(text: "")
    var useDering: Bool = false
    var deringStrength: NumericDraft = NumericDraft(text: "0.5")
    var sharpenMethod: String = "cas"
    var sharpenStrength: NumericDraft = NumericDraft(text: "0.25")
    var usmRadius: NumericDraft = NumericDraft(text: "5")
    var usmAmount: NumericDraft = NumericDraft(text: "1.0")
    var usmThreshold: NumericDraft = NumericDraft(text: "0.03")
    var debandMethod: String = "deband"
    var debandStrength: NumericDraft = NumericDraft(text: "0.015")
    var f3kdbRange: NumericDraft = NumericDraft(text: "15")
    var f3kdbY: NumericDraft = NumericDraft(text: "64")
    var f3kdbCbCr: NumericDraft = NumericDraft(text: "64")
    var grainStrength: NumericDraft = NumericDraft(text: "1.0")
    var useDeblock: Bool = true
    var useDenoise: Bool = true
    var useSharpen: Bool = true
    var useDeband: Bool = true
    var useGrain: Bool = true

    static var secondary: RestorationStage {
        var stage = RestorationStage()
        stage.useDenoise = false
        stage.useDeblock = false
        stage.useDering = false
        stage.useSharpen = false
        stage.useDeband = false
        stage.useGrain = false
        return stage
    }
}

nonisolated struct CodecSettings: Equatable {
    var useHEVC: Bool = false
    var crf: Double = 20.0
    var preset: String = "faster"
    var use10Bit: Bool = false
    var x265AqMode: NumericDraft = NumericDraft(text: "3")
    var x265PsyRd: NumericDraft = NumericDraft(text: "2.0")
    var x265Deblock1: NumericDraft = NumericDraft(text: "-2")
    var x265Deblock2: NumericDraft = NumericDraft(text: "-2")
}

nonisolated struct HardwareSettings: Equatable {
    var hwAccel: String = UpscaleSettings.defaultHwAccel
    var encoder: String = UpscaleSettings.defaultEncoder
    var threads: NumericDraft = NumericDraft(text: "0")
}

nonisolated struct VideoSettings: Equatable {
    var fps: NumericDraft = NumericDraft(text: "60")
    var scaleFactor: Double = 2.0
    var interpolation: String = "mci"
}

nonisolated struct UpscalingSettings: Equatable {
    var scaler: String = "lanczos"
    var coremlModelId: CoreMLModelID = .realESRGANx4
    var aiModelPath: String = ""
    var aiBackend: String = "sr"
    var aiModelType: String = "espcn"
    var dnnBackend: String = "native"
}

nonisolated struct ColorSettings: Equatable {
    var eqContrast: NumericDraft = NumericDraft(text: "1.0")
    var eqBrightness: NumericDraft = NumericDraft(text: "0.0")
    var eqSaturation: NumericDraft = NumericDraft(text: "1.0")
    var noEq: Bool = false
}

nonisolated struct MetalSettings: Equatable {
    var enableColorLinearize: Bool = true
    var colorExposure: NumericDraft = NumericDraft(text: "1.0")
    var enableToneMap: Bool = false
    var toneMapExposure: NumericDraft = NumericDraft(text: "1.0")
    var encodeToSRGB: Bool = true
    var encodeExposure: NumericDraft = NumericDraft(text: "1.0")
    var gammaBlendWeight: NumericDraft = NumericDraft(text: "0.0")
    var useMedianPrefilter: Bool = false
    var useBlueNoiseDeband: Bool = true
    var useLaplacianSharpen: Bool = false
    var laplacianStrength: NumericDraft = NumericDraft(text: "0.15")
    var useDehalo: Bool = false
    var dehaloStrength: NumericDraft = NumericDraft(text: "0.25")
    var useMoireSuppress: Bool = false
    var moireStrength: NumericDraft = NumericDraft(text: "0.2")
    var alphaSafeProcessing: Bool = true
    var useCosineFeather: Bool = true
    var tileFeatherMargin: NumericDraft = NumericDraft(text: "0")
    var useTemporalSmoothing: Bool = false
    var temporalStrength: NumericDraft = NumericDraft(text: "0.15")
    var maskFeatherRadius: NumericDraft = NumericDraft(text: "0")
    var maskDilateRadius: NumericDraft = NumericDraft(text: "0")
    var maskErodeRadius: NumericDraft = NumericDraft(text: "0")
}

nonisolated struct OutputSettings: Equatable {
    var audioBitrate: String = "192k"
    var movflags: String = "+faststart"
}

nonisolated struct ModesSettings: Equatable {
    var noDecimate: Bool = false
    var noInterpolate: Bool = false
    var useQualityAnalyzer: Bool = false
    var useDriftGuard: Bool = false
    var pciSafe: Bool = false
    var dryRun: Bool = false
    var preview: Bool = false
}

nonisolated struct SettingsConfiguration: Equatable {
    var codec = CodecSettings()
    var hardware = HardwareSettings()
    var video = VideoSettings()
    var upscaling = UpscalingSettings()
    var primary = RestorationStage()
    var secondary = RestorationStage.secondary
    var color = ColorSettings()
    var metal = MetalSettings()
    var output = OutputSettings()
    var modes = ModesSettings()
}
