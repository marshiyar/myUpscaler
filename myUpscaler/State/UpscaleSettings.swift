import Foundation
import Combine

nonisolated class UpscaleSettings: ObservableObject {
     var cancellables = Set<AnyCancellable>()

     static var defaultHwAccel: String {
        #if arch(arm64)
        return "videotoolbox"
        #else
        return "none"
        #endif
    }

     static var defaultEncoder: String { "auto" }

    init() {
        cancellables = SettingsNormalization.install(on: self)
    }

    // --- Codec & Rate ---
    @Published var useHEVC: Bool = false
    @Published var crf: Double = 20.0 // CRF default
    @Published var preset: String = "faster"
    @Published var use10Bit: Bool = false

    // x265 Parameters - individual values
    @Published var x265AqMode: String = "3"
    @Published var x265PsyRd: String = "2.0"
    @Published var x265Deblock1: String = "-2"
    @Published var x265Deblock2: String = "-2"

    // Computed property that builds the x265 params string
    var x265Params: String {
        var params: [String] = []
        if !x265AqMode.isEmpty {
            params.append("aq-mode=\(x265AqMode)")
        }
        if !x265PsyRd.isEmpty {
            params.append("psy-rd=\(x265PsyRd)")
        }
        if !x265Deblock1.isEmpty || !x265Deblock2.isEmpty {
            let deblock = "deblock=\(x265Deblock1),\(x265Deblock2)"
            params.append(deblock)
        }
        return params.joined(separator: ",")
    }

    // --- Hardware ---
    @Published var hwAccel: String = UpscaleSettings.defaultHwAccel
    @Published var encoder: String = UpscaleSettings.defaultEncoder
    @Published var threads: String = "0"  // 0 = auto

    // --- Frame & Scale ---
    @Published var fps: String = "60"
    @Published var scaleFactor: Double = 2.0
    @Published var interpolation: String = "mci"

    // --- AI Upscaling ---
    @Published var scaler: String = "lanczos"
    @Published var coremlModelId: CoreMLModelID = .realESRGANx4
    @Published var aiModelPath: String = ""
    @Published var aiBackend: String = "sr"
    @Published var aiModelType: String = "espcn"
    @Published var dnnBackend: String = "native"

    // --- Restoration Filters - First Set ---
    @Published var denoiser: String = "bm3d"
    @Published var denoiseStrength: String = "2.5"

    @Published var deblockMode: String = "strong"
    @Published var deblockThresh: String = ""

    @Published var deringActive: Bool = false
    @Published var deringStrength: String = "0.5"

    @Published var sharpenMethod: String = "cas"
    @Published var sharpenStrength: String = "0.25"

    // Unsharp Mask
    @Published var usmRadius: String = "5"
    @Published var usmAmount: String = "1.0"
    @Published var usmThreshold: String = "0.03"

    @Published var debandMethod: String = "deband"
    @Published var debandStrength: String = "0.015"

    // F3KDB
    @Published var f3kdbRange: String = "15"
    @Published var f3kdbY: String = "64"
    @Published var f3kdbCbCr: String = "64"

    @Published var grainStrength: String = "1.0"

    // --- Restoration Filters - Second Set ---
    @Published var denoiser2: String = "bm3d"
    @Published var denoiseStrength2: String = "2.5"
    @Published var useDenoise2: Bool = false

    @Published var deblockMode2: String = "strong"
    @Published var deblockThresh2: String = ""
    @Published var useDeblock2: Bool = false

    @Published var deringActive2: Bool = false
    @Published var deringStrength2: String = "0.5"
    @Published var useDering2: Bool = false

    @Published var sharpenMethod2: String = "cas"
    @Published var sharpenStrength2: String = "0.25"
    @Published var useSharpen2: Bool = false

    // Unsharp Mask 2
    @Published var usmRadius2: String = "5"
    @Published var usmAmount2: String = "1.0"
    @Published var usmThreshold2: String = "0.03"

    @Published var debandMethod2: String = "deband"
    @Published var debandStrength2: String = "0.015"
    @Published var useDeband2: Bool = false

    // F3KDB 2
    @Published var f3kdbRange2: String = "15"
    @Published var f3kdbY2: String = "64"
    @Published var f3kdbCbCr2: String = "64"

    @Published var grainStrength2: String = "1.0"
    @Published var useGrain2: Bool = false

    // --- Color / Equalization ---
    @Published var eqContrast: String = "1.0"
    @Published var eqBrightness: String = "0.0"
    @Published var eqSaturation: String = "1.0"
//    @Published var lutPath: String = "" // LUT DEACTIVATED

    // --- Metal Pre/Post Processing ---
    @Published var enableColorLinearize: Bool = true
    @Published var colorExposure: String = "1.0"
    @Published var enableToneMap: Bool = false
    @Published var toneMapExposure: String = "1.0"
    @Published var encodeToSRGB: Bool = true
    @Published var encodeExposure: String = "1.0"
    @Published var gammaBlendWeight: String = "0.0"
    @Published var useMedianPrefilter: Bool = false
    @Published var useBlueNoiseDeband: Bool = true
    @Published var useLaplacianSharpen: Bool = false
    @Published var laplacianStrength: String = "0.15"
    @Published var useDehalo: Bool = false
    @Published var dehaloStrength: String = "0.25"
    @Published var useMoireSuppress: Bool = false
    @Published var moireStrength: String = "0.2"
    @Published var alphaSafeProcessing: Bool = true
    @Published var useCosineFeather: Bool = true
    @Published var tileFeatherMargin: String = "0"
    @Published var useTemporalSmoothing: Bool = false
    @Published var temporalStrength: String = "0.15"
    @Published var maskFeatherRadius: String = "0"
    @Published var maskDilateRadius: String = "0"
    @Published var maskErodeRadius: String = "0"

    // --- I/O ---
    @Published var audioBitrate: String = "192k"
    @Published var movflags: String = "+faststart"

    // --- Toggles & Modes ---
    @Published var noDeblock: Bool = false
    @Published var noDenoise: Bool = false
    @Published var noDecimate: Bool = false
    @Published var noInterpolate: Bool = false
    @Published var noSharpen: Bool = false
    @Published var noDeband: Bool = false
    @Published var noEq: Bool = false
    @Published var noGrain: Bool = false
    // DISABLED: Region Masks defaulted off
//    @Published var regionMasksEnabled: Bool = false
    // DISABLED: Quality Analyzer defaulted off
    @Published var useQualityAnalyzer: Bool = false
    // DISABLED: Drift Guard defaulted off
    @Published var useDriftGuard: Bool = false
    @Published var pciSafe: Bool = false
    @Published var dryRun: Bool = false
    @Published var preview: Bool = false

    // Constants
    let presets = ["veryfast", "faster", "medium"] // REMOVED  "slow", "slower", "veryslow"
    let interpolations = ["mci", "blend"]
    var coremlModels: [CoreMLModelSpec] { CoreMLModelRegistry.bundledModels }
    var scalers: [String] {
        UpscalingModeSupport.scalers(bundledModelIDs: coremlModels.map { $0.id.rawValue })
    }
    var upscalingUnavailableReason: String? {
        UpscalingModeSupport.unavailableReason(scaler: scaler, modelID: coremlModelId.rawValue,
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

    // MARK: - Reset to Defaults
    /// Resets all settings to their default values
    func resetToDefaults() {
        // Codec & Rate
        useHEVC = false
        crf = 20.0 // DEFAULT FROM 16 to 20
        preset = "faster" // DEFAULT CHANGE TO FASTER FROM SLOW — slow no longer exists MONDAY, JAN , 5th 2026 update
        use10Bit = false

        // x265 Parameters
        x265AqMode = "3"
        x265PsyRd = "2.0"
        x265Deblock1 = "-2"
        x265Deblock2 = "-2"

        // Hardware
        hwAccel = UpscaleSettings.defaultHwAccel
        encoder = UpscaleSettings.defaultEncoder
        threads = "0"

        // Frame & Scale
        fps = "60"
        scaleFactor = 2.0
        interpolation = "mci"

        // AI Upscaling
        scaler = "lanczos"
        coremlModelId = .realESRGANx4
        aiModelPath = ""
        aiBackend = "sr"
        aiModelType = "espcn"
        dnnBackend = "native"

        // Restoration Filters - First Set
        denoiser = "bm3d"
        denoiseStrength = "2.5"
        deblockMode = "strong"
        deblockThresh = ""
        deringActive = false
        deringStrength = "0.5"
        sharpenMethod = "cas"
        sharpenStrength = "0.25"
        usmRadius = "5"
        usmAmount = "1.0"
        usmThreshold = "0.03"
        debandMethod = "deband"
        debandStrength = "0.015"
        f3kdbRange = "15"
        f3kdbY = "64"
        f3kdbCbCr = "64"
        grainStrength = "1.0"

        // Restoration Filters - Second Set
        denoiser2 = "bm3d"
        denoiseStrength2 = "2.5"
        useDenoise2 = false
        deblockMode2 = "strong"
        deblockThresh2 = ""
        useDeblock2 = false
        deringActive2 = false
        deringStrength2 = "0.5"
        useDering2 = false
        sharpenMethod2 = "cas"
        sharpenStrength2 = "0.25"
        useSharpen2 = false
        usmRadius2 = "5"
        usmAmount2 = "1.0"
        usmThreshold2 = "0.03"
        debandMethod2 = "deband"
        debandStrength2 = "0.015"
        useDeband2 = false
        f3kdbRange2 = "15"
        f3kdbY2 = "64"
        f3kdbCbCr2 = "64"
        grainStrength2 = "1.0"
        useGrain2 = false

        // Color / Equalization
        eqContrast = "1.00"
        eqBrightness = "0.000"
        eqSaturation = "1.00"
//        lutPath = "" // LUT DEACTIVATED

        // Metal Pre/Post
        enableColorLinearize = true
        colorExposure = "1.0"
        enableToneMap = false
        toneMapExposure = "1.0"
        encodeToSRGB = true
        encodeExposure = "1.0"
        gammaBlendWeight = "0.0"
        useMedianPrefilter = false
        useBlueNoiseDeband = true
        useLaplacianSharpen = false
        laplacianStrength = "0.15"
        useDehalo = false
        dehaloStrength = "0.25"
        useMoireSuppress = false
        moireStrength = "0.2"
        alphaSafeProcessing = true
        useCosineFeather = true
        tileFeatherMargin = "0"
        useTemporalSmoothing = false
        temporalStrength = "0.15"
        maskFeatherRadius = "0"
        maskDilateRadius = "0"
        maskErodeRadius = "0"

        // I/O
        audioBitrate = "192k"
        movflags = "+faststart"

        // Toggles & Modes
        noDeblock = false
        noDenoise = false
        noDecimate = false
        noInterpolate = false
        noSharpen = false
        noDeband = false
        noEq = false
        noGrain = false
        useQualityAnalyzer = false
        useDriftGuard = false
        pciSafe = false
        dryRun = false
        preview = false
    }
}
