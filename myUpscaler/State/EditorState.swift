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
    var timelinePresentationTimes: [CMTime] = []
    var loadedFramePresentationTime: CMTime?
    var pendingFramePresentationTime: CMTime?

    @Published var selectedFrameIndex: Int = 0
    @Published var videoAsset: AVURLAsset?
    @Published var totalFrames: Int = 0
    @Published var videoFPS: Double = 30.0

    // MARK: - Internal

    private var cancellables = Set<AnyCancellable>()
    private let filterCache = NSCache<PreviewCacheKey, NSImage>()
    private var desiredKey: PreviewRequestKey?
    private var publishedKey: PreviewRequestKey?
    private var snapshotTask: Task<Void, Never>?
    private let previewRenderer: @Sendable (NSImage, PreviewFilterParameters, CIContext) -> NSImage?
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
        loadedFramePresentationTime = nil
        pendingFramePresentationTime = nil
        filterCache.removeAllObjects()
        desiredKey = nil
        publishedKey = nil
        pendingFilterUpdate = false
        snapshotTask?.cancel()
        snapshotTask = nil
    }

    func beginFrameRequest() -> UUID {
        frameGeneration = UUID()
        filterGeneration = UUID()
        desiredKey = nil
        publishedKey = nil
        originalThumbnail = nil
        return frameGeneration
    }

    func installOriginal(_ image: NSImage, presentationTime: CMTime? = nil) {
        loadedFramePresentationTime = presentationTime
        pendingFramePresentationTime = nil
        frameGeneration = UUID()
        filterGeneration = UUID()
        filterCache.removeAllObjects()
        originalThumbnail = image
        desiredKey = nil
        publishedKey = nil
        if !isProcessingFullUpscale { thumbnailImage = image }
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

    init(settings: UpscaleSettings? = nil,
         previewRenderer: @escaping @Sendable (NSImage, PreviewFilterParameters, CIContext) -> NSImage? = { image, parameters, context in PreviewRenderer.render(image, params: parameters, context: context) }) {
        self.settings = settings ?? UpscaleSettings()
        self.previewRenderer = previewRenderer

        // Configure filter cache limits to prevent excessive memory usage
        filterCache.countLimit = 10 // Only cache last 10 filtered images
        filterCache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit

        // MARK: Reload video on path change
        $filePath
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] path in
                guard let self = self else { return }
                self.reset()
                if !path.isEmpty {
                    self.loadThumbnail(path)
                    self.loadTimeline(path)
                }
            }
            .store(in: &cancellables)

        // objectWillChange fires before mutation. Defer one snapshot until the
        // current MainActor turn finishes, so a burst observes its final values.
        self.settings?.objectWillChange
            .sink { [weak self] in self?.scheduleSnapshot() }
            .store(in: &cancellables)
    }

    private func scheduleSnapshot() {
        // Reject an old worker immediately, before the deferred snapshot runs.
        filterGeneration = UUID()
        guard snapshotTask == nil else { return }
        snapshotTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.snapshotTask = nil
            self.applyFilters()
        }
    }

    // MARK: -  Reset
    func reset() {
        invalidateMedia()
        thumbnailImage = nil
        originalThumbnail = nil
        timelineFrames = []
        timelineFrameTimes = []
        timelinePresentationTimes = []
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
            loadFullResolutionFrame(at: timelineFrameTimes[index],
                presentationTime: index < timelinePresentationTimes.count ? timelinePresentationTimes[index] : nil)
        }
    }

    // MARK: - Filters
    func applyFilters() {
        guard let original = originalThumbnail, let settings else { return }
        let key = PreviewRequestKey(frameGeneration: frameGeneration,
                                    parameters: settings.makePreviewFilterParameters())
        if desiredKey != key {
            filterGeneration = UUID()
            desiredKey = key
        }
        submitDesired(original: original)
    }

    private func submitDesired(original: NSImage? = nil) {
        guard let key = desiredKey, key.frameGeneration == frameGeneration,
              let original = original ?? originalThumbnail else { return }
        guard !isProcessingFullUpscale else { pendingFilterUpdate = true; return }
        guard publishedKey != key else { pendingFilterUpdate = false; return }
        if let cached = filterCache.object(forKey: PreviewCacheKey(key)) {
            thumbnailImage = cached
            publishedKey = key
            pendingFilterUpdate = false
            return
        }
        guard !isRenderingFilter else { pendingFilterUpdate = true; return }
        isRenderingFilter = true
        pendingFilterUpdate = false
        let generation = filterGeneration
        let context = ciContext
        let renderer = previewRenderer
        filterQueue.async { [weak self] in
            let filtered = renderer(original, key.parameters, context)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRenderingFilter = false
                if key.frameGeneration == self.frameGeneration, let image = filtered {
                    // A superseded setting combination can still be reused later;
                    // a superseded media frame can never enter this frame's cache.
                    self.filterCache.setObject(image, forKey: PreviewCacheKey(key),
                                               cost: Self.cacheCost(of: image))
                }
                guard self.snapshotTask == nil else { return }
                if generation == self.filterGeneration && self.desiredKey == key && !self.isProcessingFullUpscale {
                    self.thumbnailImage = filtered
                    self.publishedKey = key
                } else {
                    self.submitDesired()
                }
            }
        }
    }

    nonisolated static func cacheCost(bytesPerRow: Int, height: Int) -> Int {
        guard bytesPerRow > 0, height > 0 else { return 0 }
        let (cost, overflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        return overflow ? Int.max : cost
    }

    private static func cacheCost(of image: NSImage) -> Int {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Int.max }
        return cacheCost(bytesPerRow: cg.bytesPerRow, height: cg.height)
    }

    // MARK: - Upscaling State Management
    func setProcessingFullUpscale(_ isProcessing: Bool) {
        guard isProcessingFullUpscale != isProcessing else { return }
        isProcessingFullUpscale = isProcessing
        if isProcessing {
            filterGeneration = UUID()
            pendingFilterUpdate = originalThumbnail != nil
        } else if pendingFilterUpdate {
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

