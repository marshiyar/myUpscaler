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
        settings.sharpenStrength = "4.0"
        settings.sharpenMethod = "unsharp"
        precondition(settings.sharpenStrength == "4.00", "method validation must use incoming unsharp range")
        settings.sharpenStrength2 = "4.0"
        settings.sharpenMethod2 = "unsharp"
        precondition(settings.sharpenStrength2 == "4.00", "second method must use its own incoming range")
        settings.sharpenMethod2 = "cas"
        precondition(settings.sharpenStrength2 == "1.00", "CAS must clamp second strength")
        settings.noDenoise = true
        settings.noSharpen = true
        settings.noEq = true
        let editor = EditorState(settings: settings)
        var publications = 0
        let subscription = editor.$contrast.dropFirst().sink { _ in publications += 1 }
        editor.syncFromSettings(settings)
        precondition(publications == 0, "unchanged settings must not publish")
        let red = try save(image(220, 10), "red.png")
        let blue = try save(image(10, 220), "blue.png")
        editor.loadThumbnail(red)
        try await Task.sleep(nanoseconds: 400_000_000)
        let first = channels(editor.thumbnailImage)
        precondition(first.0 > first.1, "first preview should be red")
        editor.loadThumbnail(blue)
        editor.applyFilters()
        try await Task.sleep(nanoseconds: 400_000_000)
        let second = channels(editor.thumbnailImage)
        precondition(second.1 > second.0, "cache must not return the previous image")
        let original = channels(editor.originalThumbnail)
        precondition(abs(second.0 - original.0) < 0.01 && abs(second.1 - original.1) < 0.01,
            "disabled first filters must leave preview colors unchanged")
        for i in 0..<100 { editor.brightness = Double(i) / 1000; editor.applyFilters() }
        editor.reset()
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(editor.thumbnailImage == nil, "old queued renders must not repopulate reset state")
        withExtendedLifetime(subscription) {}
        print("PASS unchanged settings, input cache identity, latest-render/reset ownership")
    }
}
