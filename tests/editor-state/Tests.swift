import AppKit
import Combine

@main struct EditorStateTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func image(_ red: UInt8, _ blue: UInt8) -> NSImage {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
            for i in 0..<1024 {
                rep.bitmapData![i * 4] = red
                rep.bitmapData![i * 4 + 1] = 40
                rep.bitmapData![i * 4 + 2] = blue
                rep.bitmapData![i * 4 + 3] = 255
            }
            let result = NSImage(size: NSSize(width: 32, height: 32))
            result.addRepresentation(rep)
            return result
        }
        func save(_ image: NSImage, _ name: String) throws -> String {
            let url = folder.appendingPathComponent(name)
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try rep.representation(using: .png, properties: [:])!.write(to: url)
            return url.path
        }
        func channels(_ image: NSImage?) -> (Double, Double) {
            let rep = NSBitmapImageRep(data: image!.tiffRepresentation!)!
            let color = rep.colorAt(x: 16, y: 16)!.usingColorSpace(.deviceRGB)!
            return (color.redComponent, color.blueComponent)
        }
        let settings = UpscaleSettings()
        settings.primary.sharpenStrength.text = "4.0"
        settings.primary.sharpenMethod = "unsharp"
        precondition(settings.primary.sharpenStrength.text == "4.00", "method validation must use incoming unsharp range")
        settings.secondary.sharpenStrength.text = "4.0"
        settings.secondary.sharpenMethod = "unsharp"
        precondition(settings.secondary.sharpenStrength.text == "4.00", "second method must use its own incoming range")
        settings.secondary.sharpenMethod = "cas"
        precondition(settings.secondary.sharpenStrength.text == "1.00", "CAS must clamp second strength")
        settings.primary.useDenoise = !(true)
        settings.primary.useSharpen = !(true)
        settings.color.noEq = true
        settings.secondary.useDering = true
        precondition(settings.secondary.useDering, "legacy dering alias must share one authority")
        settings.secondary.useDering = false
        precondition(!settings.secondary.useDering, "legacy alias must update authoritative state")
        settings.secondary.useSharpen = true
        settings.primary.useSharpen = !(false)
        settings.primary.sharpenMethod = "cas"
        settings.primary.sharpenStrength.text = "0.5"
        settings.secondary.sharpenMethod = "unsharp"
        settings.secondary.usmRadius.text = "7"
        precondition(Int(String(Int(UpscaleSettings.unsharpMatrixSize(settings.secondary.usmRadius.text))))! % 2 == 1, "Unsharp requires an odd matrix size")
        for value in ["nan", "inf", "1e300"] {
            settings.secondary.usmRadius.text = value
            precondition(["3", "23"].contains(String(Int(UpscaleSettings.unsharpMatrixSize(settings.secondary.usmRadius.text)))), "invalid radius must not trap")
        }
        settings.secondary.debandMethod = "gradfun"
        precondition(Double(settings.secondary.debandStrength.text)! >= 0.51)
        settings.secondary.debandMethod = "deband"
        precondition(Double(settings.secondary.debandStrength.text)! <= 0.1)
        settings.upscaling.scaler = "coreml"
        precondition(!settings.makePreviewFilterParameters().useSharpen2, "Core ML does not export finishing filters")
        settings.upscaling.scaler = "lanczos"
        settings.primary.useSharpen = !(true)
        settings.secondary.useSharpen = false
        settings.secondary.denoiseStrength.text = "auto"
        settings.secondary.useDenoise = true
        settings.primary.useDenoise = !(false)
        precondition(settings.secondary.denoiseStrength.text == "auto",
                     "auto denoise remains an explicit draft")
        settings.secondary.useDenoise = false
        settings.primary.useDenoise = !(true)
        let editor = EditorState(settings: settings)
        let red = try save(image(220, 10), "red.png")
        let blue = try save(image(10, 220), "blue.png")
        let disguised = try save(image(220, 10), "image.mp4")
        for path in [red, blue, disguised] {
            let url = URL(fileURLWithPath: path)
            precondition(!VideoInput.acceptsSelection(url), "import must reject images, including renamed files")
            editor.filePath = path
            precondition(editor.videoAsset == nil && editor.originalThumbnail == nil && editor.timelineFrames.isEmpty)
        }
        precondition(VideoInput.acceptsSelection(folder), "batch folders remain selectable")
        for name in ["video.MP4", "video.mov", "video.mkv", "video.m4v"] {
            precondition(VideoInput.hasVideoExtension(folder.appendingPathComponent(name)))
        }
        // Preview tests inject decoded video frames; image-file import is unsupported.
        editor.installOriginal(image(220, 10))
        try await Task.sleep(nanoseconds: 400_000_000)
        let first = channels(editor.thumbnailImage)
        precondition(first.0 > first.1, "first preview should be red")
        editor.installOriginal(image(10, 220))
        editor.applyFilters()
        try await Task.sleep(nanoseconds: 400_000_000)
        let second = channels(editor.thumbnailImage)
        precondition(second.1 > second.0, "cache must not return the previous image")
        let original = channels(editor.originalThumbnail)
        precondition(abs(second.0 - original.0) < 0.01 && abs(second.1 - original.1) < 0.01,
            "disabled first filters must leave preview colors unchanged")
        for i in 0..<100 { settings.color.eqBrightness.text = String(Double(i) / 1000) }
        editor.reset()
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(editor.thumbnailImage == nil, "old queued renders must not repopulate reset state")
        precondition(EditorState.cacheCost(bytesPerRow: 128, height: 32) == 4096)
        precondition(EditorState.cacheCost(bytesPerRow: Int.max, height: 2) == Int.max)
        precondition(EditorState.cacheCost(bytesPerRow: -1, height: 2) == 0)
        let probe = RenderProbe()
        let observed = UpscaleSettings()
        observed.primary.useDenoise = false
        observed.primary.useSharpen = false
        observed.color.noEq = false
        let coalesced = EditorState(settings: observed, previewRenderer: { input, params, _ in
            probe.record(params)
            return input
        })
        func settle() async throws { try await Task.sleep(nanoseconds: 200_000_000) }
        coalesced.installOriginal(image(220, 10))
        try await settle()
        precondition(probe.count == 1)
        for i in 0..<100 { observed.color.eqBrightness.text = String(Double(i) / 1000) }
        try await settle()
        precondition(probe.count == 2 && abs(probe.last!.brightness - 0.099) < 0.0001,
                     "burst must render the post-mutation final snapshot once")
        observed.color.noEq = true
        try await settle()
        let inactiveCount = probe.count
        observed.color.eqBrightness.text = "0.02"
        observed.primary.usmThreshold.text = "0.5"
        observed.secondary.denoiseStrength.text = "3"
        try await settle()
        precondition(probe.count == inactiveCount, "inactive and unimplemented parameters must not render")
        observed.primary.useDenoise = true
        observed.primary.denoiseStrength.text = "2"
        observed.secondary.useDenoise = true
        observed.secondary.denoiseStrength.text = "2"
        try await settle()
        precondition(probe.last!.denoiseStrength2 == 2,
                     "preview must use the entered finishing strength with both stages enabled")
        observed.primary.useDenoise = false
        try await settle()
        precondition(probe.last!.noDenoise && probe.last!.denoiseStrength2 == 2,
                     "primary toggle must not alter finishing strength")
        coalesced.setProcessingFullUpscale(true)
        let pausedCount = probe.count
        observed.color.noEq = false
        for i in 0..<50 { observed.color.eqBrightness.text = String(Double(i) / 1000) }
        try await settle()
        precondition(probe.count == pausedCount, "paused preview must not render")
        coalesced.setProcessingFullUpscale(false)
        coalesced.setProcessingFullUpscale(false)
        try await settle()
        precondition(probe.count == pausedCount + 1 && abs(probe.last!.brightness - 0.049) < 0.0001,
                     "resume must render only the latest snapshot once")
        let blocked = RenderProbe(blockFirst: true)
        let stale = EditorState(settings: observed, previewRenderer: { input, params, _ in
            blocked.record(params)
            return input
        })
        stale.installOriginal(image(220, 10))
        try await settle()
        precondition(blocked.count == 1)
        stale.reset()
        blocked.release()
        try await settle()
        precondition(stale.thumbnailImage == nil, "reset must reject an in-flight worker")
        stale.installOriginal(image(10, 220))
        try await settle()
        precondition(channels(stale.thumbnailImage).1 > channels(stale.thumbnailImage).0,
                     "media identity must reject old cache entries")
        let blockedLatest = RenderProbe(blockFirst: true)
        let latest = EditorState(settings: observed, previewRenderer: { input, params, _ in
            blockedLatest.record(params)
            return input
        })
        latest.installOriginal(image(220, 10))
        try await settle()
        for i in 0..<80 { observed.color.eqBrightness.text = String(Double(i) / 1000) }
        try await settle()
        blockedLatest.release()
        try await settle()
        precondition(blockedLatest.count == 2 && abs(blockedLatest.last!.brightness - 0.079) < 0.0001,
                     "busy renderer must process only the latest pending snapshot")
        let key = PreviewRequestKey(frameGeneration: UUID(), parameters: observed.makePreviewFilterParameters())
        precondition(PreviewCacheKey(key) == PreviewCacheKey(key), "typed cache equality must compare values")
        print("PASS preview snapshots, burst coalescing, inactive equality, independent finishing strengths, pause/resume, stale media, cache cost")
    }
}

nonisolated private final class RenderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PreviewFilterParameters] = []
    private let semaphore = DispatchSemaphore(value: 0)
    private let blockFirst: Bool
    init(blockFirst: Bool = false) { self.blockFirst = blockFirst }
    func record(_ value: PreviewFilterParameters) {
        lock.lock()
        values.append(value)
        let first = values.count == 1
        lock.unlock()
        if blockFirst && first { semaphore.wait() }
    }
    func release() { semaphore.signal() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
    var last: PreviewFilterParameters? { lock.lock(); defer { lock.unlock() }; return values.last }
}
