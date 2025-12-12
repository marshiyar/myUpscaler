import Foundation
import CoreImage
import CoreGraphics
import CoreVideo

// MARK: - CoreML Engine Shader Extension

extension CoreMLEngine {
    
    /// Manages the custom Metal kernels for video restoration
    class ShaderRegistry {
        static let shared = ShaderRegistry()
        
        var casKernel: CIKernel?
        var debandKernel: CIKernel?
        var bilateralKernel: CIKernel?
        var driftGuardKernel: CIKernel?
        var linearizeKernel: CIKernel?
        var encodeSrgbKernel: CIKernel?
        var toneMapKernel: CIKernel?
        var gammaBlendKernel: CIKernel?
        var unsharpKernel: CIKernel?
        var laplacianKernel: CIKernel?
        var medianKernel: CIKernel?
        var blueNoiseDebandKernel: CIKernel?
        var dehaloKernel: CIKernel?
        var moireKernel: CIKernel?
        var premultiplyKernel: CIKernel?
        var unpremultiplyKernel: CIKernel?
        var maskFeatherKernel: CIKernel?
        var maskDilateKernel: CIKernel?
        var maskErodeKernel: CIKernel?
        var hannFeatherKernel: CIKernel?
        var temporalSmoothKernel: CIKernel?
        
        private init() {
            loadKernels()
        }
        
