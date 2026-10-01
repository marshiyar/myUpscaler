    nonisolated struct PreviewFilterParameters: Hashable, Sendable {
        // First set
        let noDenoise: Bool
        let noSharpen: Bool
        let noEq: Bool
        let contrast: Double
        let brightness: Double
        let saturation: Double
        let denoiseStrength: Double
        let deringActive: Bool
        let deringStrength: Double
        let sharpenMethod: String
        let sharpenStrength: Double
        let usmRadius: Double
        let usmAmount: Double
        let usmThreshold: Double
        // Second set
        let useDenoise2: Bool
        let denoiseStrength2: Double
        let useDering2: Bool
        let deringActive2: Bool
        let deringStrength2: Double
        let useSharpen2: Bool
        let sharpenMethod2: String
        let sharpenStrength2: Double
        let usmRadius2: Double
        let usmAmount2: Double
        let usmThreshold2: Double
    }

import Foundation

extension UpscaleSettings {
    /// Immutable, effective inputs. Inactive values have canonical identities so
    /// editing an unused field does not invalidate a modes.preview.
    func makePreviewFilterParameters() -> PreviewFilterParameters {
        let primaryDenoise = primary.useDenoise
        let primarySharpen = primary.useSharpen
        let primaryUnsharp = primarySharpen && primary.sharpenMethod == "unsharp"
        let supportsSecondStage = upscaling.scaler != "coreml"
        let secondSharpen = supportsSecondStage && secondary.useSharpen
        let secondUnsharp = secondSharpen && secondary.sharpenMethod == "unsharp"
        let secondDering = supportsSecondStage && secondary.useDering
        return PreviewFilterParameters(
            noDenoise: !primaryDenoise, noSharpen: !primarySharpen, noEq: color.noEq,
            contrast: color.noEq ? 1 : finite(color.eqContrast.text, fallback: 1),
            brightness: color.noEq ? 0 : finite(color.eqBrightness.text, fallback: 0),
            saturation: color.noEq ? 1 : finite(color.eqSaturation.text, fallback: 1),
            denoiseStrength: primaryDenoise ? finite(primary.denoiseStrength.text, fallback: 0) : 0,
            deringActive: primary.useDering, deringStrength: primary.useDering ? finite(primary.deringStrength.text, fallback: 0) : 0,
            sharpenMethod: primarySharpen ? primary.sharpenMethod : "cas",
            sharpenStrength: primarySharpen && !primaryUnsharp ? finite(primary.sharpenStrength.text, fallback: 0) : 0,
            usmRadius: primaryUnsharp ? Self.unsharpMatrixSize(primary.usmRadius.text) : 0,
            usmAmount: primaryUnsharp ? finite(primary.usmAmount.text, fallback: 0) : 0, usmThreshold: 0,
            useDenoise2: supportsSecondStage && secondary.useDenoise,
            denoiseStrength2: supportsSecondStage && secondary.useDenoise ? finite(effectiveDenoiseStrength2, fallback: 0) : 0,
            useDering2: secondDering, deringActive2: secondDering,
            deringStrength2: secondDering ? finite(secondary.deringStrength.text, fallback: 0) : 0,
            useSharpen2: secondSharpen, sharpenMethod2: secondSharpen ? secondary.sharpenMethod : "cas",
            sharpenStrength2: secondSharpen && !secondUnsharp ? finite(effectiveSharpenStrength2, fallback: 0) : 0,
            usmRadius2: secondUnsharp ? Self.unsharpMatrixSize(effectiveUsmRadius2) : 0,
            usmAmount2: secondUnsharp ? finite(effectiveUsmAmount2, fallback: 0) : 0, usmThreshold2: 0)
    }
    private func finite(_ text: String, fallback: Double) -> Double {
        NumericDraft(text: text).finiteValue ?? fallback
    }
}
