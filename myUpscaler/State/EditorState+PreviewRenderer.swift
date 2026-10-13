import AppKit
import CoreImage

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
        if params.useDenoise2 && params.denoiseStrength2 > 0,
           let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(params.denoiseStrength2 / 20.0, forKey: "inputNoiseLevel")
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
        if params.useSharpen2 {
            if params.sharpenMethod2 == "cas" {
                if let f = CIFilter(name: "CIUnsharpMask") {
                    f.setValue(ci, forKey: kCIInputImageKey)
                    f.setValue(2.5, forKey: kCIInputRadiusKey)
                    f.setValue(params.sharpenStrength2, forKey: kCIInputIntensityKey)
                    ci = f.outputImage ?? ci
                }
            } else {
                if let f = CIFilter(name: "CIUnsharpMask") {
                    f.setValue(ci, forKey: kCIInputImageKey)
                    f.setValue(params.usmRadius2, forKey: kCIInputRadiusKey)
                    f.setValue(params.usmAmount2, forKey: kCIInputIntensityKey)
                    ci = f.outputImage ?? ci
                }
            }
        }

        guard let out = context.createCGImage(ci, from: ci.extent) else { return image }
        return NSImage(cgImage: out, size: .zero)
    }


}
