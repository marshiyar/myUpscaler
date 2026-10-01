import Foundation

/// Derives second-pass attenuation from the authoritative first/second-pass
/// settings. Both export option construction and UI warnings use these values.
extension UpscaleSettings {
    // MARK: - Filter Stacking Orchestration
    // These computed properties provide attenuated values when multiple filters of the same type are active.
    // These are fixed heuristics, not image analysis or a quality guarantee.

    /// Returns true if both first and second set have sharpening active
    var isSharpenStacked: Bool {
        upscaling.scaler != "coreml" && primary.useSharpen && secondary.useSharpen && (primary.sharpenMethod == "cas" ? (Double(primary.sharpenStrength.text) ?? 0) > 0 : (Double(primary.usmAmount.text) ?? 0) != 0)
    }

    /// Returns true if both first and second set have denoising active
    var isDenoiseStacked: Bool {
        upscaling.scaler != "coreml" && primary.useDenoise && secondary.useDenoise && secondary.denoiseStrength.text.lowercased() != "auto"
    }

    /// Returns true if both first and second set have debanding active
    var isDebandStacked: Bool {
        upscaling.scaler != "coreml" && primary.useDeband && secondary.useDeband
    }

    /// Attenuation factor for second set sharpening based on what's being combined
    /// - unsharp + unsharp: heavy attenuation (0.35) - same filter stacking is very aggressive
    /// - unsharp + cas: moderate attenuation (0.5) - cross-filter stacking
    /// - cas + unsharp: moderate attenuation (0.5)
    /// - cas + cas: light attenuation (0.6) - CAS is gentler
    var sharpen2AttenuationFactor: Double {
        guard isSharpenStacked else { return 1.0 }

        let method1 = primary.sharpenMethod
        let method2 = secondary.sharpenMethod

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
        guard isSharpenStacked, secondary.sharpenMethod == "cas" else { return secondary.sharpenStrength.text }

        guard let value = Double(secondary.sharpenStrength.text) else { return secondary.sharpenStrength.text }
        let attenuated = value * sharpen2AttenuationFactor
        return String(format: "%.3f", max(0, min(1.0, attenuated)))
    }

    /// Effective unsharp amount for second set (attenuated when stacked)
    var effectiveUsmAmount2: String {
        guard isSharpenStacked, secondary.sharpenMethod == "unsharp" else { return secondary.usmAmount.text }

        guard let value = Double(secondary.usmAmount.text) else { return secondary.usmAmount.text }
        let attenuated = value * sharpen2AttenuationFactor
        // Clamp to valid range for unsharp amount (-2.0 to 5.0)
        return String(format: "%.2f", max(-2.0, min(5.0, attenuated)))
    }

    /// Effective unsharp radius for second set (slightly reduced when stacked to prevent halo artifacts)
    var effectiveUsmRadius2: String {
        guard isSharpenStacked, secondary.sharpenMethod == "unsharp" else { return String(Int(Self.unsharpMatrixSize(secondary.usmRadius.text))) }

        guard let value = Double(secondary.usmRadius.text), value.isFinite else { return "3" }
        // Reduce radius slightly to prevent excessive halo when stacking
        let attenuated = max(3, min(23, value * (sharpen2AttenuationFactor + 0.2)))  // Less aggressive on radius
        // Clamp to valid range (3-23)
        return String(Int(Self.unsharpMatrixSize(String(attenuated))))
    }

    /// Effective denoise strength for second set (attenuated when stacked)
    var effectiveDenoiseStrength2: String {
        guard isDenoiseStacked else { return secondary.denoiseStrength.text }

        // Handle "auto" specially
        if secondary.denoiseStrength.text.lowercased() == "auto" { return "auto" }

        guard let value = Double(secondary.denoiseStrength.text) else { return secondary.denoiseStrength.text }
        let attenuated = value * denoise2AttenuationFactor
        return String(format: "%.2f", max(0, attenuated))
    }

    /// Effective deband strength for second set (attenuated when stacked)
    var effectiveDebandStrength2: String {
        guard isDebandStacked else { return secondary.debandStrength.text }

        guard let value = Double(secondary.debandStrength.text) else { return secondary.debandStrength.text }
        let attenuated = value * deband2AttenuationFactor
        return String(format: "%.4f", max(secondary.debandMethod == "gradfun" ? 0.51 : 0, attenuated))
    }

    /// Effective f3kdb Y for second set (attenuated when stacked)
    var effectiveF3kdbY2: String {
        guard isDebandStacked, secondary.debandMethod == "f3kdb" else { return secondary.f3kdbY.text }

        guard let value = Double(secondary.f3kdbY.text) else { return secondary.f3kdbY.text }
        let attenuated = value * deband2AttenuationFactor
        return String(format: "%.0f", max(16, min(512, attenuated)))
    }

    /// Effective f3kdb CbCr for second set (attenuated when stacked)
    var effectiveF3kdbCbCr2: String {
        guard isDebandStacked, secondary.debandMethod == "f3kdb" else { return secondary.f3kdbCbCr.text }

        guard let value = Double(secondary.f3kdbCbCr.text) else { return secondary.f3kdbCbCr.text }
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

}
