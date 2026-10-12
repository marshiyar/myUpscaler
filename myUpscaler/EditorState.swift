import SwiftUI
import AVFoundation
import Combine
import CoreImage
import Metal
import MetalKit
import UniformTypeIdentifiers

// MARK: - EDITOR STATE
@MainActor
final class EditorState: ObservableObject {

    // MARK: - File / Asset
    @Published var filePath: String = ""
    @Published var isHovered: Bool = false

    @Published var thumbnailImage: NSImage?
    @Published var originalThumbnail: NSImage?
    @Published var timelineFrames: [NSImage] = []
    @Published var timelineFrameTimes: [Double] = []

    @Published var selectedFrameIndex: Int = 0
    @Published var videoAsset: AVURLAsset?
    @Published var totalFrames: Int = 0
    @Published var videoFPS: Double = 30.0

    // MARK: - Filters (First Set)
    @Published var contrast: Double = UpscaleSettings.eqContrastNeutral
    @Published var brightness: Double = UpscaleSettings.eqBrightnessNeutral
    @Published var saturation: Double = UpscaleSettings.eqSaturationNeutral
    @Published var denoiseStrength: Double = 2.5
    @Published var deringActive: Bool = false
    @Published var deringStrength: Double = 0.5
    @Published var sharpenMethod: String = "cas"
    @Published var sharpenStrength: Double = 0.25
    @Published var usmRadius: Double = 5.0
    @Published var usmAmount: Double = 1.0
    @Published var usmThreshold: Double = 0.0
    
    // MARK: - Filters (Second Set)
    @Published var useDenoise2: Bool = false
    @Published var denoiseStrength2: Double = 2.5
    @Published var useDering2: Bool = false
    @Published var deringActive2: Bool = false
    @Published var deringStrength2: Double = 0.5
    @Published var useSharpen2: Bool = false
    @Published var sharpenMethod2: String = "cas"
    @Published var sharpenStrength2: Double = 0.25
    @Published var usmRadius2: Double = 5.0
    @Published var usmAmount2: Double = 1.0
    @Published var usmThreshold2: Double = 0.0

    // MARK: - Internal
    
    struct FilterParameters: Hashable {
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

    private var cancellables = Set<AnyCancellable>()
    private var filterCache = NSCache<NSString, NSImage>()
    private var _ciContext: CIContext?
    private var settings: UpscaleSettings?
    private var isProcessingFullUpscale: Bool = false
    private var pendingFilterUpdate: Bool = false
    private var mediaGeneration = UUID()
    private var frameGeneration = UUID()
    private var filterGeneration = UUID()
    private var isRenderingFilter = false
    private var thumbnailTask: Task<Void, Never>?
    private var timelineTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?

    private func invalidateMedia() {
        mediaGeneration = UUID()
        frameGeneration = UUID()
        filterGeneration = UUID()
        thumbnailTask?.cancel()
        timelineTask?.cancel()
        frameTask?.cancel()
        filterCache.removeAllObjects()
    }

    private func installOriginal(_ image: NSImage) {
        frameGeneration = UUID()
        filterGeneration = UUID()
        filterCache.removeAllObjects()
        originalThumbnail = image
        thumbnailImage = image
        applyFilters()
    }
    
    // Background queue for heavy filter operations
    private let filterQueue = DispatchQueue(label: "com.myupscaler.filter", qos: .userInitiated)
    
    // Lazy initialization of CIContext to avoid expensive Metal setup on app startup
    private var ciContext: CIContext {
        if let existing = _ciContext {
            return existing
        }
        let context: CIContext
        if let device = MTLCreateSystemDefaultDevice(),
           let _ = device.makeCommandQueue() {
            let options: [CIContextOption: Any] = [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .outputColorSpace: CGColorSpaceCreateDeviceRGB()
            ]
            context = CIContext(mtlDevice: device, options: options)
        } else {
            // Fallback to CPU context if Metal is unavailable
            context = CIContext()
        }
        _ciContext = context
        return context
    }

