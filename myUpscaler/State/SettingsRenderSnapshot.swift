import Foundation

/// Pure rendering values read from one frozen configuration, without UI publications.
nonisolated extension SettingsConfiguration {
    var colorExposureValue: Double { metal.colorExposure.finiteValue ?? 1 }
    var toneMapExposureValue: Double { metal.toneMapExposure.finiteValue ?? 1 }
    var encodeExposureValue: Double { metal.encodeExposure.finiteValue ?? 1 }
    var gammaBlendWeightValue: Double { max(0, min(1, metal.gammaBlendWeight.finiteValue ?? 0)) }
    var laplacianStrengthValue: Double { metal.laplacianStrength.finiteValue ?? 0.15 }
    var dehaloStrengthValue: Double { metal.dehaloStrength.finiteValue ?? 0.25 }
    var moireStrengthValue: Double { metal.moireStrength.finiteValue ?? 0.2 }
    var temporalStrengthValue: Double { metal.temporalStrength.finiteValue ?? 0.15 }
    var tileFeatherMarginValue: Int {
        let value = metal.tileFeatherMargin.finiteValue ?? 0
        return value >= Double(Int.min) && value < Double(Int.max) ? Int(value) : 0
    }
    var maskFeatherRadiusValue: Double { metal.maskFeatherRadius.finiteValue ?? 0 }
    var maskDilateRadiusValue: Double { metal.maskDilateRadius.finiteValue ?? 0 }
    var maskErodeRadiusValue: Double { metal.maskErodeRadius.finiteValue ?? 0 }
}
