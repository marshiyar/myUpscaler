import Foundation

/// Parameter ranges, validation and native pipeline conversions share the same
/// rules for UI controls, presets and render snapshots.
extension UpscaleSettings {
    /// Unsharp takes an odd matrix size from 3 through 23.
    nonisolated static func unsharpMatrixSize(_ text: String) -> Double {
        guard let value = Double(text), value.isFinite else { return 3 }
        let bounded = max(3, min(23, value))
        return Double(2 * Int((bounded - 1) / 2) + 1)
    }

    // MARK: - Helper methods to check if values are zero
    func isZero(_ value: String) -> Bool {
        guard let numValue = Double(value) else { return false }
        return numValue == 0
    }

    func isZeroOrEmpty(_ value: String) -> Bool {
        return value.isEmpty || value == "0" || isZero(value)
    }

    // MARK: - Default fallbacks used when re-enabling filters that were auto-disabled at 0
     var defaultDeringStrengthString: String { RestorationStage().deringStrength.text }
     var defaultDeblockThreshString: String { "" }
     var defaultDenoiseStrength2String: String { String(format: "%.2f", denoiseStrength2Default) }
     var defaultSharpenStrength2String: String { RestorationStage().sharpenStrength.text }
     var defaultUsmRadius2String: String { RestorationStage().usmRadius.text }
     var defaultUsmAmount2String: String { RestorationStage().usmAmount.text }
     var defaultUsmThreshold2String: String { RestorationStage().usmThreshold.text }
     var defaultDebandStrength2String: String { RestorationStage().debandStrength.text }
     var defaultF3kdbRange2String: String { RestorationStage().f3kdbRange.text }
     var defaultF3kdbY2String: String { RestorationStage().f3kdbY.text }
     var defaultF3kdbCbCr2String: String { RestorationStage().f3kdbCbCr.text }
     var defaultGrainStrength2String: String { RestorationStage().grainStrength.text }