    init(settings: UpscaleSettings? = nil) {
        self.settings = settings
        
        // Configure filter cache limits to prevent excessive memory usage
        filterCache.countLimit = 10 // Only cache last 10 filtered images
        filterCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        
        // MARK: Reload video on path change
        $filePath
            .dropFirst()
            .sink { [weak self] path in
                guard let self = self else { return }
                self.reset()
                if !path.isEmpty {
                    self.loadThumbnail(path)
                    self.loadTimeline(path)
                } else {
                    self.reset()
                }
            }
            .store(in: &cancellables)

        // MARK: -  Sync from external settings if provided
        if let settings = settings {
            syncFromSettings(settings)
            
            // Optimized: Combine settings into fewer observers with throttling
            Publishers.CombineLatest3(settings.$noDenoise, settings.$noSharpen, settings.$noEq)
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _, _, _ in self?.applyFilters() }
                .store(in: &cancellables)

            // Group 1: Color and denoise settings (most frequently changed)
            Publishers.CombineLatest4(
                settings.$eqContrast,
                settings.$eqBrightness,
                settings.$eqSaturation,
                settings.$denoiseStrength
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 2: Deringing and sharpen settings
            Publishers.CombineLatest4(
                settings.$deringActive,
                settings.$deringStrength,
                settings.$sharpenMethod,
                settings.$sharpenStrength
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 3: USM parameters (only needed when unsharp is selected)
            Publishers.CombineLatest3(
                settings.$usmRadius,
                settings.$usmAmount,
                settings.$usmThreshold
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 4: Deband settings (less frequently updated)
            Publishers.CombineLatest(
                settings.$debandMethod,
                settings.$debandStrength
            )
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 5: Denoiser changes (affects denoise strength range)
            settings.$denoiser
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    // Use Task to ensure we're outside view update cycle
                    Task { @MainActor in
                        self.syncFromSettings(settings)
                    }
                }
                .store(in: &cancellables)
            
            // Group 6: Second set toggles and denoise
            Publishers.CombineLatest4(
                settings.$useDenoise2,
                settings.$denoiseStrength2,
                settings.$useDering2,
                settings.$deringActive2
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 7: Second set sharpen
            Publishers.CombineLatest4(
                settings.$useSharpen2,
                settings.$sharpenMethod2,
                settings.$sharpenStrength2,
                settings.$deringStrength2
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
            
            // Group 8: Second set USM parameters
            Publishers.CombineLatest3(
                settings.$usmRadius2,
                settings.$usmAmount2,
                settings.$usmThreshold2
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self = self else { return }
                // Use Task to ensure we're outside view update cycle
                Task { @MainActor in
                    self.syncFromSettings(settings)
                }
            }
            .store(in: &cancellables)
        }

        // MARK: -  Real-time filter updates (throttled for performance)
        // Use throttle instead of debounce for immediate updates during dragging
        // First set
        let p1 = $contrast.map { _ in () }.eraseToAnyPublisher()
        let p2 = $brightness.map { _ in () }.eraseToAnyPublisher()
        let p3 = $saturation.map { _ in () }.eraseToAnyPublisher()
        let p4 = $denoiseStrength.map { _ in () }.eraseToAnyPublisher()
        let p5 = $deringActive.map { _ in () }.eraseToAnyPublisher()
        let p6 = $deringStrength.map { _ in () }.eraseToAnyPublisher()
        let p7 = $sharpenMethod.map { _ in () }.eraseToAnyPublisher()
        let p8 = $sharpenStrength.map { _ in () }.eraseToAnyPublisher()
        let p9 = $usmRadius.map { _ in () }.eraseToAnyPublisher()
        let p10 = $usmAmount.map { _ in () }.eraseToAnyPublisher()
        let p11 = $usmThreshold.map { _ in () }.eraseToAnyPublisher()
        // Second set
        let p12 = $useDenoise2.map { _ in () }.eraseToAnyPublisher()
        let p13 = $denoiseStrength2.map { _ in () }.eraseToAnyPublisher()
        let p14 = $useDering2.map { _ in () }.eraseToAnyPublisher()
        let p15 = $deringActive2.map { _ in () }.eraseToAnyPublisher()
        let p16 = $deringStrength2.map { _ in () }.eraseToAnyPublisher()
        let p17 = $useSharpen2.map { _ in () }.eraseToAnyPublisher()
        let p18 = $sharpenMethod2.map { _ in () }.eraseToAnyPublisher()
        let p19 = $sharpenStrength2.map { _ in () }.eraseToAnyPublisher()
        let p20 = $usmRadius2.map { _ in () }.eraseToAnyPublisher()
        let p21 = $usmAmount2.map { _ in () }.eraseToAnyPublisher()
        let p22 = $usmThreshold2.map { _ in () }.eraseToAnyPublisher()

        Publishers.MergeMany([p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16, p17, p18, p19, p20, p21, p22])
            .throttle(for: .milliseconds(150), scheduler: RunLoop.main, latest: true) // Increased throttle to 150ms for better performance
            .sink { [weak self] in
                // Skip filter updates during full upscaling
                guard let self = self, !self.isProcessingFullUpscale else {
                    self?.pendingFilterUpdate = true
                    return
                }
                // Defer mutation of @Published properties to avoid publishing during view updates
                DispatchQueue.main.async { self.applyFilters() }
            }
            .store(in: &cancellables)
    }
    
    // MARK: -  Sync from UpscaleSettings
    func syncFromSettings(_ settings: UpscaleSettings) {
        // First set
        let contrastValue = Double(settings.eqContrast).flatMap { $0.isFinite ? $0 : nil } ?? settings.eqContrastDefault
        if contrast != contrastValue { contrast = contrastValue }
        let brightnessValue = Double(settings.eqBrightness).flatMap { $0.isFinite ? $0 : nil } ?? settings.eqBrightnessDefault
        if brightness != brightnessValue { brightness = brightnessValue }
        let saturationValue = Double(settings.eqSaturation).flatMap { $0.isFinite ? $0 : nil } ?? settings.eqSaturationDefault
        if saturation != saturationValue { saturation = saturationValue }
        if denoiseStrength != (Double(settings.denoiseStrength) ?? 2.5) { denoiseStrength = Double(settings.denoiseStrength) ?? 2.5 }
        if deringActive != (settings.deringActive) { deringActive = settings.deringActive }
        if deringStrength != (Double(settings.deringStrength) ?? 0.5) { deringStrength = Double(settings.deringStrength) ?? 0.5 }
        if sharpenMethod != (settings.sharpenMethod) { sharpenMethod = settings.sharpenMethod }
        if sharpenStrength != (Double(settings.sharpenStrength) ?? 0.25) { sharpenStrength = Double(settings.sharpenStrength) ?? 0.25 }
        if usmRadius != (Double(settings.usmRadius) ?? 5.0) { usmRadius = Double(settings.usmRadius) ?? 5.0 }
        if usmAmount != (Double(settings.usmAmount) ?? 1.0) { usmAmount = Double(settings.usmAmount) ?? 1.0 }
        if usmThreshold != (Double(settings.usmThreshold) ?? 0.0) { usmThreshold = Double(settings.usmThreshold) ?? 0.0 }
        
        // Second set
        if useDenoise2 != (settings.useDenoise2) { useDenoise2 = settings.useDenoise2 }
        if denoiseStrength2 != (Double(settings.denoiseStrength2) ?? 2.5) { denoiseStrength2 = Double(settings.denoiseStrength2) ?? 2.5 }
        if useDering2 != (settings.useDering2) { useDering2 = settings.useDering2 }
        if deringActive2 != (settings.deringActive2) { deringActive2 = settings.deringActive2 }
        if deringStrength2 != (Double(settings.deringStrength2) ?? 0.5) { deringStrength2 = Double(settings.deringStrength2) ?? 0.5 }
        if useSharpen2 != (settings.useSharpen2) { useSharpen2 = settings.useSharpen2 }
        if sharpenMethod2 != (settings.sharpenMethod2) { sharpenMethod2 = settings.sharpenMethod2 }
        if sharpenStrength2 != (Double(settings.sharpenStrength2) ?? 0.25) { sharpenStrength2 = Double(settings.sharpenStrength2) ?? 0.25 }
        if usmRadius2 != (Double(settings.usmRadius2) ?? 5.0) { usmRadius2 = Double(settings.usmRadius2) ?? 5.0 }
        if usmAmount2 != (Double(settings.usmAmount2) ?? 1.0) { usmAmount2 = Double(settings.usmAmount2) ?? 1.0 }
        if usmThreshold2 != (Double(settings.usmThreshold2) ?? 0.0) { usmThreshold2 = Double(settings.usmThreshold2) ?? 0.0 }
    }

    // MARK: -  Reset
    func reset() {
        invalidateMedia()
        thumbnailImage = nil
        originalThumbnail = nil
        timelineFrames = []
        timelineFrameTimes = []
        selectedFrameIndex = 0
        videoAsset = nil
        totalFrames = 0
        videoFPS = 30.0
        filterCache.removeAllObjects() // Clear cache on reset
    }

    // MARK: Select Frame
    func selectFrame(_ index: Int) {
        guard index >= 0, index < timelineFrames.count else { return }
        selectedFrameIndex = index
        if index < timelineFrameTimes.count {
            loadFullResolutionFrame(at: timelineFrameTimes[index])
        }
    }

    // MARK: - Load Thumbnail
    func loadThumbnail(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            if let image = NSImage(contentsOf: url) {
                self.installOriginal(image)
                self.videoAsset = nil
                return
            }
        }

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        let generation = mediaGeneration
        let selectedFrame = frameGeneration
        thumbnailTask?.cancel()
        thumbnailTask = Task {
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
               
                await MainActor.run {
                    guard generation == self.mediaGeneration, selectedFrame == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(nsImage)
                }
            } catch {
                print("Thumbnail error: \(error)")
            }
        }
    }

    // MARK: -  Load Timeline
    func loadTimeline(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        
        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            if let image = NSImage(contentsOf: url) {
                self.videoFPS = 0
                self.totalFrames = 1
                self.timelineFrames = [image]
                self.timelineFrameTimes = [0.0]
                return
            }
        }

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        let generation = mediaGeneration
        timelineTask?.cancel()
        timelineTask = Task {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }

            guard let durationTime = try? await asset.load(.duration) else { return }
            let duration = durationTime.seconds
           
            let fpsFloat = try? await track.load(.nominalFrameRate)
            let reportedFPS = Double(fpsFloat ?? 30.0)
            let fps = reportedFPS.isFinite && reportedFPS > 0 ? reportedFPS : 30.0
            guard duration.isFinite, duration >= 0, !Task.isCancelled else { return }
           
            await MainActor.run {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                self.videoFPS = fps
                self.totalFrames = Int(duration * fps)
                self.timelineFrames.removeAll()
                self.timelineFrameTimes.removeAll()
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)

            // Prepare times - limit to 50 frames for better memory performance
            var times: [CMTime] = []
            let count = min(Int(duration * fps), 50) // Reduced from 200 to 50
            for i in 0..<count {
                let t = Double(i) / fps
                times.append(CMTime(seconds: t, preferredTimescale: 600))
            }
           
            var loadedImages: [NSImage] = []
            var loadedTimes: [Double] = []
           
            for await result in generator.images(for: times) {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                switch result {
                case .success(requestedTime: let req, image: let img, actualTime: _):
                    loadedImages.append(NSImage(cgImage: img, size: .zero))
                    loadedTimes.append(req.seconds)
                case .failure:
                    continue
                }
            }
           
            let finalImages = loadedImages
            let finalTimes = loadedTimes
           
            await MainActor.run {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                self.timelineFrames = finalImages
                self.timelineFrameTimes = finalTimes
            }
        }
    }

