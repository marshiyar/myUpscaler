import Foundation

// The runner tests inject their engine. No media engine or model download is needed.
@MainActor final class Up60PEngine {
    static let shared = Up60PEngine()
    static func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {}
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {}
    func cancel() {}
}
enum Up60PEngineError: Error {
    case invalidOptions, engineUnavailable, unsupportedMedia, io, internalError, notInitialized, unsupportedScaler
    case unknownStatus(Int32)
}
