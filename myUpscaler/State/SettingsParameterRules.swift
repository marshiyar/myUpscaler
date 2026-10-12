import Foundation

/// Parameter ranges, validation and native pipeline conversions share the same
/// rules for UI controls, presets and render snapshots.
nonisolated extension UpscaleSettings {
    // MARK: - Helper methods to check if values are zero
    func isZero(_ value: String) -> Bool {
        guard let numValue = Double(value) else { return false }
        return numValue == 0
    }

    func isZeroOrEmpty(_ value: String) -> Bool {
        return value.isEmpty || value == "0" || isZero(value)
    }

    // MARK: - Default fallbacks used when re-enabling filters that were auto-disabled at 0
     var defaultDeringStrengthString: String { "0.5" }
     var defaultDeblockThreshString: String { "0.5" }
     var defaultDenoiseStrength2String: String { String(format: "%.2f", denoiseStrength2Default) }
     var defaultSharpenStrength2String: String { "0.25" }
     var defaultUsmRadius2String: String { "5" }
     var defaultUsmAmount2String: String { "1.0" }
     var defaultUsmThreshold2String: String { "0.03" }
     var defaultDebandStrength2String: String { "0.015" }
     var defaultF3kdbRange2String: String { "15" }
     var defaultF3kdbY2String: String { "64" }
     var defaultF3kdbCbCr2String: String { "64" }
     var defaultGrainStrength2String: String { "1.0" }

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
    var eqContrastDefault: Double { 1.0 }
    var eqContrastStep: Double { 0.005 }

    var eqBrightnessRange: ClosedRange<Double> { -0.1...0.1 }
    var eqBrightnessDefault: Double { 0.0 }
    var eqBrightnessStep: Double { 0.005 }

    var eqSaturationRange: ClosedRange<Double> { 0.0...2.0 }
    var eqSaturationDefault: Double { 1.0 }
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
    func validateSharpenStrength(_ value: String, method: String? = nil) -> String {
        let method = method ?? sharpenMethod
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
        let method = method ?? sharpenMethod2
        let defaultValue = method == "unsharp" ? 1.0 : 0.25
        let range: ClosedRange<Double> = method == "unsharp" ? -2.0...5.0 : 0.0...1.0
        guard let numValue = Double(value) else {
            return String(format: "%.2f", defaultValue)
        }
        let clamped = max(range.lowerBound, min(range.upperBound, numValue))
        return String(format: "%.2f", clamped)
    }

}
