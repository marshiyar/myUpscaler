import Foundation
import Darwin

@MainActor final class BatchEngine: EngineProtocol {
    var inputs: [String] = []
    var failureAt: Int?
    var held = false
    var continuation: CheckedContinuation<Void, Never>?
    var cancels = 0
    var destinationRace: URL?
    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {}
    func cancel() { cancels += 1 }
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        inputs.append(inputPath)
        if held { await withCheckedContinuation { continuation = $0 } }
        if inputs.count == failureAt { throw BatchPlan.Failure("fixture failure") }
        let input = URL(fileURLWithPath: inputPath)
        let ext = BatchPlan.imageExtensions.contains(input.pathExtension.lowercased()) ? "png" : "mp4"
        let output = URL(fileURLWithPath: outputDirectory).appendingPathComponent(input.deletingPathExtension().lastPathComponent + "_[restored]." + ext)
        try Data([42]).write(to: output)
        if let race = destinationRace { try Data([99]).write(to: race) }
    }
}
struct BatchNoDuration: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double { 0 }
}
@main struct BatchTests {
    @MainActor static func wait(_ job: UpscaleRunner) async throws {
        let deadline = Date().addingTimeInterval(5)
        while job.isRunning {
            guard Date() < deadline else { job.cancel(); throw BatchPlan.Failure("batch wait timed out: " + job.log) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), output = root.appendingPathComponent("output")
        func file(_ relative: String) throws {
            let url = source.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        func reject(_ body: () throws -> Void) throws {
            do { try body(); preconditionFailure("unsafe plan accepted") } catch is BatchPlan.Failure {}
        }
        try file("b.MOV"); try file("nested/a.mp4"); try file("picture.PNG"); try file("misleading.mp4/readme.txt")
        try fm.createSymbolicLink(at: source.appendingPathComponent("linked.mov"), withDestinationURL: source.appendingPathComponent("b.MOV"))
        let plan = try BatchPlan.make(input: source, outputFolder: output, coreML: false)
        precondition(plan.items.count == 3 && plan.items.map { $0.input.lastPathComponent } == ["b.MOV", "a.mp4", "picture.PNG"])
        precondition(plan.items[1].output.path.hasSuffix("source_[restored]/nested/a_[restored].mp4"))
        try reject { _ = try BatchPlan.make(input: source, outputFolder: output, coreML: true) }
        try file("other/a.MOV")
        let duplicates = try BatchPlan.make(input: source, outputFolder: output, coreML: false)
        precondition(duplicates.items.count == 4 && Set(duplicates.items.map { $0.output.path }).count == 4)
        try fm.removeItem(at: source.appendingPathComponent("other"))
        try fm.removeItem(at: source.appendingPathComponent("picture.PNG"))
        let aiPlan = try BatchPlan.make(input: source, outputFolder: output, coreML: true)
        precondition(aiPlan.items.count == 2)
        try file("picture.PNG")
        try file("b.mp4")
        try reject { _ = try BatchPlan.make(input: source, outputFolder: output, coreML: false) }
        try fm.removeItem(at: source.appendingPathComponent("b.mp4"))
        try fm.createDirectory(at: plan.items[0].output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([99]).write(to: plan.items[0].output)
        try reject { _ = try BatchPlan.make(input: source, outputFolder: output, coreML: false) }
        precondition((try? Data(contentsOf: plan.items[0].output)) == Data([99]))
        let staged = plan.outputRoot.appendingPathComponent("staged.mp4")
        try Data([42]).write(to: staged)
        do { try BatchPlan.commit(staged: staged, output: plan.items[0].output); preconditionFailure("exclusive rename overwrote destination") }
        catch let error as NSError { precondition(error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST)) }
        precondition((try? Data(contentsOf: plan.items[0].output)) == Data([99]))
        precondition((try? Data(contentsOf: staged)) == Data([42]))
        try fm.removeItem(at: plan.outputRoot)
        let empty = root.appendingPathComponent("empty")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try reject { _ = try BatchPlan.make(input: empty, outputFolder: output, coreML: false) }
        // Outputs nested under input are excluded from repeat enumeration.
        let nestedPlan = try BatchPlan.make(input: source, outputFolder: source, coreML: false)
        try fm.createDirectory(at: nestedPlan.outputRoot, withIntermediateDirectories: true)
        try Data([1]).write(to: nestedPlan.outputRoot.appendingPathComponent("ignored.mp4"))
        let repeatPlan = try BatchPlan.make(input: source, outputFolder: source, coreML: false)
        precondition(repeatPlan.items.count == 3)
        try fm.removeItem(at: nestedPlan.outputRoot)
        // Existing symlink parents must not redirect writes.
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: plan.outputRoot, withDestinationURL: empty)
        try reject { _ = try BatchPlan.make(input: source, outputFolder: output, coreML: false) }
        try fm.removeItem(at: plan.outputRoot)
        func runner(_ engine: BatchEngine) -> UpscaleRunner {
            let value = UpscaleRunner(engine: engine, assetLoader: BatchNoDuration())
            value.inputPath = source.path; value.customOutputFolder = output.path
            value.settings.upscaling.scaler = "lanczos"
            return value
        }
        let engine = BatchEngine(), job = runner(engine)
        job.run(); job.run()
        try await wait(job)
        precondition(engine.inputs.count == 3 && job.batchCompleted == 3 && job.progress == 1)
        precondition(job.completedOutputPath == plan.outputRoot.path)
        for item in plan.items { precondition((try? Data(contentsOf: item.output)) == Data([42])) }
        try fm.removeItem(at: plan.outputRoot)
        let failed = BatchEngine(); failed.failureAt = 2
        let failedJob = runner(failed); failedJob.run()
        try await wait(failedJob)
        precondition(failed.inputs.count == 2 && failedJob.batchCompleted == 1 && failedJob.completedOutputPath == nil)
        precondition(fm.fileExists(atPath: plan.items[0].output.path) && !fm.fileExists(atPath: plan.items[1].output.path))
        try fm.removeItem(at: plan.outputRoot)
        let racing = BatchEngine(); racing.destinationRace = plan.items[0].output
        let raceJob = runner(racing); raceJob.run()
        try await wait(raceJob)
        precondition(raceJob.batchCompleted == 0 && racing.inputs.count == 1)
        precondition((try? Data(contentsOf: plan.items[0].output)) == Data([99]))
        try fm.removeItem(at: plan.outputRoot)
        let held = BatchEngine(); held.held = true
        let cancelled = runner(held); cancelled.run()
        let deadline = Date().addingTimeInterval(5)
        while held.continuation == nil {
            guard cancelled.isRunning, Date() < deadline else { throw BatchPlan.Failure("held engine never started: " + cancelled.log) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        cancelled.cancel(); cancelled.run()
        precondition(cancelled.isRunning && held.cancels == 1 && held.inputs.count == 1)
        held.continuation?.resume(); held.continuation = nil
        try await wait(cancelled)
        precondition(cancelled.batchCompleted == 0 && cancelled.completedOutputPath == nil)
        let leftovers = (try? fm.subpathsOfDirectory(atPath: output.path)) ?? []
        precondition(!leftovers.contains { $0.contains(".myUpscaler-batch-") || $0.hasSuffix(".mp4") })
        print("PASS folder plan: sorted uppercase/nested media, images, collisions, existing/racing outputs, symlinks, empty/excluded folders")
        print("PASS folder runner: per-file validation, duplicate-run ownership, stop-on-failure, partial results, cancellation and temporary cleanup")
    }
}
