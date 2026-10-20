import Foundation

// This focused runner test injects a held engine; no GPU/model/process work.
@MainActor final class CoreMLEngine: EngineProtocol {
    static let shared = CoreMLEngine()
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        preconditionFailure("Focused stage test must never select CoreML")
    }
    func cancel() {}
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {}
}
@MainActor final class HeldStageEngine: EngineProtocol {
    var handler: (@Sendable (String) -> Void)?
    var continuation: CheckedContinuation<Void, Never>?
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        await withCheckedContinuation { continuation = $0 }
    }
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    func cancel() { continuation?.resume(); continuation = nil }
}
struct ZeroStageDuration: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double { 0 }
}
@main struct StageTests {
    @MainActor static func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Timed out waiting for runner state")
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.mp4")
        try Data([1]).write(to: input)
        let engine = HeldStageEngine()
        let runner = UpscaleRunner(engine: engine, assetLoader: ZeroStageDuration())
        runner.inputPath = input.path; runner.customOutputFolder = root.path
        runner.settings.upscaling.scaler = "lanczos"
        runner.run()
        try await waitFor { engine.continuation != nil }
        engine.handler?("stage=processing Preparing genuine F3kdb input\n")
        try await waitFor { runner.phase == .processing }
        precondition(!runner.progressKnown && runner.etaString == "--:--")
        engine.handler?("stage=finalizing Encoding and verifying output\n")
        try await waitFor { runner.phase == .finalizing }
        precondition(!runner.progressKnown)
        engine.handler?("stage=processing delayed preparation callback\n")
        for _ in 0..<10 { await Task.yield() }
        precondition(runner.phase == .finalizing && !runner.progressKnown)
        try Data([2]).write(to: URL(fileURLWithPath: runner.outputVideoPath))
        engine.continuation?.resume(); engine.continuation = nil
        try await waitFor { !runner.isRunning }
        let completedPhase = runner.phase
        let completedKnown = runner.progressKnown
        engine.handler?("stage=processing delayed same-run callback\n")
        for _ in 0..<10 { await Task.yield() }
        precondition(runner.phase == completedPhase && runner.progressKnown == completedKnown && runner.progress == 1)
        print("PASS: genuine split stage uses truthful indeterminate processing/finalizing; completed run rejects delayed stage")
    }
}
