import Foundation

/// Derives second-pass attenuation from the authoritative first/second-pass
/// settings. Both export option construction and UI warnings use these values.
nonisolated extension UpscaleSettings {
    // MARK: - Filter Stacking Orchestration
    // These computed properties provide attenuated values when multiple filters of the same type are active.
    // These are fixed heuristics, not image analysis or a quality guarantee.

    /// Returns true if both first and second set have sharpening active
    var isSharpenStacked: Bool {
        scaler != "coreml" && !noSharpen && useSharpen2 && (sharpenMethod == "cas" ? (Double(sharpenStrength) ?? 0) > 0 : (Double(usmAmount) ?? 0) != 0)
    }

    /// Returns true if both first and second set have denoising active
    var isDenoiseStacked: Bool {
        scaler != "coreml" && !noDenoise && useDenoise2 && denoiseStrength2.lowercased() != "auto"
    }

    /// Returns true if both first and second set have debanding active
    var isDebandStacked: Bool {
        scaler != "coreml" && !noDeband && useDeband2
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

        guard let value = Double(usmRadius2), value.isFinite else { return "3" }
        // Reduce radius slightly to prevent excessive halo when stacking
        let attenuated = max(3, min(23, value * (sharpen2AttenuationFactor + 0.2)))  // Less aggressive on radius
        // Clamp to valid range (3-23)
        let oddSize = 2 * Int((attenuated - 1) / 2) + 1
        return String(max(3, min(23, oddSize)))
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
        return String(format: "%.4f", max(debandMethod2 == "gradfun" ? 0.51 : 0, attenuated))
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

}