    // MARK: -  Load Full-Res Frame
    func loadFullResolutionFrame(at timeSeconds: Double) {
        if videoAsset == nil, !timelineFrames.isEmpty {
             if let original = originalThumbnail {
                 self.installOriginal(original)
             }
             return
        }

        guard let asset = videoAsset else { return }

        frameTask?.cancel()
        let generation = UUID()
        frameGeneration = generation
        filterGeneration = UUID()
        frameTask = Task {
            let tracks = try? await asset.loadTracks(withMediaType: AVMediaType.video)
            guard let videoTrack = tracks?.first else { return }

            let naturalSize = try? await videoTrack.load(.naturalSize)
            let preferredTransform = try? await videoTrack.load(.preferredTransform)

            var videoSize = naturalSize ?? CGSize(width: 1920, height: 1080)

            if let t = preferredTransform,
               (t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0) ||
               (t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0) {
                videoSize = CGSize(width: videoSize.height, height: videoSize.width)
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = videoSize
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ns = NSImage(cgImage: cgImage, size: .zero)
               
                await MainActor.run {
                    guard generation == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(ns)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.frameGeneration, !Task.isCancelled else { return }
                    if self.selectedFrameIndex < self.timelineFrames.count {
                        let fallback = self.timelineFrames[self.selectedFrameIndex]
                        self.installOriginal(fallback)
                    }
                }
            }
        }
    }

