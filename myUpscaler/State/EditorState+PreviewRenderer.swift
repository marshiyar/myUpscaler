import AppKit
import CoreImage

// Immutable render input; worker code never reads observable editor state.
    nonisolated struct PreviewFilterParameters: Hashable {
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

nonisolated enum PreviewRenderer {
    // Non-isolated helper for background processing
    static func render(_ image: NSImage, params: PreviewFilterParameters, context: CIContext) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        var ci = CIImage(cgImage: cg)

        // MARK: -  ===== FIRST SET =====

        // ----- Denoise (1st) -----
        if !params.noDenoise && params.denoiseStrength > 0,
           let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(params.denoiseStrength / 20.0, forKey: "inputNoiseLevel")
            ci = f.outputImage ?? ci
        }

        // ----- Dering (1st) -----
        if params.deringActive,
           let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(params.deringStrength * 0.1, forKey: "inputNoiseLevel")
            ci = f.outputImage ?? ci
        }

        // ----- Color -----
        if !params.noEq, let f = CIFilter(name: "CIColorControls") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(params.contrast, forKey: kCIInputContrastKey)
            f.setValue(params.brightness, forKey: kCIInputBrightnessKey)
            f.setValue(params.saturation, forKey: kCIInputSaturationKey)
            ci = f.outputImage ?? ci
        }

        // ----- Sharpen (1st) -----
        if !params.noSharpen && params.sharpenMethod == "cas" {
            if let f = CIFilter(name: "CIUnsharpMask") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(2.5, forKey: kCIInputRadiusKey)
                f.setValue(params.sharpenStrength, forKey: kCIInputIntensityKey)
                ci = f.outputImage ?? ci
            }
        } else if !params.noSharpen {
            if let f = CIFilter(name: "CIUnsharpMask") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(params.usmRadius, forKey: kCIInputRadiusKey)
                f.setValue(params.usmAmount, forKey: kCIInputIntensityKey)
                ci = f.outputImage ?? ci
            }
        }


        // MARK: - SECOND SET (applies after first set)

        // ----- Denoise (2nd) -----
        if !params.noDenoise && params.useDenoise2 && params.denoiseStrength2 > 0,
           let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(ci, forKey: kCIInputImageKey)
            // Apply attenuation if both sets have denoise active (stacking)
            let attenuationFactor = !params.noDenoise && params.denoiseStrength > 0 ? 0.55 : 1.0
            f.setValue((params.denoiseStrength2 * attenuationFactor) / 20.0, forKey: "inputNoiseLevel")
            ci = f.outputImage ?? ci
        }

        // ----- Dering (2nd) -----
        if params.useDering2 && params.deringActive2,
           let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(params.deringStrength2 * 0.1, forKey: "inputNoiseLevel")
            ci = f.outputImage ?? ci
        }

        // ----- Sharpen (2nd) -----
        if !params.noSharpen && params.useSharpen2 {
            // Calculate attenuation factor based on first set sharpen being active
            let firstSetSharpenActive = !params.noSharpen && (params.sharpenMethod == "cas" ? params.sharpenStrength > 0 : params.usmAmount > 0)
            var attenuationFactor: Double = 1.0
            if firstSetSharpenActive {
                // Determine attenuation based on what's being stacked
                if params.sharpenMethod == "unsharp" && params.sharpenMethod2 == "unsharp" {
                    attenuationFactor = 0.35  // Heavy attenuation for double unsharp
                } else if params.sharpenMethod == "unsharp" || params.sharpenMethod2 == "unsharp" {
                    attenuationFactor = 0.5   // Moderate for mixed
                } else {
                    attenuationFactor = 0.6   // Light for CAS + CAS
                }
            }

            if params.sharpenMethod2 == "cas" {
                if let f = CIFilter(name: "CIUnsharpMask") {
                    f.setValue(ci, forKey: kCIInputImageKey)
                    f.setValue(2.5, forKey: kCIInputRadiusKey)
                    f.setValue(params.sharpenStrength2 * attenuationFactor, forKey: kCIInputIntensityKey)
                    ci = f.outputImage ?? ci
                }
            } else {
                if let f = CIFilter(name: "CIUnsharpMask") {
                    f.setValue(ci, forKey: kCIInputImageKey)
                    let radiusAttenuation = attenuationFactor + 0.2  // Less aggressive on radius
                    f.setValue(params.usmRadius2 * radiusAttenuation, forKey: kCIInputRadiusKey)
                    f.setValue(params.usmAmount2 * attenuationFactor, forKey: kCIInputIntensityKey)
                    ci = f.outputImage ?? ci
                }
            }
        }

        guard let out = context.createCGImage(ci, from: ci.extent) else { return image }
        return NSImage(cgImage: out, size: .zero)
    }


}
