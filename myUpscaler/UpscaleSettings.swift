import Foundation
import Combine

class UpscaleSettings: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    
    private static var defaultHwAccel: String {
        #if arch(arm64)
        return "videotoolbox"
        #else
        return "none"
        #endif
    }
    
    private static var defaultEncoder: String { "auto" }
    
    init() {
        setupValueObservers()
    }
    
    func parseX265Params(from paramsString: String) {
        x265AqMode = "3"
        x265PsyRd = "2.0"
        x265Deblock1 = "-2"
        x265Deblock2 = "-2"
        
        // Try to parse from existing x265Params string (handles both : and , separators)
        let params = paramsString.replacingOccurrences(of: ":", with: ",")
        let components = params.split(separator: ",")
        
        for component in components {
            let part = String(component).trimmingCharacters(in: .whitespaces)
            if part.hasPrefix("aq-mode=") {
                x265AqMode = String(part.dropFirst("aq-mode=".count))
            } else if part.hasPrefix("psy-rd=") {
                x265PsyRd = String(part.dropFirst("psy-rd=".count))
            } else if part.hasPrefix("deblock=") {
                let deblockValue = String(part.dropFirst("deblock=".count))
                let deblockParts = deblockValue.split(separator: ",")
                if deblockParts.count >= 1 {
                    x265Deblock1 = String(deblockParts[0])
                }
                if deblockParts.count >= 2 {
                    x265Deblock2 = String(deblockParts[1])
                }
            }
        }
    }
    
    // MARK: - Auto-toggle management when values become 0
    private func setupValueObservers() {
        $denoiser
            .sink { [weak self] newDenoiser in
                guard let self = self else { return }
                self.denoiseStrength = self.validateDenoiseStrength(self.denoiseStrength, forDenoiser: newDenoiser)
            }
            .store(in: &cancellables)
        
        $denoiser2
            .sink { [weak self] newDenoiser in
                guard let self = self else { return }
                self.denoiseStrength2 = self.validateDenoiseStrength(self.denoiseStrength2, forDenoiser: newDenoiser)
            }
            .store(in: &cancellables)
        
        $denoiseStrength2
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDenoise2 = false
                }
            }
            .store(in: &cancellables)
        
        $sharpenMethod
            .sink { [weak self] newMethod in
                guard let self = self else { return }
                self.sharpenStrength = self.validateSharpenStrength(self.sharpenStrength)
            }
            .store(in: &cancellables)
        
        $sharpenMethod2
            .sink { [weak self] newMethod in
                guard let self = self else { return }
                self.sharpenStrength2 = self.validateSharpenStrength(self.sharpenStrength2)
            }
            .store(in: &cancellables)
        
        $debandMethod
            .sink { [weak self] newMethod in
                guard let self = self else { return }
                self.debandStrength = self.validateDebandStrength(self.debandStrength)
            }
            .store(in: &cancellables)
        
        $debandMethod2
            .sink { [weak self] newMethod in
                guard let self = self else { return }
                self.debandStrength2 = self.validateDebandStrength(self.debandStrength2)
            }
            .store(in: &cancellables)
        
        $deringStrength
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.deringActive = false
                }
            }
            .store(in: &cancellables)
        
        $deringActive
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZero(self.deringStrength) {
                    self.deringStrength = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)
        
        // Note: denoiseStrength2 validation is handled above in the combined observer
        
        $useDenoise2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZero(self.denoiseStrength2) {
                    self.denoiseStrength2 = self.defaultDenoiseStrength2String
                }
            }
            .store(in: &cancellables)
        
        $deblockThresh2
            .sink { [weak self] value in
                guard let self = self else { return }
                if value.isEmpty || value == "0" || (Double(value) ?? 0) == 0 {
                    self.useDeblock2 = false
                }
            }
            .store(in: &cancellables)
        

        $useDeblock2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZeroOrEmpty(self.deblockThresh2) {
                    self.deblockThresh2 = self.defaultDeblockThreshString
                }
            }
            .store(in: &cancellables)
        

        $deringStrength2
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDering2 = false
                    self.deringActive2 = false
                }
            }
            .store(in: &cancellables)
        

        $useDering2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZero(self.deringStrength2) {
                    self.deringStrength2 = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)
        

        $deringActive2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZero(self.deringStrength2) {
                    self.deringStrength2 = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)
        

        $sharpenStrength2
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useSharpen2 = false
                }
            }
            .store(in: &cancellables)
        

        Publishers.CombineLatest3($usmRadius2, $usmAmount2, $usmThreshold2)
            .sink { [weak self] radius, amount, threshold in
                guard let self = self else { return }
                if self.sharpenMethod2 == "unsharp" {
                    let radiusVal = Double(radius) ?? 0
                    let amountVal = Double(amount) ?? 0
                    let thresholdVal = Double(threshold) ?? 0
                    if radiusVal == 0 && amountVal == 0 && thresholdVal == 0 {
                        self.useSharpen2 = false
                    }
                }
            }
            .store(in: &cancellables)
        

        $useSharpen2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.sharpenMethod2 == "cas" {
                    if self.isZero(self.sharpenStrength2) {
                        self.sharpenStrength2 = self.defaultSharpenStrength2String
                    }
                } else if self.sharpenMethod2 == "unsharp" {
                    let radiusVal = Double(self.usmRadius2) ?? 0
                    let amountVal = Double(self.usmAmount2) ?? 0
                    let thresholdVal = Double(self.usmThreshold2) ?? 0
                    if radiusVal == 0 && amountVal == 0 && thresholdVal == 0 {
                        self.usmRadius2 = self.defaultUsmRadius2String
                        self.usmAmount2 = self.defaultUsmAmount2String
                        self.usmThreshold2 = self.defaultUsmThreshold2String
                    }
                }
            }
            .store(in: &cancellables)
        
        $debandStrength2
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDeband2 = false
                }
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest3($f3kdbRange2, $f3kdbY2, $f3kdbCbCr2)
            .sink { [weak self] range, y, cbcr in
                guard let self = self else { return }
                if self.debandMethod2 == "f3kdb" {
                    let rangeVal = Double(range) ?? 0
                    let yVal = Double(y) ?? 0
                    let cbcrVal = Double(cbcr) ?? 0
                    if rangeVal == 0 && yVal == 0 && cbcrVal == 0 {
                        self.useDeband2 = false
                    }
                }
            }
            .store(in: &cancellables)
        
        $useDeband2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.debandMethod2 == "f3kdb" {
                    let rangeVal = Double(self.f3kdbRange2) ?? 0
                    let yVal = Double(self.f3kdbY2) ?? 0
                    let cbcrVal = Double(self.f3kdbCbCr2) ?? 0
                    if rangeVal == 0 && yVal == 0 && cbcrVal == 0 {
                        self.f3kdbRange2 = self.defaultF3kdbRange2String
                        self.f3kdbY2 = self.defaultF3kdbY2String
                        self.f3kdbCbCr2 = self.defaultF3kdbCbCr2String
                    }
                } else {
                    if self.isZero(self.debandStrength2) {
                        self.debandStrength2 = self.defaultDebandStrength2String
                    }
                }
            }
            .store(in: &cancellables)
        
        $grainStrength2
            .sink { [weak self] value in
                guard let self = self else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useGrain2 = false
                }
            }
            .store(in: &cancellables)
        
        $useGrain2
            .sink { [weak self] isOn in
                guard let self = self, isOn else { return }
                if self.isZero(self.grainStrength2) {
                    self.grainStrength2 = self.defaultGrainStrength2String
                }
            }
            .store(in: &cancellables)
    }
    // --- Codec & Rate ---
    @Published var useHEVC: Bool = false
    @Published var crf: Double = 16.0
    @Published var preset: String = "slow"
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
    @Published var eqContrast: String = "1.03"
    @Published var eqBrightness: String = "0.005"
    @Published var eqSaturation: String = "1.06"
    @Published var lutPath: String = ""

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
    @Published var regionMasksEnabled: Bool = false
    // DISABLED: Quality Analyzer defaulted off
    @Published var useQualityAnalyzer: Bool = false
    // DISABLED: Drift Guard defaulted off
    @Published var useDriftGuard: Bool = false
    @Published var pciSafe: Bool = false
    @Published var dryRun: Bool = false
    @Published var preview: Bool = false
    
    // Constants
    let presets = ["veryfast", "faster", "medium", "slow", "slower", "veryslow"]
    let interpolations = ["mci", "blend"]
    let scalers = ["ai", "lanczos", "zscale", "hw", "coreml"]
    let coremlModels = CoreMLModelRegistry.models
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
    // Stick to the builtin FFmpeg DNN backend that does not require external runtimes on macOS.
    let dnnBackends = ["native"]
    let deblockModes = ["weak", "strong"]
    let aiBackends = ["sr", "dnn"]
    let aiModelTypes = ["srcnn", "espcn", "edsr", "fsrcnn"]
    
    // MARK: - Helper methods to check if values are zero
    func isZero(_ value: String) -> Bool {
        guard let numValue = Double(value) else { return false }
        return numValue == 0
    }
    
    func isZeroOrEmpty(_ value: String) -> Bool {
        return value.isEmpty || value == "0" || isZero(value)
    }

    // Default fallbacks used when re-enabling filters that were auto-disabled at 0
    private var defaultDeringStrengthString: String { "0.5" }
    private var defaultDeblockThreshString: String { "0.5" }
    private var defaultDenoiseStrength2String: String { String(format: "%.2f", denoiseStrength2Default) }
    private var defaultSharpenStrength2String: String { "0.25" }
    private var defaultUsmRadius2String: String { "5" }
    private var defaultUsmAmount2String: String { "1.0" }
    private var defaultUsmThreshold2String: String { "0.03" }
    private var defaultDebandStrength2String: String { "0.015" }
    private var defaultF3kdbRange2String: String { "15" }
    private var defaultF3kdbY2String: String { "64" }
    private var defaultF3kdbCbCr2String: String { "64" }
    private var defaultGrainStrength2String: String { "1.0" }
    
    // MARK: - Denoiser-specific parameter ranges
    /**
     * Returns the valid range for denoise strength based on the selected denoiser.
     * Each denoiser has different valid ranges:
     * - bm3d: sigma 0-20 (or "auto")
     * - hqdn3d: luma_spatial 1.0-10.0
     * - nlmeans: strength 1.0-30.0
     * - atadenoise: threshold 1.0-20.0
     */
    var denoiseStrengthRange: ClosedRange<Double> {
        switch denoiser {
        case "bm3d":
            return 0...20.0
        case "hqdn3d":
            return 1.0...10.0
        case "nlmeans":
            return 1.0...30.0
        case "atadenoise":
            return 1.0...20.0
        default:
            return 0...20.0 // Safe default
        }
    }
    
    /**
     * Returns the default value for denoise strength based on the selected denoiser.
     */
    var denoiseStrengthDefault: Double {
        switch denoiser {
        case "bm3d":
            return 2.5
        case "hqdn3d":
            return 4.0
        case "nlmeans":
            return 1.0
        case "atadenoise":
            return 9.0
        default:
            return 2.5
        }
    }
    
    /**
     * Returns the step size for denoise strength based on the selected denoiser.
     */
    var denoiseStrengthStep: Double {
        switch denoiser {
        case "bm3d":
            return 0.1
        case "hqdn3d":
            return 0.1
        case "nlmeans":
            return 0.1
        case "atadenoise":
            return 0.1
        default:
            return 0.1
        }
    }
    
    /**
     * Same as above but for the second denoiser (denoiser2).
     */
    var denoiseStrength2Range: ClosedRange<Double> {
        switch denoiser2 {
        case "bm3d":
            return 0...20.0
        case "hqdn3d":
            return 1.0...10.0
        case "nlmeans":
            return 1.0...30.0
        case "atadenoise":
            return 1.0...20.0
        default:
            return 0...20.0
        }
    }
    
    var denoiseStrength2Default: Double {
        switch denoiser2 {
        case "bm3d":
            return 2.5
        case "hqdn3d":
            return 4.0
        case "nlmeans":
            return 1.0
        case "atadenoise":
            return 9.0
        default:
            return 2.5
        }
    }
    
    var denoiseStrength2Step: Double {
        switch denoiser2 {
        case "bm3d":
            return 0.1
        case "hqdn3d":
            return 0.1
        case "nlmeans":
            return 0.1
        case "atadenoise":
            return 0.1
        default:
            return 0.1
        }
    }
    
    /**
     * Validates and clamps denoise strength value to the appropriate range for the selected denoiser.
     * Returns the clamped value as a string.
     * For bm3d, "auto" is a valid value and will be preserved.
     */
    func validateDenoiseStrength(_ value: String, forDenoiser: String) -> String {
        // For bm3d, "auto" is a special valid value
        if forDenoiser == "bm3d" && value.lowercased() == "auto" {
            return "auto"
        }
        
        guard let numValue = Double(value) else {
            // If not a number and not "auto", return default for the denoiser
            return String(format: "%.2f", denoiseStrengthDefault)
        }
        
        let range: ClosedRange<Double>
        switch forDenoiser {
        case "bm3d":
            range = 0...20.0
        case "hqdn3d":
            range = 1.0...10.0
        case "nlmeans":
            range = 1.0...30.0
        case "atadenoise":
            range = 1.0...20.0
        default:
            range = 0...20.0
        }
        
        let clamped = max(range.lowerBound, min(range.upperBound, numValue))
        return String(format: "%.2f", clamped)
    }
    
    // MARK: - Sharpen-specific parameter ranges
    /**
     * CAS (Contrast Adaptive Sharpening) strength range: 0.0-1.0
     * Unsharp Mask: radius 3-23, amount -2.0-5.0, threshold 0.0-1.0
     */
    var sharpenStrengthRange: ClosedRange<Double> {
        switch sharpenMethod {
        case "cas":
            return 0.0...1.0
        case "unsharp":
            return -2.0...5.0  // Amount range
        default:
            return 0.0...1.0
        }
    }
    
    var sharpenStrengthDefault: Double {
        switch sharpenMethod {
        case "cas":
            return 0.25
        case "unsharp":
            return 1.0
        default:
            return 0.25
        }
    }
    
    var sharpenStrengthStep: Double {
        switch sharpenMethod {
        case "cas":
            return 0.005
        case "unsharp":
            return 0.01
        default:
            return 0.005
        }
    }
    
    // Unsharp Mask specific ranges
    var usmRadiusRange: ClosedRange<Double> { 3.0...12.0 }
    var usmRadiusDefault: Double { 5.0 }
    var usmRadiusStep: Double { 1.0 }
    
    var usmAmountRange: ClosedRange<Double> { -2.0...5.0 }
    var usmAmountDefault: Double { 1.0 }
    var usmAmountStep: Double { 0.01 }
    
    var usmThresholdRange: ClosedRange<Double> { 0.0...0.03 }
    var usmThresholdDefault: Double { 0.03 }
    var usmThresholdStep: Double { 0.001 }
    
    // Same for second set
    var sharpenStrength2Range: ClosedRange<Double> {
        switch sharpenMethod2 {
        case "cas":
            return 0.0...1.0
        case "unsharp":
            return -2.0...5.0
        default:
            return 0.0...1.0
        }
    }
    
    var sharpenStrength2Default: Double {
        switch sharpenMethod2 {
        case "cas":
            return 0.25
        case "unsharp":
            return 1.0
        default:
            return 0.25
        }
    }
    
    var sharpenStrength2Step: Double {
        switch sharpenMethod2 {
        case "cas":
            return 0.005
        case "unsharp":
            return 0.01
        default:
            return 0.005
        }
    }
    
    // MARK: - Deband-specific parameter ranges
    /**
     * deband: strength 0.0-0.1 (typical range)
     * gradfun: strength 0.0-0.1
     * f3kdb: range 1-32, y 16-512, cb/cr 16-512
     */
    var debandStrengthRange: ClosedRange<Double> {
        switch debandMethod {
        case "deband":
            return 0.0...0.1
        case "gradfun":
            return 0.0...0.1
        case "f3kdb":
            return 0.0...0.1  // Not used for f3kdb, but keep for compatibility
        default:
            return 0.0...0.1
        }
    }
    
    var debandStrengthDefault: Double {
        switch debandMethod {
        case "deband":
            return 0.015
        case "gradfun":
            return 0.015
        case "f3kdb":
            return 0.015
        default:
            return 0.015
        }
    }
    
    var debandStrengthStep: Double { 0.001 }
    
    // F3KDB specific ranges
    var f3kdbRangeRange: ClosedRange<Double> { 1.0...32.0 }
    var f3kdbRangeDefault: Double { 15.0 }
    var f3kdbRangeStep: Double { 1.0 }
    
    var f3kdbYRange: ClosedRange<Double> { 16.0...512.0 }
    var f3kdbYDefault: Double { 64.0 }
    var f3kdbYStep: Double { 1.0 }
    
    var f3kdbCbCrRange: ClosedRange<Double> { 16.0...512.0 }
    var f3kdbCbCrDefault: Double { 64.0 }
    var f3kdbCbCrStep: Double { 1.0 }
    
    // Same for second set
    var debandStrength2Range: ClosedRange<Double> {
        switch debandMethod2 {
        case "deband":
            return 0.0...0.1
        case "gradfun":
            return 0.0...0.1
        case "f3kdb":
            return 0.0...0.1
        default:
            return 0.0...0.1
        }
    }
    
    var debandStrength2Default: Double {
        switch debandMethod2 {
        case "deband":
            return 0.015
        case "gradfun":
            return 0.015
        case "f3kdb":
            return 0.015
        default:
            return 0.015
        }
    }
    
    var debandStrength2Step: Double { 0.001 }
    
    // MARK: - Dering-specific parameter ranges
    /**
     * Dering strength: 0.0-2.0 (typical range for hqdn3d dering)
     */
    var deringStrengthRange: ClosedRange<Double> { 0.0...2.0 }
    var deringStrengthDefault: Double { 0.5 }
    var deringStrengthStep: Double { 0.01 }
    
    var deringStrength2Range: ClosedRange<Double> { 0.0...2.0 }
    var deringStrength2Default: Double { 0.5 }
    var deringStrength2Step: Double { 0.01 }
    
    // MARK: - EQ-specific parameter ranges
    /**
     * Contrast: 0.5-2.0
     * Brightness: -0.1-0.1
     * Saturation: 0.0-2.0
     */
    var eqContrastRange: ClosedRange<Double> { 0.5...2.0 }
    var eqContrastDefault: Double { 1.03 }
    var eqContrastStep: Double { 0.005 }
    
    var eqBrightnessRange: ClosedRange<Double> { -0.1...0.1 }
    var eqBrightnessDefault: Double { 0.005 }
    var eqBrightnessStep: Double { 0.005 }
    
    var eqSaturationRange: ClosedRange<Double> { 0.0...2.0 }
    var eqSaturationDefault: Double { 1.06 }
    var eqSaturationStep: Double { 0.005 }
    
    // MARK: - Metal Pipeline Derived Values
    var colorExposureValue: Double { Double(colorExposure) ?? 1.0 }
    var toneMapExposureValue: Double { Double(toneMapExposure) ?? 1.0 }
    var encodeExposureValue: Double { Double(encodeExposure) ?? 1.0 }
    var gammaBlendWeightValue: Double { max(0.0, min(1.0, Double(gammaBlendWeight) ?? 0.0)) }
    var laplacianStrengthValue: Double { Double(laplacianStrength) ?? 0.15 }
    var dehaloStrengthValue: Double { Double(dehaloStrength) ?? 0.25 }
    var moireStrengthValue: Double { Double(moireStrength) ?? 0.2 }
    var temporalStrengthValue: Double { Double(temporalStrength) ?? 0.15 }
    var tileFeatherMarginValue: Int { Int(Double(tileFeatherMargin) ?? 0) }
    var maskFeatherRadiusValue: Double { Double(maskFeatherRadius) ?? 0.0 }
    var maskDilateRadiusValue: Double { Double(maskDilateRadius) ?? 0.0 }
    var maskErodeRadiusValue: Double { Double(maskErodeRadius) ?? 0.0 }
    
    // MARK: - Grain-specific parameter ranges
    /**
     * Grain strength: 0.0-10.0
     */
    var grainStrengthRange: ClosedRange<Double> { 0.0...10.0 }
    var grainStrengthDefault: Double { 1.0 }
    var grainStrengthStep: Double { 0.1 }
    
    var grainStrength2Range: ClosedRange<Double> { 0.0...10.0 }
    var grainStrength2Default: Double { 1.0 }
    var grainStrength2Step: Double { 0.1 }
    
    // MARK: - Validation functions
    func validateSharpenStrength(_ value: String) -> String {
        guard let numValue = Double(value) else {
            return String(format: "%.2f", sharpenStrengthDefault)
        }
        let clamped = max(sharpenStrengthRange.lowerBound, min(sharpenStrengthRange.upperBound, numValue))
        return String(format: "%.2f", clamped)
    }
    
    func validateDebandStrength(_ value: String) -> String {
        guard let numValue = Double(value) else {
            return String(format: "%.3f", debandStrengthDefault)
        }
        let clamped = max(debandStrengthRange.lowerBound, min(debandStrengthRange.upperBound, numValue))
        return String(format: "%.3f", clamped)
    }
    
    func validateDebandStrength2(_ value: String) -> String {
        guard let numValue = Double(value) else {
            return String(format: "%.3f", debandStrength2Default)
        }
        let clamped = max(debandStrength2Range.lowerBound, min(debandStrength2Range.upperBound, numValue))
        return String(format: "%.3f", clamped)
    }
    
    func validateSharpenStrength2(_ value: String) -> String {
        guard let numValue = Double(value) else {
            return String(format: "%.2f", sharpenStrength2Default)
        }
        let clamped = max(sharpenStrength2Range.lowerBound, min(sharpenStrength2Range.upperBound, numValue))
        return String(format: "%.2f", clamped)
    }
    
    // MARK: - Filter Stacking Orchestration
    // These computed properties provide attenuated values when multiple filters of the same type are active.
    // This prevents the cumulative effect from becoming excessive (e.g., unsharp + CAS causing extreme sharpening).
    
    /// Returns true if both first and second set have sharpening active
    var isSharpenStacked: Bool {
        !noSharpen && useSharpen2
    }
    
    /// Returns true if both first and second set have denoising active
    var isDenoiseStacked: Bool {
        !noDenoise && useDenoise2
    }
    
    /// Returns true if both first and second set have debanding active
    var isDebandStacked: Bool {
        !noDeband && useDeband2
    }
    
    /// Attenuation factor for second set sharpening based on what's being combined
    /// - unsharp + unsharp: heavy attenuation (0.35) - same filter stacking is very aggressive
    /// - unsharp + cas: moderate attenuation (0.5) - cross-filter stacking
    /// - cas + unsharp: moderate attenuation (0.5)
    /// - cas + cas: light attenuation (0.6) - CAS is gentler
    var sharpen2AttenuationFactor: Double {
        guard isSharpenStacked else { return 1.0 }
        
        let method1 = sharpenMethod
        let method2 = sharpenMethod2
        
        if method1 == "unsharp" && method2 == "unsharp" {
            return 0.35  // Heavy: double unsharp is very aggressive
        } else if method1 == "unsharp" || method2 == "unsharp" {
            return 0.5   // Moderate: unsharp combined with anything else
        } else {
            return 0.6   // Light: CAS + CAS is gentler
        }
    }
    
    /// Attenuation factor for second set denoising
    var denoise2AttenuationFactor: Double {
        guard isDenoiseStacked else { return 1.0 }
        
        // Double denoising can over-smooth, but it's less destructive than double sharpening
        // Use consistent moderate attenuation
        return 0.55
    }
    
    /// Attenuation factor for second set debanding
    var deband2AttenuationFactor: Double {
        guard isDebandStacked else { return 1.0 }
        return 0.6  // Debanding is gentler, light attenuation
    }
    
    // MARK: - Effective Values (what actually gets sent to FFmpeg)
    // These apply attenuation when filters are stacked
    
    /// Effective CAS strength for second set (attenuated when stacked)
    var effectiveSharpenStrength2: String {
        guard isSharpenStacked, sharpenMethod2 == "cas" else { return sharpenStrength2 }
        
        guard let value = Double(sharpenStrength2) else { return sharpenStrength2 }
        let attenuated = value * sharpen2AttenuationFactor
        return String(format: "%.3f", max(0, min(1.0, attenuated)))
    }
    
    /// Effective unsharp amount for second set (attenuated when stacked)
    var effectiveUsmAmount2: String {
        guard isSharpenStacked, sharpenMethod2 == "unsharp" else { return usmAmount2 }
        
        guard let value = Double(usmAmount2) else { return usmAmount2 }
        let attenuated = value * sharpen2AttenuationFactor
        // Clamp to valid range for unsharp amount (-2.0 to 5.0)
        return String(format: "%.2f", max(-2.0, min(5.0, attenuated)))
    }
    
    /// Effective unsharp radius for second set (slightly reduced when stacked to prevent halo artifacts)
    var effectiveUsmRadius2: String {
        guard isSharpenStacked, sharpenMethod2 == "unsharp" else { return usmRadius2 }
        
        guard let value = Double(usmRadius2) else { return usmRadius2 }
        // Reduce radius slightly to prevent excessive halo when stacking
        let attenuated = value * (sharpen2AttenuationFactor + 0.2)  // Less aggressive on radius
        // Clamp to valid range (3-23)
        return String(format: "%.0f", max(3, min(23, attenuated)))
    }
    
    /// Effective denoise strength for second set (attenuated when stacked)
    var effectiveDenoiseStrength2: String {
        guard isDenoiseStacked else { return denoiseStrength2 }
        
        // Handle "auto" specially
        if denoiseStrength2.lowercased() == "auto" { return "auto" }
        
        guard let value = Double(denoiseStrength2) else { return denoiseStrength2 }
        let attenuated = value * denoise2AttenuationFactor
        return String(format: "%.2f", max(0, attenuated))
    }
    
    /// Effective deband strength for second set (attenuated when stacked)
    var effectiveDebandStrength2: String {
        guard isDebandStacked else { return debandStrength2 }
        
        guard let value = Double(debandStrength2) else { return debandStrength2 }
        let attenuated = value * deband2AttenuationFactor
        return String(format: "%.4f", max(0, attenuated))
    }
    
    /// Effective f3kdb Y for second set (attenuated when stacked)
    var effectiveF3kdbY2: String {
        guard isDebandStacked, debandMethod2 == "f3kdb" else { return f3kdbY2 }
        
        guard let value = Double(f3kdbY2) else { return f3kdbY2 }
        let attenuated = value * deband2AttenuationFactor
        return String(format: "%.0f", max(16, min(512, attenuated)))
    }
    
    /// Effective f3kdb CbCr for second set (attenuated when stacked)
    var effectiveF3kdbCbCr2: String {
        guard isDebandStacked, debandMethod2 == "f3kdb" else { return f3kdbCbCr2 }
        
        guard let value = Double(f3kdbCbCr2) else { return f3kdbCbCr2 }
        let attenuated = value * deband2AttenuationFactor
        return String(format: "%.0f", max(16, min(512, attenuated)))
    }
    
    // MARK: - Warning Messages for UI
    
    /// Returns a warning message if filter stacking might cause quality issues
    var filterStackingWarning: String? {
        var warnings: [String] = []
        
        if isSharpenStacked {
            let factor = Int((1.0 - sharpen2AttenuationFactor) * 100)
            warnings.append("⚡ Sharpening stacked: 2nd set reduced by \(factor)%")
        }
        if isDenoiseStacked {
            let factor = Int((1.0 - denoise2AttenuationFactor) * 100)
            warnings.append("🔇 Denoise stacked: 2nd set reduced by \(factor)%")
        }
        if isDebandStacked {
            let factor = Int((1.0 - deband2AttenuationFactor) * 100)
            warnings.append("📊 Deband stacked: 2nd set reduced by \(factor)%")
        }
        
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }
    
    /// Returns true if any filter stacking is occurring
    var hasFilterStacking: Bool {
        isSharpenStacked || isDenoiseStacked || isDebandStacked
    }
    
    // MARK: - Reset to Defaults
    /// Resets all settings to their default values
    func resetToDefaults() {
        // Codec & Rate
        useHEVC = false
        crf = 16.0
        preset = "slow"
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
        eqContrast = "1.03"
        eqBrightness = "0.005"
        eqSaturation = "1.06"
        lutPath = ""
        
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
        // DISABLED: keep advanced features off during resets
        regionMasksEnabled = false
        useQualityAnalyzer = false
        useDriftGuard = false
        pciSafe = false
        dryRun = false
        preview = false
    }
}
