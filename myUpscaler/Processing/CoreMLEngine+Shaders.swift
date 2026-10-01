import Foundation
import CoreImage
import CoreGraphics
import CoreVideo

// MARK: - CoreML Engine Shader Extension

nonisolated extension CoreMLProcessingJob {

    /// Manages the custom Metal kernels for video restoration
    /// Loaded once, then immutable. Core Image kernels are SDK-declared Sendable.
    final class ShaderRegistry: Sendable {
        static let shared = ShaderRegistry()
        private let kernels: [String: CIKernel]
        var casKernel: CIKernel? { kernels["cas_sharpen"] }
        var debandKernel: CIKernel? { kernels["deband_dither"] }
        var bilateralKernel: CIKernel? { kernels["bilateral_denoise"] }
        var driftGuardKernel: CIKernel? { kernels["drift_guard"] }
        var linearizeKernel: CIKernel? { kernels["linearize_srgb"] }
        var encodeSrgbKernel: CIKernel? { kernels["encode_srgb"] }
        var toneMapKernel: CIKernel? { kernels["tone_map_reinhard"] }
        var gammaBlendKernel: CIKernel? { kernels["gamma_correct_blend"] }
        var unsharpKernel: CIKernel? { kernels["unsharp_mask"] }
        var laplacianKernel: CIKernel? { kernels["laplacian_sharpen"] }
        var medianKernel: CIKernel? { kernels["median_denoise"] }
        var blueNoiseDebandKernel: CIKernel? { kernels["blue_noise_deband"] }
        var dehaloKernel: CIKernel? { kernels["dehalo"] }
        var moireKernel: CIKernel? { kernels["moire_suppress"] }
        var premultiplyKernel: CIKernel? { kernels["premultiply_alpha"] }
        var unpremultiplyKernel: CIKernel? { kernels["unpremultiply_alpha"] }
        var maskFeatherKernel: CIKernel? { kernels["mask_feather"] }
        var maskDilateKernel: CIKernel? { kernels["mask_dilate"] }
        var maskErodeKernel: CIKernel? { kernels["mask_erode"] }
        var hannFeatherKernel: CIKernel? { kernels["hann_feather_tile"] }
        var temporalSmoothKernel: CIKernel? { kernels["temporal_smooth"] }

        private init() { kernels = Self.loadKernels() }

        private static func loadKernels() -> [String: CIKernel] {
            var result: [String: CIKernel] = [:]
            let names = [
                "cas_sharpen",
                "deband_dither",
                "bilateral_denoise",
                "drift_guard",
                "linearize_srgb",
                "encode_srgb",
                "tone_map_reinhard",
                "gamma_correct_blend",
                "unsharp_mask",
                "laplacian_sharpen",
                "median_denoise",
                "blue_noise_deband",
                "dehalo",
                "moire_suppress",
                "premultiply_alpha",
                "unpremultiply_alpha",
                "mask_feather",
                "mask_dilate",
                "mask_erode",
                "hann_feather_tile",
                "temporal_smooth"
            ]
            if let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
               let data = try? Data(contentsOf: url) {
                do {
                    for name in names { result[name] = try CIKernel(functionName: name, fromMetalLibraryData: data) }
                    print("CoreMLEngine: Loaded Metal kernels from default.metallib")
                    return result
                } catch {
                    print("CoreMLEngine: Failed to load kernels from metallib: \(error.localizedDescription)")
                }
            }
            if let url = Bundle.main.url(forResource: "Shaders", withExtension: "ci.metal"),
               let code = try? String(contentsOf: url, encoding: .utf8) {
                do {
                    for kernel in try CIKernel.kernels(withMetalString: code) where names.contains(kernel.name) {
                        result[kernel.name] = kernel
                    }
                    print("CoreMLEngine: Loaded Metal kernels from source")
                } catch {
                    print("CoreMLEngine: Failed to compile kernels from source: \(error.localizedDescription)")
                }
            }
            return result
        }
    }

    // Shared CIContext with linear working color space for color-accurate ops
    private static let ciContext: CIContext = {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let options: [CIContextOption: Any] = [
            .workingColorSpace: linear,
            .outputColorSpace: srgb
        ]
        return CIContext(options: options)
    }()

    private static let srgbColorSpace: CGColorSpace = {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }()

    // MARK: - Public Filter API

    /// Applies Drift Guard (Color Stabilization)
    /// - Parameters:
    ///   - input: AI upscaled image
    ///   - baseline: Bicubic upscaled baseline
    ///   - threshold: Difference threshold (0.0 - 1.0, typ. 0.05-0.1)
    ///   - strength: Correction strength (0.0 - 1.0)
    func applyDriftGuard(input: CIImage, baseline: CIImage, threshold: Double, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.driftGuardKernel else {
            print("Warning: DriftGuard Kernel not loaded")
            return input
        }

        // ROI Callback: Pointwise, but needs both inputs
        // Core Image automatically handles sampling from both if extents match

        guard let output = kernel.apply(extent: input.extent,
                                        roiCallback: { _, rect in rect },
                                        arguments: [input, baseline, CGFloat(threshold), CGFloat(strength)]) else {
            return input
        }

        return output
    }

    /// Applies Contrast Adaptive Sharpening (CAS)
    /// - Parameters:
    ///   - input: Source image
    ///   - sharpness: Strength (0.0 - 1.0)
    func applyCustomSharpen(_ input: CIImage, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.casKernel else {
            print("Warning: CAS Kernel not loaded")
            return input
        }

        let sharpness = CGFloat(max(0.0, min(1.0, strength)))
        if sharpness == 0 { return input }

        // ROI Callback: 3x3 window needs 1 pixel margin
        let roiCallback: CIKernelROICallback = { _, destRect in
            return destRect.insetBy(dx: -1, dy: -1)
        }

        guard let output = kernel.apply(extent: input.extent,
                                        roiCallback: roiCallback,
                                        arguments: [input, sharpness]) else {
            return input
        }

        return output
    }

    /// Applies Gradient-Aware Debanding
    /// - Parameters:
    ///   - input: Source image
    ///   - threshold: Sensitivity to gradients (0.001 - 0.1)
    ///   - amount: Dithering noise strength
    func applyDeband(_ input: CIImage, threshold: Double, amount: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.debandKernel else {
            print("Warning: Deband Kernel not loaded")
            return input
        }

        let thresh = CGFloat(max(0.001, min(0.1, threshold)))
        let amt = CGFloat(amount)
        if amt == 0 { return input }

        // ROI Callback: Uses 2-pixel radius neighborhood
        let roiCallback: CIKernelROICallback = { _, destRect in
            return destRect.insetBy(dx: -2, dy: -2)
        }

        guard let output = kernel.apply(extent: input.extent,
                                        roiCallback: roiCallback,
                                        arguments: [input, thresh, amt]) else {
            return input
        }

        return output
    }

    func applyDenoise(_ input: CIImage, sigmaSpatial: Double, sigmaRange: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.bilateralKernel else {
            print("Warning: Bilateral Kernel not loaded")
            return input
        }

        let sSpatial = CGFloat(sigmaSpatial)
        let sRange = CGFloat(sigmaRange)
        if sSpatial == 0 { return input }

        let radius = CGFloat(2.0)
        let roiCallback: CIKernelROICallback = { _, destRect in
            return destRect.insetBy(dx: -radius, dy: -radius)
        }

        guard let output = kernel.apply(extent: input.extent,
                                        roiCallback: roiCallback,
                                        arguments: [input, sSpatial, sRange]) else {
            return input
        }

        return output
    }

    // MARK: - Color Management

    func applyLinearizeSRGB(_ input: CIImage, exposure: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.linearizeKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect }
        let exp = CGFloat(exposure)
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input, exp]) ?? input
    }

    func applyEncodeSRGB(_ input: CIImage, exposure: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.encodeSrgbKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect }
        let exp = CGFloat(exposure)
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input, exp]) ?? input
    }

    func applyToneMap(_ input: CIImage, exposure: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.toneMapKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect }
        let exp = CGFloat(exposure)
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input, exp]) ?? input
    }

    func applyGammaBlend(base: CIImage, overlay: CIImage, mix: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.gammaBlendKernel else { return overlay }
        let roi: CIKernelROICallback = { _, rect in rect }
        let mixVal = CGFloat(max(0.0, min(1.0, mix)))
        return kernel.apply(extent: overlay.extent, roiCallback: roi, arguments: [overlay, base, mixVal]) ?? overlay
    }

    // MARK: - Sharpen / Detail

    func applyUnsharpMask(_ input: CIImage, radius: Double, amount: Double, threshold: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.unsharpKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -2, dy: -2) }
        return kernel.apply(extent: input.extent,
                            roiCallback: roi,
                            arguments: [input,
                                        CGFloat(radius),
                                        CGFloat(amount),
                                        CGFloat(threshold)]) ?? input
    }

    func applyLaplacianSharpen(_ input: CIImage, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.laplacianKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -1, dy: -1) }
        return kernel.apply(extent: input.extent,
                            roiCallback: roi,
                            arguments: [input, CGFloat(strength)]) ?? input
    }

    // MARK: - Extra Denoise / Deband

    func applyMedianDenoise(_ input: CIImage) -> CIImage {
        guard let kernel = ShaderRegistry.shared.medianKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -1, dy: -1) }
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input]) ?? input
    }

    func applyBlueNoiseDeband(_ input: CIImage, threshold: Double, amount: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.blueNoiseDebandKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -1, dy: -1) }
        return kernel.apply(extent: input.extent,
                            roiCallback: roi,
                            arguments: [input, CGFloat(threshold), CGFloat(amount)]) ?? input
    }

    // MARK: - Artifact Suppression

    func applyDehalo(_ input: CIImage, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.dehaloKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -1, dy: -1) }
        return kernel.apply(extent: input.extent,
                            roiCallback: roi,
                            arguments: [input, CGFloat(strength)]) ?? input
    }

    func applyMoireSuppress(_ input: CIImage, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.moireKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -1, dy: -1) }
        return kernel.apply(extent: input.extent,
                            roiCallback: roi,
                            arguments: [input, CGFloat(strength)]) ?? input
    }

    // MARK: - Alpha / Mask

    func applyPremultiplyAlpha(_ input: CIImage) -> CIImage {
        guard let kernel = ShaderRegistry.shared.premultiplyKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect }
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input]) ?? input
    }

    func applyUnpremultiplyAlpha(_ input: CIImage) -> CIImage {
        guard let kernel = ShaderRegistry.shared.unpremultiplyKernel else { return input }
        let roi: CIKernelROICallback = { _, rect in rect }
        return kernel.apply(extent: input.extent, roiCallback: roi, arguments: [input]) ?? input
    }

    func featherMask(_ mask: CIImage, radius: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.maskFeatherKernel else { return mask }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -3, dy: -3) }
        return kernel.apply(extent: mask.extent,
                            roiCallback: roi,
                            arguments: [mask, CGFloat(radius)]) ?? mask
    }

    func dilateMask(_ mask: CIImage, radius: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.maskDilateKernel else { return mask }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -3, dy: -3) }
        return kernel.apply(extent: mask.extent,
                            roiCallback: roi,
                            arguments: [mask, CGFloat(radius)]) ?? mask
    }

    func erodeMask(_ mask: CIImage, radius: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.maskErodeKernel else { return mask }
        let roi: CIKernelROICallback = { _, rect in rect.insetBy(dx: -3, dy: -3) }
        return kernel.apply(extent: mask.extent,
                            roiCallback: roi,
                            arguments: [mask, CGFloat(radius)]) ?? mask
    }

    func processMask(_ mask: CIImage, settings: SettingsConfiguration) -> CIImage {
        var m = mask
        if settings.maskDilateRadiusValue > 0 {
            m = dilateMask(m, radius: settings.maskDilateRadiusValue)
        }
        if settings.maskErodeRadiusValue > 0 {
            m = erodeMask(m, radius: settings.maskErodeRadiusValue)
        }
        if settings.maskFeatherRadiusValue > 0 {
            m = featherMask(m, radius: settings.maskFeatherRadiusValue)
        }
        return m
    }

    // MARK: - Tile Feathering

    func applyHannFeather(_ tile: CIImage, margin: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.hannFeatherKernel else { return tile }
        let roi: CIKernelROICallback = { _, rect in rect }
        let size = tile.extent.size
        return kernel.apply(extent: tile.extent,
                            roiCallback: roi,
                            arguments: [tile, CGFloat(size.width), CGFloat(size.height), CGFloat(margin)]) ?? tile
    }

    // MARK: - Temporal

    func applyTemporalSmooth(current: CIImage, previous: CIImage, strength: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.temporalSmoothKernel else { return current }
        let roi: CIKernelROICallback = { _, rect in rect }
        return kernel.apply(extent: current.extent,
                            roiCallback: roi,
                            arguments: [current, previous, CGFloat(strength)]) ?? current
    }

    // MARK: - Pipeline Integration Helper

    /// Helper to apply all active filters in the correct order
    /// Pipeline: Color → Denoise → Deband → Sharpen → Artifact cleanup → Encode
    func applyPostProcessing(to input: CIImage, original: CIImage? = nil, settings: SettingsConfiguration) -> CIImage {
        var processed = input
        let source = original ?? input

        // Alpha safety first
        if settings.metal.alphaSafeProcessing {
            processed = applyUnpremultiplyAlpha(processed)
        }

        // Color space shaping
        if settings.metal.enableColorLinearize {
            processed = applyLinearizeSRGB(processed, exposure: settings.colorExposureValue)
        }
        if settings.metal.enableToneMap {
            processed = applyToneMap(processed, exposure: settings.toneMapExposureValue)
        }

        // Optional median prefilter (light speckle)
        if settings.metal.useMedianPrefilter {
            processed = applyMedianDenoise(processed)
        }

        // Denoise (lightweight bilateral)
        if settings.primary.useDenoise && settings.primary.denoiseStrength.text != "0" {
            let strength = double(from: settings.primary.denoiseStrength.text, default: 0.0)
            let sigmaRange = strength * 0.02
            let sigmaSpatial = 2.0
            processed = applyDenoise(processed, sigmaSpatial: sigmaSpatial, sigmaRange: sigmaRange)
        }

        // Deband (dither + optional blue-noise)
        if settings.primary.useDeband && settings.primary.debandStrength.text != "0" {
            let thresh = 0.02
            let amount = double(from: settings.primary.debandStrength.text, default: 0.0)
            processed = applyDeband(processed, threshold: thresh, amount: amount)

            if settings.metal.useBlueNoiseDeband {
                processed = applyBlueNoiseDeband(processed, threshold: thresh * 0.6, amount: amount * 0.5)
            }
        }

        // Sharpen (CAS or USM/laplacian)
        if settings.primary.useSharpen && settings.primary.sharpenStrength.text != "0" {
            if settings.primary.sharpenMethod == "unsharp" {
                let radius = double(from: settings.primary.usmRadius.text, default: 5.0)
                let amount = double(from: settings.primary.usmAmount.text, default: 1.0)
                let threshold = double(from: settings.primary.usmThreshold.text, default: 0.03)
                processed = applyUnsharpMask(processed, radius: radius, amount: amount, threshold: threshold)
            } else {
                let strength = double(from: settings.primary.sharpenStrength.text, default: 0.0)
                processed = applyCustomSharpen(processed, strength: strength)
            }

            if settings.metal.useLaplacianSharpen {
                processed = applyLaplacianSharpen(processed, strength: settings.laplacianStrengthValue)
            }
        }

        // Artifact suppression
        if settings.metal.useDehalo {
            processed = applyDehalo(processed, strength: settings.dehaloStrengthValue)
        }
        if settings.metal.useMoireSuppress {
            processed = applyMoireSuppress(processed, strength: settings.moireStrengthValue)
        }

        // Encode back to sRGB / apply gamma-correct blend
        if settings.metal.encodeToSRGB {
            processed = applyEncodeSRGB(processed, exposure: settings.encodeExposureValue)
        }
        if settings.gammaBlendWeightValue > 0 {
            processed = applyGammaBlend(base: source, overlay: processed, mix: settings.gammaBlendWeightValue)
        }

        if settings.metal.alphaSafeProcessing {
            processed = applyPremultiplyAlpha(processed)
        }

        return processed
    }

    // MARK: - Buffer Bridging (CVPixelBuffer)

    /// Pre-filter before feeding CoreML (color normalization + light denoise)
    func applyPreProcessing(to input: CIImage, settings: SettingsConfiguration) -> CIImage {
        var processed = input

        if settings.metal.alphaSafeProcessing {
            processed = applyUnpremultiplyAlpha(processed)
        }

        if settings.metal.enableColorLinearize {
            processed = applyLinearizeSRGB(processed, exposure: settings.colorExposureValue)
        }
        if settings.metal.enableToneMap {
            processed = applyToneMap(processed, exposure: settings.toneMapExposureValue)
        }

        if settings.metal.useMedianPrefilter {
            processed = applyMedianDenoise(processed)
        }

        if settings.primary.useDenoise && settings.primary.denoiseStrength.text != "0" {
            let strength = double(from: settings.primary.denoiseStrength.text, default: 0.0)
            let sigmaRange = strength * 0.02
            let sigmaSpatial = 2.0
            processed = applyDenoise(processed, sigmaSpatial: sigmaSpatial, sigmaRange: sigmaRange)
        }

        if settings.metal.encodeToSRGB {
            processed = applyEncodeSRGB(processed, exposure: settings.encodeExposureValue)
        }

        if settings.metal.useCosineFeather && settings.tileFeatherMarginValue > 0 {
            processed = applyHannFeather(processed, margin: Double(settings.tileFeatherMarginValue))
        }

        if settings.metal.alphaSafeProcessing {
            processed = applyPremultiplyAlpha(processed)
        }

        return processed
    }

    /// Run pre-processing on a tile buffer prior to CoreML inference.
    func preprocessTileBuffer(_ buffer: CVPixelBuffer, settings: SettingsConfiguration) {
        guard settings.metal.enableColorLinearize
                || settings.metal.useMedianPrefilter
                || (settings.metal.useCosineFeather && settings.tileFeatherMarginValue > 0)
                || (settings.primary.useDenoise && settings.primary.denoiseStrength.text != "0") else {
            return
        }
        let ci = CIImage(cvPixelBuffer: buffer)
        let processed = applyPreProcessing(to: ci, settings: settings)
        CoreMLProcessingJob.ciContext.render(processed, to: buffer, bounds: processed.extent, colorSpace: CoreMLProcessingJob.srgbColorSpace)
    }

    /// Run post-processing on a full frame buffer and optionally apply temporal smoothing.
    func postprocessFrameBuffer(_ buffer: CVPixelBuffer,
                                previous: CVPixelBuffer?,
                                settings: SettingsConfiguration) {
        var ci = CIImage(cvPixelBuffer: buffer)
        let original = ci
        ci = applyPostProcessing(to: ci, original: original, settings: settings)

        if settings.metal.useTemporalSmoothing, let previous = previous {
            let prevCI = CIImage(cvPixelBuffer: previous)
            ci = applyTemporalSmooth(current: ci, previous: prevCI, strength: settings.temporalStrengthValue)
        }

        CoreMLProcessingJob.ciContext.render(ci, to: buffer, bounds: ci.extent, colorSpace: CoreMLProcessingJob.srgbColorSpace)
    }

    // MARK: - Helpers

    private func double(from value: String, default fallback: Double) -> Double {
        Double(value) ?? fallback
    }
}