    // MARK: -  Filters
    func applyFilters() {
        guard let original = originalThumbnail else { return }
        filterGeneration = UUID()
        let generation = filterGeneration
        guard !isProcessingFullUpscale else { pendingFilterUpdate = true; return }
        guard !isRenderingFilter else { pendingFilterUpdate = true; return }
        pendingFilterUpdate = false
        
        // Capture parameters on MainActor to avoid isolation issues
        let params = FilterParameters(
            noDenoise: settings?.noDenoise ?? false,
            noSharpen: settings?.noSharpen ?? false,
            noEq: settings?.noEq ?? false,
            contrast: contrast,
            brightness: brightness,
            saturation: saturation,
            denoiseStrength: denoiseStrength,
            deringActive: deringActive,
            deringStrength: deringStrength,
            sharpenMethod: sharpenMethod,
            sharpenStrength: sharpenStrength,
            usmRadius: usmRadius,
            usmAmount: usmAmount,
            usmThreshold: usmThreshold,
            // Second set
            useDenoise2: useDenoise2,
            denoiseStrength2: denoiseStrength2,
            useDering2: useDering2,
            deringActive2: deringActive2,
            deringStrength2: deringStrength2,
            useSharpen2: useSharpen2,
            sharpenMethod2: sharpenMethod2,
            sharpenStrength2: sharpenStrength2,
            usmRadius2: usmRadius2,
            usmAmount2: usmAmount2,
            usmThreshold2: usmThreshold2
        )
        
        // Create cache key from filter parameters (including second set)
        let cacheKeyString = "\(frameGeneration)_\(String(reflecting: params))"
        
        // Check cache first
        if let cached = filterCache.object(forKey: cacheKeyString as NSString) {
            thumbnailImage = cached
            return
        }
        
        let context = self.ciContext
        
        isRenderingFilter = true
        filterQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Use static nonisolated method
            let filteredImage = EditorState.processImage(original, params: params, context: context)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.isRenderingFilter = false
                if self.pendingFilterUpdate && !self.isProcessingFullUpscale {
                    self.applyFilters()
                    return
                }
                guard generation == self.filterGeneration, !self.isProcessingFullUpscale else { return }
                self.thumbnailImage = filteredImage
                // Cache the filtered image
                if let image = filteredImage {
                    self.filterCache.setObject(image, forKey: cacheKeyString as NSString)
                }
            }
        }
    }
    
    // MARK: - Upscaling State Management
    func setProcessingFullUpscale(_ isProcessing: Bool) {
        isProcessingFullUpscale = isProcessing
        if !isProcessing && pendingFilterUpdate {
            pendingFilterUpdate = false
            applyFilters()
        }
    }

    // Non-isolated helper for background processing
    nonisolated static func processImage(_ image: NSImage, params: FilterParameters, context: CIContext) -> NSImage? {
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
    

    // MARK: - Timing
    func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        let ms = Int((s - floor(s)) * 100)
        return String(format: "%02d:%02d.%02d", m, sec, ms)
    }
}