    // MARK: - Denoiser-specific parameter ranges
    /**
     * Returns the valid range for denoise strength based on the selected primary.denoiser.
     * Each primary.denoiser has different valid ranges:
     * - bm3d: sigma 0-20 (or "auto")
     * - hqdn3d: luma_spatial 1.0-10.0
     * - nlmeans: strength 1.0-30.0
     * - atadenoise: threshold 1.0-20.0
     */
    var denoiseStrengthRange: ClosedRange<Double> {
        switch primary.denoiser {
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
     * Returns the default value for denoise strength based on the selected primary.denoiser.
     */
    var denoiseStrengthDefault: Double {
        switch primary.denoiser {
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
     * Returns the step size for denoise strength based on the selected primary.denoiser.
     */
    var denoiseStrengthStep: Double {
        switch primary.denoiser {
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
     * Same as above but for the second primary.denoiser (secondary.denoiser).
     */
    var denoiseStrength2Range: ClosedRange<Double> {
        switch secondary.denoiser {
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
        switch secondary.denoiser {
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
        switch secondary.denoiser {
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

    func validateDenoiseStrength(_ value: String, forDenoiser: String) -> String {
        // For bm3d, "auto" is a special valid value
        if forDenoiser == "bm3d" && value.lowercased() == "auto" {
            return "auto"
        }

        guard let numValue = Double(value) else {
            // If not a number and not "auto", return default for the primary.denoiser
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
        switch primary.sharpenMethod {
        case "cas":
            return 0.0...1.0
        case "unsharp":
            return -2.0...5.0  // Amount range
        default:
            return 0.0...1.0
        }
    }

    var sharpenStrengthDefault: Double {
        switch primary.sharpenMethod {
        case "cas":
            return 0.25
        case "unsharp":
            return 1.0
        default:
            return 0.25
        }
    }

    var sharpenStrengthStep: Double {
        switch primary.sharpenMethod {
        case "cas":
            return 0.005
        case "unsharp":
            return 0.01
        default:
            return 0.005
        }
    }

    // Unsharp Mask specific ranges
    var usmRadiusRange: ClosedRange<Double> { 3.0...23.0 }
    var usmRadiusDefault: Double { 5.0 }
    var usmRadiusStep: Double { 1.0 }

    var usmAmountRange: ClosedRange<Double> { -2.0...5.0 }
    var usmAmountDefault: Double { 1.0 }
    var usmAmountStep: Double { 0.01 }

    var usmThresholdRange: ClosedRange<Double> { 0.0...1.0 }
    var usmThresholdDefault: Double { 0.03 }
    var usmThresholdStep: Double { 0.001 }

    // Same for second set
    var sharpenStrength2Range: ClosedRange<Double> {
        switch secondary.sharpenMethod {
        case "cas":
            return 0.0...1.0
        case "unsharp":
            return -2.0...5.0
        default:
            return 0.0...1.0
        }
    }

    var sharpenStrength2Default: Double {
        switch secondary.sharpenMethod {
        case "cas":
            return 0.25
        case "unsharp":
            return 1.0
        default:
            return 0.25
        }
    }

    var sharpenStrength2Step: Double {
        switch secondary.sharpenMethod {
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
     * gradfun: strength 0.51-64
     * f3kdb: range 1-32, y 16-512, cb/cr 16-512
     */
    var debandStrengthRange: ClosedRange<Double> {
        switch primary.debandMethod {
        case "deband":
            return 0.0...0.1
        case "gradfun":
            return 0.51...64
        case "f3kdb":
            return 0.0...0.1  // Not used for f3kdb, but keep for compatibility
        default:
            return 0.0...0.1
        }
    }

    var debandStrengthDefault: Double {
        switch primary.debandMethod {
        case "deband":
            return 0.015
        case "gradfun":
            return 1.2
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
        switch secondary.debandMethod {
        case "deband":
            return 0.0...0.1
        case "gradfun":
            return 0.51...64
        case "f3kdb":
            return 0.0...0.1
        default:
            return 0.0...0.1
        }
    }

    var debandStrength2Default: Double {
        switch secondary.debandMethod {
        case "deband":
            return 0.015
        case "gradfun":
            return 1.2
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
    var eqContrastDefault: Double { 1.0 }
    var eqContrastStep: Double { 0.005 }

    var eqBrightnessRange: ClosedRange<Double> { -0.1...0.1 }
    var eqBrightnessDefault: Double { 0.0 }
    var eqBrightnessStep: Double { 0.005 }

    var eqSaturationRange: ClosedRange<Double> { 0.0...2.0 }
    var eqSaturationDefault: Double { 1.0 }
    var eqSaturationStep: Double { 0.005 }

    // MARK: - Metal Pipeline Derived Values
    var colorExposureValue: Double { Double(metal.colorExposure.text) ?? 1.0 }
    var toneMapExposureValue: Double { Double(metal.toneMapExposure.text) ?? 1.0 }
    var encodeExposureValue: Double { Double(metal.encodeExposure.text) ?? 1.0 }
    var gammaBlendWeightValue: Double { max(0.0, min(1.0, Double(metal.gammaBlendWeight.text) ?? 0.0)) }
    var laplacianStrengthValue: Double { Double(metal.laplacianStrength.text) ?? 0.15 }
    var dehaloStrengthValue: Double { Double(metal.dehaloStrength.text) ?? 0.25 }
    var moireStrengthValue: Double { Double(metal.moireStrength.text) ?? 0.2 }
    var temporalStrengthValue: Double { Double(metal.temporalStrength.text) ?? 0.15 }
    var tileFeatherMarginValue: Int { Int(Double(metal.tileFeatherMargin.text) ?? 0) }
    var maskFeatherRadiusValue: Double { Double(metal.maskFeatherRadius.text) ?? 0.0 }
    var maskDilateRadiusValue: Double { Double(metal.maskDilateRadius.text) ?? 0.0 }
    var maskErodeRadiusValue: Double { Double(metal.maskErodeRadius.text) ?? 0.0 }

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
    func validateSharpenStrength(_ value: String, method: String? = nil) -> String {
        let method = method ?? primary.sharpenMethod
        let defaultValue = method == "unsharp" ? 1.0 : 0.25
        let range: ClosedRange<Double> = method == "unsharp" ? -2.0...5.0 : 0.0...1.0
        guard let numValue = Double(value) else {
            return String(format: "%.2f", defaultValue)
        }
        let clamped = max(range.lowerBound, min(range.upperBound, numValue))
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

    func validateSharpenStrength2(_ value: String, method: String? = nil) -> String {
        let method = method ?? secondary.sharpenMethod
        let defaultValue = method == "unsharp" ? 1.0 : 0.25
        let range: ClosedRange<Double> = method == "unsharp" ? -2.0...5.0 : 0.0...1.0
        guard let numValue = Double(value) else {
            return String(format: "%.2f", defaultValue)
        }
        let clamped = max(range.lowerBound, min(range.upperBound, numValue))
        return String(format: "%.2f", clamped)
    }

}