        private func loadKernels() {
            // 1. Try to load from default.metallib (compiled Metal)
            if let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
               let data = try? Data(contentsOf: url) {
                
                do {
                    // Note: In production, you load specific kernels by name.
                    // General kernels (color) vs Warp/Sampler kernels.
                    // cas_sharpen uses sampler -> CIKernel (general)
                    // deband_dither uses sampler -> CIKernel
                    // bilateral_denoise uses sampler -> CIKernel
                    
                    self.casKernel = try CIKernel(functionName: "cas_sharpen", fromMetalLibraryData: data)
                    self.debandKernel = try CIKernel(functionName: "deband_dither", fromMetalLibraryData: data)
                    self.bilateralKernel = try CIKernel(functionName: "bilateral_denoise", fromMetalLibraryData: data)
                    self.driftGuardKernel = try CIKernel(functionName: "drift_guard", fromMetalLibraryData: data)
                    self.linearizeKernel = try CIKernel(functionName: "linearize_srgb", fromMetalLibraryData: data)
                    self.encodeSrgbKernel = try CIKernel(functionName: "encode_srgb", fromMetalLibraryData: data)
                    self.toneMapKernel = try CIKernel(functionName: "tone_map_reinhard", fromMetalLibraryData: data)
                    self.gammaBlendKernel = try CIKernel(functionName: "gamma_correct_blend", fromMetalLibraryData: data)
                    self.unsharpKernel = try CIKernel(functionName: "unsharp_mask", fromMetalLibraryData: data)
                    self.laplacianKernel = try CIKernel(functionName: "laplacian_sharpen", fromMetalLibraryData: data)
                    self.medianKernel = try CIKernel(functionName: "median_denoise", fromMetalLibraryData: data)
                    self.blueNoiseDebandKernel = try CIKernel(functionName: "blue_noise_deband", fromMetalLibraryData: data)
                    self.dehaloKernel = try CIKernel(functionName: "dehalo", fromMetalLibraryData: data)
                    self.moireKernel = try CIKernel(functionName: "moire_suppress", fromMetalLibraryData: data)
                    self.premultiplyKernel = try CIKernel(functionName: "premultiply_alpha", fromMetalLibraryData: data)
                    self.unpremultiplyKernel = try CIKernel(functionName: "unpremultiply_alpha", fromMetalLibraryData: data)
                    self.maskFeatherKernel = try CIKernel(functionName: "mask_feather", fromMetalLibraryData: data)
                    self.maskDilateKernel = try CIKernel(functionName: "mask_dilate", fromMetalLibraryData: data)
                    self.maskErodeKernel = try CIKernel(functionName: "mask_erode", fromMetalLibraryData: data)
                    self.hannFeatherKernel = try CIKernel(functionName: "hann_feather_tile", fromMetalLibraryData: data)
                    self.temporalSmoothKernel = try CIKernel(functionName: "temporal_smooth", fromMetalLibraryData: data)
                    print("CoreMLEngine: Loaded Metal kernels from default.metallib")
                    return
                } catch {
                    print("CoreMLEngine: Failed to load kernels from metallib: \(error.localizedDescription)")
                }
            }
            
            // 2. Fallback: Load from source (Shaders.ci.metal) if provided as resource (Dev mode)
            // This is useful if the build system didn't bundle the metallib correctly
            if let url = Bundle.main.url(forResource: "Shaders", withExtension: "ci.metal"),
               let code = try? String(contentsOf: url) {
                do {
                    let kernels = try CIKernel.kernels(withMetalString: code)
                    for kernel in kernels {
                        if kernel.name == "cas_sharpen" { self.casKernel = kernel }
                        if kernel.name == "deband_dither" { self.debandKernel = kernel }
                        if kernel.name == "bilateral_denoise" { self.bilateralKernel = kernel }
                        if kernel.name == "drift_guard" { self.driftGuardKernel = kernel }
                        if kernel.name == "linearize_srgb" { self.linearizeKernel = kernel }
                        if kernel.name == "encode_srgb" { self.encodeSrgbKernel = kernel }
                        if kernel.name == "tone_map_reinhard" { self.toneMapKernel = kernel }
                        if kernel.name == "gamma_correct_blend" { self.gammaBlendKernel = kernel }
                        if kernel.name == "unsharp_mask" { self.unsharpKernel = kernel }
                        if kernel.name == "laplacian_sharpen" { self.laplacianKernel = kernel }
                        if kernel.name == "median_denoise" { self.medianKernel = kernel }
                        if kernel.name == "blue_noise_deband" { self.blueNoiseDebandKernel = kernel }
                        if kernel.name == "dehalo" { self.dehaloKernel = kernel }
                        if kernel.name == "moire_suppress" { self.moireKernel = kernel }
                        if kernel.name == "premultiply_alpha" { self.premultiplyKernel = kernel }
                        if kernel.name == "unpremultiply_alpha" { self.unpremultiplyKernel = kernel }
                        if kernel.name == "mask_feather" { self.maskFeatherKernel = kernel }
                        if kernel.name == "mask_dilate" { self.maskDilateKernel = kernel }
                        if kernel.name == "mask_erode" { self.maskErodeKernel = kernel }
                        if kernel.name == "hann_feather_tile" { self.hannFeatherKernel = kernel }
                        if kernel.name == "temporal_smooth" { self.temporalSmoothKernel = kernel }
                    }
                    print("CoreMLEngine: Loaded Metal kernels from source")
                } catch {
                    print("CoreMLEngine: Failed to compile kernels from source: \(error.localizedDescription)")
                }
            }
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
    
    /// Applies Bilateral Denoising
    /// - Parameters:
    ///   - input: Source image
    ///   - sigmaSpatial: Spatial influence radius
    ///   - sigmaRange: Color similarity threshold
    func applyDenoise(_ input: CIImage, sigmaSpatial: Double, sigmaRange: Double) -> CIImage {
        guard let kernel = ShaderRegistry.shared.bilateralKernel else {
            print("Warning: Bilateral Kernel not loaded")
            return input
        }
        
        let sSpatial = CGFloat(sigmaSpatial)
        let sRange = CGFloat(sigmaRange)
        if sSpatial == 0 { return input }
        
        // ROI Callback: 5x5 window needs 2 pixel margin
        // If we increase kernel radius, this must match
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
    
    func processMask(_ mask: CIImage, settings: UpscaleSettings) -> CIImage {
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
    func applyPostProcessing(to input: CIImage, original: CIImage? = nil, settings: UpscaleSettings) -> CIImage {
        var processed = input
        let source = original ?? input
        
        // Alpha safety first
        if settings.alphaSafeProcessing {
            processed = applyUnpremultiplyAlpha(processed)
        }
        
        // Color space shaping
        if settings.enableColorLinearize {
            processed = applyLinearizeSRGB(processed, exposure: settings.colorExposureValue)
        }
        if settings.enableToneMap {
            processed = applyToneMap(processed, exposure: settings.toneMapExposureValue)
        }
        
        // Optional median prefilter (light speckle)
        if settings.useMedianPrefilter {
            processed = applyMedianDenoise(processed)
        }
        
        // Denoise (lightweight bilateral)
        if !settings.noDenoise && settings.denoiseStrength != "0" {
            let strength = double(from: settings.denoiseStrength, default: 0.0)
            let sigmaRange = strength * 0.02
            let sigmaSpatial = 2.0
            processed = applyDenoise(processed, sigmaSpatial: sigmaSpatial, sigmaRange: sigmaRange)
        }
        
        // Deband (dither + optional blue-noise)
        if !settings.noDeband && settings.debandStrength != "0" {
            let thresh = 0.02
            let amount = double(from: settings.debandStrength, default: 0.0)
            processed = applyDeband(processed, threshold: thresh, amount: amount)
            
            if settings.useBlueNoiseDeband {
                processed = applyBlueNoiseDeband(processed, threshold: thresh * 0.6, amount: amount * 0.5)
            }
        }
        
        // Sharpen (CAS or USM/laplacian)
        if !settings.noSharpen && settings.sharpenStrength != "0" {
            if settings.sharpenMethod == "unsharp" {
                let radius = double(from: settings.usmRadius, default: 5.0)
                let amount = double(from: settings.usmAmount, default: 1.0)
                let threshold = double(from: settings.usmThreshold, default: 0.03)
                processed = applyUnsharpMask(processed, radius: radius, amount: amount, threshold: threshold)
            } else {
                let strength = double(from: settings.sharpenStrength, default: 0.0)
                processed = applyCustomSharpen(processed, strength: strength)
            }
            
            if settings.useLaplacianSharpen {
                processed = applyLaplacianSharpen(processed, strength: settings.laplacianStrengthValue)
            }
        }
        
        // Artifact suppression
        if settings.useDehalo {
            processed = applyDehalo(processed, strength: settings.dehaloStrengthValue)
        }
        if settings.useMoireSuppress {
            processed = applyMoireSuppress(processed, strength: settings.moireStrengthValue)
        }
        
        // Encode back to sRGB / apply gamma-correct blend
        if settings.encodeToSRGB {
            processed = applyEncodeSRGB(processed, exposure: settings.encodeExposureValue)
        }
        if settings.gammaBlendWeightValue > 0 {
            processed = applyGammaBlend(base: source, overlay: processed, mix: settings.gammaBlendWeightValue)
        }
        
        if settings.alphaSafeProcessing {
            processed = applyPremultiplyAlpha(processed)
        }
        
        return processed
    }
    
    // MARK: - Buffer Bridging (CVPixelBuffer)
    
    /// Pre-filter before feeding CoreML (color normalization + light denoise)
    func applyPreProcessing(to input: CIImage, settings: UpscaleSettings) -> CIImage {
        var processed = input
        
        if settings.alphaSafeProcessing {
            processed = applyUnpremultiplyAlpha(processed)
        }
        
        if settings.enableColorLinearize {
            processed = applyLinearizeSRGB(processed, exposure: settings.colorExposureValue)
        }
        if settings.enableToneMap {
            processed = applyToneMap(processed, exposure: settings.toneMapExposureValue)
        }
        
        if settings.useMedianPrefilter {
            processed = applyMedianDenoise(processed)
        }
        
        if !settings.noDenoise && settings.denoiseStrength != "0" {
            let strength = double(from: settings.denoiseStrength, default: 0.0)
            let sigmaRange = strength * 0.02
            let sigmaSpatial = 2.0
            processed = applyDenoise(processed, sigmaSpatial: sigmaSpatial, sigmaRange: sigmaRange)
        }
        
        if settings.encodeToSRGB {
            processed = applyEncodeSRGB(processed, exposure: settings.encodeExposureValue)
        }
        
        if settings.useCosineFeather && settings.tileFeatherMarginValue > 0 {
            processed = applyHannFeather(processed, margin: Double(settings.tileFeatherMarginValue))
        }
        
        if settings.alphaSafeProcessing {
            processed = applyPremultiplyAlpha(processed)
        }
        
        return processed
    }
    
    /// Run pre-processing on a tile buffer prior to CoreML inference.
    func preprocessTileBuffer(_ buffer: CVPixelBuffer, settings: UpscaleSettings) {
        guard settings.enableColorLinearize
                || settings.useMedianPrefilter
                || (settings.useCosineFeather && settings.tileFeatherMarginValue > 0)
                || (!settings.noDenoise && settings.denoiseStrength != "0") else {
            return
        }
        let ci = CIImage(cvPixelBuffer: buffer)
        let processed = applyPreProcessing(to: ci, settings: settings)
        CoreMLEngine.ciContext.render(processed, to: buffer, bounds: processed.extent, colorSpace: CoreMLEngine.srgbColorSpace)
    }
    
    /// Run post-processing on a full frame buffer and optionally apply temporal smoothing.
    func postprocessFrameBuffer(_ buffer: CVPixelBuffer,
                                previous: CVPixelBuffer?,
                                settings: UpscaleSettings) {
        var ci = CIImage(cvPixelBuffer: buffer)
        let original = ci
        ci = applyPostProcessing(to: ci, original: original, settings: settings)
        
        if settings.useTemporalSmoothing, let previous = previous {
            let prevCI = CIImage(cvPixelBuffer: previous)
            ci = applyTemporalSmooth(current: ci, previous: prevCI, strength: settings.temporalStrengthValue)
        }
        
        CoreMLEngine.ciContext.render(ci, to: buffer, bounds: ci.extent, colorSpace: CoreMLEngine.srgbColorSpace)
    }
    
    // MARK: - Helpers
    
    private func double(from value: String, default fallback: Double) -> Double {
        Double(value) ?? fallback
    }
}
