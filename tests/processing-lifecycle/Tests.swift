import Foundation
import CoreVideo
import CoreML

@MainActor final class SuspendedEngine: EngineProtocol {
    var starts = 0
    var cancels = 0
    var handler: ((String) -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func setLogHandler(_ handler: @escaping (String) -> Void) { self.handler = handler }
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

enum LifecycleTestFailure: Error { case timeout(String) }

@main struct ProcessingTests {
    nonisolated static func testGeometryAndTensor() throws {
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
        let engine = CoreMLEngine()
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

    nonisolated static func testBlend() throws {
        let size = 8
        func buffer(_ b: UInt8, _ g: UInt8, _ r: UInt8) throws -> CVPixelBuffer {
            var result: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess,
                  let buffer = result else { throw ModelError.invalidModel }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<size { for x in 0..<size {
                let i = y * stride + x * 4
                bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = 255
            } }
            return buffer
        }
        let source = try buffer(20, 80, 140)
        let weights = UnsafeMutablePointer<Float>.allocate(capacity: size * size)
        weights.initialize(repeating: 1, count: size * size)
        defer { weights.deinitialize(count: size * size); weights.deallocate() }
        let engine = CoreMLEngine()
        // Fixed expected samples exercise actual feather weights and a nonuniform
        // source/canvas mixture, without retaining another blend implementation.
        let linear: [(Int, Float, [UInt8])] = [
            (0, 0, [200, 40, 10, 255]), (1, 0.0625, [189, 42, 17, 255]),
            (2, 0.25, [164, 48, 36, 255]), (3, 0.5625, [135, 54, 56, 255]),
            (4, 1, [110, 60, 75, 255]), (7, 0.0625, [189, 42, 17, 255])]
        let cosine: [(Int, Float, [UInt8])] = [
            (0, 0, [200, 40, 10, 255]), (1, 0.02144661, [196, 40, 12, 255]),
            (2, 0.25, [164, 48, 36, 255]), (3, 0.7285534, [124, 56, 64, 255]),
            (4, 1, [110, 60, 75, 255]), (7, 0.02144661, [196, 40, 12, 255])]
        for (useCosine, samples) in [(false, linear), (true, cosine)] {
            let canvas = try buffer(200, 40, 10)
            weights.update(repeating: 1, count: size * size)
            try engine.blendTileIntoCanvas(source: source, target: canvas, weightMap: weights,
                destX: 0, destY: 0, width: size, height: size, margin: 4, useCosine: useCosine,
                isLeft: false, isRight: false, isTop: false, isBottom: false)
            CVPixelBufferLockBaseAddress(canvas, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(canvas)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(canvas)
            for (position, weight, expected) in samples {
                precondition(abs(weights[position * size + position] - (1 + weight)) < 0.000001,
                             "incorrect feather contribution")
                for channel in 0..<4 {
                    let actual = bytes[position * stride + position * 4 + channel]
                    // Float cosine and integer truncation can differ by one RGB LSB.
                    let tolerance = channel == 3 ? 0 : 1
                    precondition(abs(Int(actual) - Int(expected[channel])) <= tolerance,
                                 "incorrect weighted BGRA sample")
                }
            }
            CVPixelBufferUnlockBaseAddress(canvas, .readOnly)
        }
        let boundary = try buffer(200, 40, 10)
        weights.update(repeating: 1, count: size * size)
        try engine.blendTileIntoCanvas(source: source, target: boundary, weightMap: weights,
            destX: 0, destY: 0, width: size, height: size, margin: 4, useCosine: true,
            isLeft: true, isRight: true, isTop: true, isBottom: true)
        precondition(weights[0] == 2 && weights[size * size - 1] == 2,
                     "image-boundary pixels must receive full weight")
        print("PASS: fixed linear/cosine feather weights, mixed BGRA pixels and image boundaries")
    }

    @MainActor static func eventually(_ message: String, _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition() {
            guard clock.now < deadline else { throw LifecycleTestFailure.timeout(message) }
            await Task.yield()
        }
    }

    nonisolated static func awaitReadiness(_ stream: AsyncStream<Void>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in stream { return }
                throw LifecycleTestFailure.timeout("readiness signal ended")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw LifecycleTestFailure.timeout("readiness was never checked")
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
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
        let (readiness, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let waiting = Task {
            try await control.waitUntilReady(isReady: { signal.yield(()); return false }, failure: { nil })
        }
        try await awaitReadiness(readiness)
        control.cancel()
        do { try await waiting.value; fatalError("cancelled wait succeeded") }
        catch is CancellationError {}
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
        runner.settings.scaler = "lanczos"
        runner.run()
        precondition(runner.phase == .preparing && !runner.progressKnown)
        try await eventually("engine did not enter processing") { engine.continuation != nil }
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
        try await eventually("runner did not finish after engine return") { !runner.isRunning }
        precondition(runner.completedOutputPath == nil && runner.progress < 1 && !runner.progressKnown, "cancel marked success")

        runner.run()
        try await eventually("engine did not enter processing") { engine.continuation != nil }
        engine.finish()
        try await eventually("runner did not finish after engine return") { !runner.isRunning }
        precondition(runner.completedOutputPath != nil && runner.progress == 1 && runner.phase == .idle)
        print("PASS: engine overlap, engine cancellation, task cancellation, writer failure/readiness")
        print("PASS: duplicate run, early completion log, cancel/restart ownership, immediate completion")
    }
}
