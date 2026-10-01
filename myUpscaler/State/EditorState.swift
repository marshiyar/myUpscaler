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
    @Published var contrast: Double = 1.03
    @Published var brightness: Double = 0.005
    @Published var saturation: Double = 1.06
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

    private var cancellables = Set<AnyCancellable>()
    private var filterCache = NSCache<NSString, NSImage>()
    private var _ciContext: CIContext?
    private var settings: UpscaleSettings?
    private var isProcessingFullUpscale: Bool = false
    private var pendingFilterUpdate: Bool = false
    // Internal access is limited to the media-loading extension; state owns all requests.
    var mediaGeneration = UUID()
    var frameGeneration = UUID()
    var filterGeneration = UUID()
    private var isRenderingFilter = false
    var thumbnailTask: Task<Void, Never>?
    var timelineTask: Task<Void, Never>?
    var frameTask: Task<Void, Never>?

    private func invalidateMedia() {
        mediaGeneration = UUID()
        frameGeneration = UUID()
        filterGeneration = UUID()
        thumbnailTask?.cancel()
        timelineTask?.cancel()
        frameTask?.cancel()
        filterCache.removeAllObjects()
    }

    func installOriginal(_ image: NSImage) {
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
            settings.$scaler
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.applyFilters() }
                }
                .store(in: &cancellables)
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
            Publishers.CombineLatest3(
                settings.$useDenoise2,
                settings.$denoiseStrength2,
                settings.$useDering2
            )
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self = self else { return }
                Task { @MainActor in self.syncFromSettings(settings) }
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
        if contrast != (Double(settings.eqContrast) ?? 1.03) { contrast = Double(settings.eqContrast) ?? 1.03 }
        if brightness != (Double(settings.eqBrightness) ?? 0.005) { brightness = Double(settings.eqBrightness) ?? 0.005 }
        if saturation != (Double(settings.eqSaturation) ?? 1.06) { saturation = Double(settings.eqSaturation) ?? 1.06 }
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

    // MARK: -  Filters
    func applyFilters() {
        guard let original = originalThumbnail else { return }
        filterGeneration = UUID()
        let generation = filterGeneration
        guard !isProcessingFullUpscale else { pendingFilterUpdate = true; return }
        guard !isRenderingFilter else { pendingFilterUpdate = true; return }
        pendingFilterUpdate = false

        // Capture parameters on MainActor to avoid isolation issues
        let params = PreviewFilterParameters(
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
            useDenoise2: useDenoise2 && settings?.scaler != "coreml",
            denoiseStrength2: denoiseStrength2,
            useDering2: useDering2 && settings?.scaler != "coreml",
            deringActive2: deringActive2,
            deringStrength2: deringStrength2,
            useSharpen2: useSharpen2 && settings?.scaler != "coreml",
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
            let filteredImage = PreviewRenderer.render(original, params: params, context: context)

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

    // MARK: - Timing
    func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60
        let sec = Int(s) % 60
        let ms = Int((s - floor(s)) * 100)
        return String(format: "%02d:%02d.%02d", m, sec, ms)
    }
}

