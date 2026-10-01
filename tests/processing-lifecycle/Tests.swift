import Foundation
import CoreVideo
import CoreML
import CoreGraphics

@MainActor final class SuspendedEngine: EngineProtocol {
    var starts = 0
    var cancels = 0
    var handler: ((String) -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        starts += 1
        handler?("elapsed=1\n")
        await withCheckedContinuation { continuation = $0 }
    }
    func cancel() { cancels += 1 }
    func finish() { continuation?.resume(); continuation = nil }
}
struct NoDuration: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double { 0 }
}

@main struct ProcessingTests {
    nonisolated static func testGeometryAndTensor() throws {
        try testTileCoverageAndOrientation()
        for native in [2.0, 4.0, 8.0] {
            for requested in [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 8.0] {
                for (width, height) in [(1920, 1080), (127, 73)] {
                    let plan = try UpscaleGeometry(inputWidth: width, inputHeight: height,
                        requestedScale: requested, nativeScale: native, tileWidth: 64, tileHeight: 64)
                    precondition(plan.outputWidth == Int(Double(width) * requested / 2) * 2)
                    precondition(plan.outputHeight == Int(Double(height) * requested / 2) * 2)
                    precondition(plan.nativeTileWidth == 64 * Int(native))
                    precondition(plan.requiresResampling == (requested != native))
                }
            }
        }
        for scale in [0.0, -1.0, Double.nan, Double.infinity] {
            do {
                _ = try UpscaleGeometry(inputWidth: 100, inputHeight: 100, requestedScale: scale,
                    nativeScale: 4, tileWidth: 64, tileHeight: 64)
                fatalError("invalid scale accepted")
            } catch Up60PEngineError.invalidOptions {}
        }
        // A padded/strided output tensor must produce the same RGB values.
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: 32)
        storage.initialize(repeating: -99, count: 32)
        defer { storage.deallocate() }
        let tensor = try MLMultiArray(dataPointer: storage, shape: [1, 3, 2, 2], dataType: .float32,
            strides: [32, 10, 4, 1], deallocator: nil)
        for channel in 0..<3 {
            for y in 0..<2 { for x in 0..<2 { storage[channel * 10 + y * 4 + x] = Float(channel + 1) / 4 } }
        }
        let engine = CoreMLProcessingJob()
        let pixels = try engine.tensorToPixelBuffer(tensor: tensor, width: 2, height: 2)
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let bytes = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
        precondition(bytes[0] == 191 && bytes[1] == 127 && bytes[2] == 63 && bytes[3] == 255)
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        storage[0] = .nan
        do { _ = try engine.tensorToPixelBuffer(tensor: tensor, width: 2, height: 2); fatalError("NaN output accepted") }
        catch ModelError.invalidModel {}
        // Cropped tiles must resize only the valid native region, excluding padding.
        var nativeTile: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32BGRA, nil, &nativeTile) == kCVReturnSuccess)
        CVPixelBufferLockBaseAddress(nativeTile!, [])
        let rowBytes = CVPixelBufferGetBytesPerRow(nativeTile!)
        let base = CVPixelBufferGetBaseAddress(nativeTile!)!
        memset(base, 0, rowBytes * 8)
        for row in 0..<4 { memset(base + row * rowBytes, 255, 4 * 4) }
        CVPixelBufferUnlockBaseAddress(nativeTile!, [])
        let resized = try engine.resizePixelBuffer(nativeTile!, width: 2, height: 2, sourceWidth: 4, sourceHeight: 4)
        CVPixelBufferLockBaseAddress(resized, .readOnly)
        let resizedBytes = CVPixelBufferGetBaseAddress(resized)!.assumingMemoryBound(to: UInt8.self)
        precondition(resizedBytes[0] == 255 && resizedBytes[4] == 255, "tile padding contaminated resized pixels")
        CVPixelBufferUnlockBaseAddress(resized, .readOnly)
        print("PASS: native/requested scale matrix, fractional/even dimensions, invalid scale, strided/NaN tensor, cropped resampling")
    }

    nonisolated static func testTileCoverageAndOrientation() throws {
        for (width, height) in [(640, 480), (259, 257), (127, 73), (16, 16)] {
            for scale in [0.25, 0.5, 1.0, 1.3, 1.5, 2.0, 4.0] {
                let tile = 256, overlap = 16
                let plan = try UpscaleGeometry(inputWidth: width, inputHeight: height,
                    requestedScale: scale, nativeScale: 4, tileWidth: tile, tileHeight: tile)
                let columns = max(1, Int(ceil(Double(width - overlap) / Double(tile - overlap))))
                let rows = max(1, Int(ceil(Double(height - overlap) / Double(tile - overlap))))
                var coverage = Array(repeating: false, count: plan.outputWidth * plan.outputHeight)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = min(column * (tile - overlap), max(0, width - tile))
                        let y = min(row * (tile - overlap), max(0, height - tile))
                        let region = plan.outputRegion(x: x, y: y, width: min(tile, width - x), height: min(tile, height - y))
                        precondition(region.width >= 0 && region.height >= 0)
                        precondition(region.x + region.width <= plan.outputWidth && region.y + region.height <= plan.outputHeight)
                        for outY in region.y..<(region.y + region.height) {
                            for outX in region.x..<(region.x + region.width) {
                                coverage[outY * plan.outputWidth + outX] = true
                            }
                        }
                    }
                }
                precondition(coverage.allSatisfy { $0 }, "Uncovered pixel for \(width)x\(height) at \(scale)x")
                let transforms: [CGAffineTransform] = [
                    .identity,
                    .init(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0),
                    .init(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(width), ty: CGFloat(height)),
                    .init(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width)),
                    .init(a: -1, b: 0, c: 0, d: 1, tx: CGFloat(width), ty: 0)
                ]
                for source in transforms {
                    let output = plan.outputTransform(for: source)
                    precondition(output.a == source.a && output.b == source.b && output.c == source.c && output.d == source.d)
                    let bounds = CGRect(x: 0, y: 0, width: plan.outputWidth, height: plan.outputHeight).applying(output)
                    precondition(bounds.minX == 0 && bounds.minY == 0)
                    precondition(bounds.width == CGFloat(source.a == 0 ? plan.outputHeight : plan.outputWidth))
                    precondition(bounds.height == CGFloat(source.a == 0 ? plan.outputWidth : plan.outputHeight))
                }
                precondition(plan.outputTransform(for: .identity) == .identity)
            }
        }
        let plan = try UpscaleGeometry(inputWidth: 640, inputHeight: 480,
            requestedScale: 1.3, nativeScale: 4, tileWidth: 256, tileHeight: 256)
        let last = plan.outputRegion(x: 384, y: 224, width: 256, height: 256)
        precondition(last.x == 499 && last.width == 333 && last.x + last.width == 832)
        let translated = plan.outputTransform(for: .init(translationX: 10, y: -20))
        precondition(translated.tx == 13 && translated.ty == -26)
        print("PASS: complete fractional tile coverage, cropped edges, even rounding, identity/90/180/270/mirror orientation and translated display origin")
    }

    nonisolated static func testBlend() throws {
        let size = 512
        func buffer() -> CVPixelBuffer {
            var result: CVPixelBuffer?
            precondition(CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess)
            let buffer = result!
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 127, CVPixelBufferGetBytesPerRow(buffer) * size)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return buffer
        }
        let source = buffer(), legacy = buffer(), current = buffer()
        let weights = UnsafeMutablePointer<Float>.allocate(capacity: size * size)
        weights.initialize(repeating: 0, count: size * size)
        defer { weights.deallocate() }
        let engine = CoreMLProcessingJob()
        func run(_ old: Bool, _ cosine: Bool) throws {
            weights.update(repeating: 0, count: size * size)
            if old {
                try engine.legacyBlendTileIntoCanvas(source: source, target: legacy, weightMap: weights,
                    destX: 0, destY: 0, width: size, height: size, margin: 64, useCosine: cosine,
                    isLeft: false, isRight: false, isTop: false, isBottom: false)
            } else {
                try engine.blendTileIntoCanvas(source: source, target: current, weightMap: weights,
                    destX: 0, destY: 0, width: size, height: size, margin: 64, useCosine: cosine,
                    isLeft: false, isRight: false, isTop: false, isBottom: false)
            }
        }
        for cosine in [false, true] {
            try run(true, cosine); try run(false, cosine)
            CVPixelBufferLockBaseAddress(legacy, .readOnly)
            CVPixelBufferLockBaseAddress(current, .readOnly)
            for row in 0..<size {
                let oldRow = CVPixelBufferGetBaseAddress(legacy)! + row * CVPixelBufferGetBytesPerRow(legacy)
                let newRow = CVPixelBufferGetBaseAddress(current)! + row * CVPixelBufferGetBytesPerRow(current)
                precondition(memcmp(oldRow, newRow, size * 4) == 0, "blend pixels changed")
            }
            CVPixelBufferUnlockBaseAddress(legacy, .readOnly)
            CVPixelBufferUnlockBaseAddress(current, .readOnly)
        }
        func time(_ old: Bool) throws -> Double {
            let start = Date()
            for _ in 0..<40 { try run(old, true) }
            return Date().timeIntervalSince(start)
        }
        let before = try time(true), after = try time(false)
        print("PASS: linear and cosine feather pixel parity")
        print(String(format: "Blend microbenchmark (40 x 512-square tiles): before %.3fs, after %.3fs (%.2fx)", before, after, before / after))
    }

    @MainActor static func main() async throws {
        let measured = FFmpegParser.parse(line: "time=00:00:05.000 fps=10 speed=0.5x", currentDuration: 10)
        precondition(measured.progress == 0.5 && measured.eta == "0:10")
        let unknownETA = FFmpegParser.parse(line: "time=00:00:05 fps=10", currentDuration: 10)
        precondition(unknownETA.eta == "--:--")
        precondition(FFmpegParser.parse(line: "time=5", currentDuration: 0).progress == nil)
        let gate = ProgressUpdateGate()
        precondition(gate.shouldEmit("time=1 fps=20", now: 0))
        precondition(!gate.shouldEmit("time=2 fps=20", now: 0.1))
        precondition(gate.shouldEmit("ERROR: time=2", now: 0.1))
        precondition(gate.shouldEmit("stage=finalizing", now: 0.1))
        precondition(gate.shouldEmit("time=3 fps=20", now: 0.3))
        print("PASS: measured/unknown progress, speed-based ETA, bounded progress events, terminal/error delivery")
        try testGeometryAndTensor()
        try testBlend()
        let control = ProcessingControl()
        try control.begin()
        do { try control.begin(); fatalError("overlapping engine accepted") }
        catch ProcessingControl.Failure.alreadyRunning {}
        let start = Date()
        let waiting = Task {
            try await control.waitUntilReady(isReady: { false }, failure: { nil })
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        control.cancel()
        do { try await waiting.value; fatalError("cancelled wait succeeded") }
        catch is CancellationError {}
        precondition(Date().timeIntervalSince(start) < 1)
        control.finish()
        try control.begin()
        enum WriterFailure: Error { case stopped }
        do {
            try await control.waitUntilReady(isReady: { false }, failure: { WriterFailure.stopped })
            fatalError("failed writer kept waiting")
        } catch WriterFailure.stopped {}
        try await control.waitUntilReady(isReady: { true }, failure: { nil })
        let taskCancelled = Task {
            try await control.waitUntilReady(isReady: { false }, failure: { nil })
        }
        taskCancelled.cancel()
        do { try await taskCancelled.value; fatalError("task cancellation ignored") }
        catch is CancellationError {}
        control.finish()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.mp4")
        try Data([1]).write(to: input)
        let engine = SuspendedEngine()
        let runner = UpscaleRunner(engine: engine, assetLoader: NoDuration())
        runner.inputPath = input.path
        runner.customOutputFolder = root.path
        runner.settings.upscaling.scaler = "lanczos"
        runner.run()
        precondition(runner.phase == .preparing && !runner.progressKnown)
        while engine.continuation == nil { await Task.yield() }
        runner.run()
        precondition(engine.starts == 1, "runner accepted duplicate start")
        // An early elapsed log and a stable file cannot end an active engine.
        try Data([2]).write(to: URL(fileURLWithPath: runner.outputVideoPath))
        try await Task.sleep(nanoseconds: 2_100_000_000)
        precondition(runner.isRunning && runner.progress < 1 && !runner.progressKnown && runner.phase == .finalizing, "early log/file stability faked completion")
        runner.cancel()
        runner.run()
        precondition(runner.isRunning && engine.starts == 1 && engine.cancels == 1,
                     "cancel released ownership before engine stopped")
        engine.finish()
        while runner.isRunning { await Task.yield() }
        precondition(runner.completedOutputPath == nil && runner.progress < 1 && !runner.progressKnown, "cancel marked success")

        runner.run()
        while engine.continuation == nil { await Task.yield() }
        let completionStart = Date()
        engine.finish()
        while runner.isRunning { await Task.yield() }
        let completionTime = Date().timeIntervalSince(completionStart)
        precondition(runner.completedOutputPath != nil && runner.progress == 1 && runner.phase == .idle)
        precondition(completionTime < 0.5, "completion still polls file size")
        let completedPath = runner.completedOutputPath
        runner.inputPath = input.path
        precondition(runner.completedOutputPath == completedPath, "unchanged input invalidated export")
        runner.inputPath = root.appendingPathComponent("next.mp4").path
        precondition(runner.completedOutputPath == nil && runner.progress == 0 && !runner.progressKnown,
                     "new input retained stale export state without a mounted log view")
        print("PASS: input changes invalidate completed export independently of log visibility")
        print("PASS: engine overlap, engine cancellation, task cancellation, writer failure/readiness")
        print("PASS: duplicate run, early completion log, cancel/restart ownership, immediate completion")
        print(String(format: "Completion after engine return: %.4f seconds (old polling minimum: 2.0 seconds)", completionTime))
    }
}
