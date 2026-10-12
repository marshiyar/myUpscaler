import Foundation

nonisolated extension Up60PEngineError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidOptions: return "Invalid processing options. Check scale, frame rate, codec and filter values."
        case .ffmpegNotFound: return "Bundled FFmpeg is missing or invalid. Reinstall the app; external FFmpeg is not supported."
        case .io: return "Unable to read the input or write the output. Check paths, permissions and encoder support."
        case .internalError: return "The processing engine failed. See the diagnostic log for context."
        case .notInitialized: return "The processing engine is not initialized."
        case .unsupportedScaler: return "This FFmpeg upscaling mode is unsupported. Choose Lanczos or an included Core ML model."
        case .unknownStatus(let code): return "Processing failed with status \(code)."
        }
    }
}

nonisolated extension ModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "The selected Core ML model is not included in this app."
        case .invalidModel: return "The Core ML model returned an incompatible tensor or invalid pixels."
        case .compilationFailed(let error), .fileSystemError(let error): return error.localizedDescription
        }
    }
}

nonisolated extension VideoIOError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "The video reader or encoder does not support this configuration."
        case .failed: return "Video reading or encoding stopped before completion."
        }
    }
}
