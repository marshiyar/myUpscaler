import Foundation
import AVFoundation
import CoreML
import VideoToolbox
import CoreVideo
import CoreImage
import Accelerate

// MARK: - Model Manager

nonisolated enum ModelError: Error {
    case compilationFailed(Error)
    case modelNotFound
    case invalidModel
    case fileSystemError(Error)
}

/// Main-thread coordinator publishes only the active run and its immutable settings snapshot.
@MainActor final class CoreMLEngine: EngineProtocol {
    static let shared = CoreMLEngine()
    private var logHandler: @Sendable (String) -> Void = { _ in }
    private var activeRun: (id: UUID, job: CoreMLProcessingJob, control: ProcessingControl)?

    func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) { logHandler = handler }
    func cancel() {
        guard let run = activeRun else { return }
        run.control.cancel()
        Task { await run.job.cancelIO() }
    }
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        guard activeRun == nil else { throw ProcessingControl.Failure.alreadyRunning }
        let configuration = settings.configuration
        let control = ProcessingControl()
        try control.begin()
        let job = CoreMLProcessingJob(control: control, logger: logHandler)
        let id = UUID()
        activeRun = (id, job, control)
        defer { if activeRun?.id == id { activeRun = nil }; control.finish() }
        try await job.process(inputPath: inputPath, configuration: configuration, outputDirectory: outputDirectory)
    }
}
