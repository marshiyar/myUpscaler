import Foundation

@MainActor final class CoreMLEngine: EngineProtocol {
    static let shared = CoreMLEngine()
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        preconditionFailure("This test never selects CoreML")
    }
    func cancel() {}
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {}
}
@MainActor final class BoundaryEngine: EngineProtocol {
    var hasCommittedOutput = false
    var continuation: CheckedContinuation<Void, Error>?
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        hasCommittedOutput = false
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func cancel() {
        if hasCommittedOutput { continuation?.resume() }
        else { continuation?.resume(throwing: CancellationError()) }
        continuation = nil
    }
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {}
}
struct ZeroDuration: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double { 0 }
}
@main struct Tests {
    @MainActor static func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Timed out waiting for runner")
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.png")
        try Data([1]).write(to: input)
        let engine = BoundaryEngine()
        let runner = UpscaleRunner(engine: engine, assetLoader: ZeroDuration())
        runner.inputPath = input.path; runner.customOutputFolder = root.path
        runner.settings.upscaling.scaler = "lanczos"
        let destination = URL(fileURLWithPath: runner.outputVideoPath)
        let previous = Data([9, 9]); try previous.write(to: destination)

        runner.run(); try await waitFor { engine.continuation != nil }
        runner.cancel(); try await waitFor { !runner.isRunning }
        precondition(runner.completedOutputPath == nil)
        let before = try Data(contentsOf: destination); precondition(before == previous)
        print("PASS: precommit cancellation stays cancelled and preserves destination")

        runner.run(); try await waitFor { engine.continuation != nil }
        try Data([2, 3]).write(to: destination)
        engine.hasCommittedOutput = true
        // Cancellation clears expectedOutputPath and cancels the real runner
        // task before the engine resumes with its explicit committed outcome.
        runner.cancel(); try await waitFor { !runner.isRunning }
        precondition(runner.completedOutputPath == destination.path)
        precondition(runner.progress == 1 && runner.progressKnown && !runner.isCancelling)
        precondition(runner.log.contains("Output committed before cancellation took effect."))
        let after = try Data(contentsOf: destination); precondition(after == Data([2, 3]))
        print("PASS: committed success survives runner task cancellation and output-path clearing")
    }
}
