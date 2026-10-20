import Foundation

nonisolated extension Up60PEngineError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidOptions: return "Invalid processing options. Check scale, frame rate, codec and filter values."
        case .engineUnavailable: return "The media engine is missing from this app. Reinstall the app."
        case .unsupportedMedia: return "This file's format is not supported by the Rust engine."
        case .io: return "Unable to read the input or write the output. Check paths, permissions and encoder support."
        case .internalError: return "The processing engine failed. See the diagnostic log for context."
        case .notInitialized: return "The processing engine is not initialized."
        case .unsupportedScaler: return "This upscaling mode is unsupported. Choose Lanczos or an included Core ML model."
        case .unknownStatus(let code): return "Processing failed with status \(code)."
        }
    }
}

nonisolated extension ModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "ML model is not included in this app."
        case .invalidModel: return "ML model returned incompatible tensor."
        case .compilationFailed(let error), .fileSystemError(let error): return error.localizedDescription
        }
    }
}

nonisolated extension VideoIOError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Imported video type is not supported."
        case .failed: return "Rendering stopped before completion."
        case .frameAlreadyFrozen: return "Frame has been finalized."
        }
    }
}
