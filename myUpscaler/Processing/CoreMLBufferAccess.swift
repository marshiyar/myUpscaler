import CoreVideo

/// Synchronous CPU access only. Callers unlock immediately with defer and never
/// retain the returned address across suspension or transfer buffer ownership.
nonisolated enum CoreMLBufferAccess {
    static func pixelCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else { throw Up60PEngineError.invalidOptions }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, count <= Int.max / MemoryLayout<Float>.stride else {
            throw Up60PEngineError.invalidOptions
        }
        return count
    }

    static func validateBGRA(_ buffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        _ = try pixelCount(width: width, height: height)
        guard !CVPixelBufferIsPlanar(buffer),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              width <= Int.max / 4 else { throw Up60PEngineError.invalidOptions }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard rowBytes >= width * 4, rowBytes <= Int.max / height else {
            throw Up60PEngineError.invalidOptions
        }
    }

    static func validateRegion(x: Int, y: Int, width: Int, height: Int,
                               buffer: CVPixelBuffer) throws {
        try validateBGRA(buffer)
        let bufferWidth = CVPixelBufferGetWidth(buffer)
        let bufferHeight = CVPixelBufferGetHeight(buffer)
        guard x >= 0, y >= 0, width > 0, height > 0,
              x <= bufferWidth, y <= bufferHeight,
              width <= bufferWidth - x, height <= bufferHeight - y else {
            throw Up60PEngineError.invalidOptions
        }
    }

    static func lock(_ buffer: CVPixelBuffer, flags: CVPixelBufferLockFlags,
                     lockBaseAddress: (CVPixelBuffer, CVPixelBufferLockFlags) -> CVReturn = CVPixelBufferLockBaseAddress,
                     unlockBaseAddress: (CVPixelBuffer, CVPixelBufferLockFlags) -> CVReturn = CVPixelBufferUnlockBaseAddress,
                     baseAddress: (CVPixelBuffer) -> UnsafeMutableRawPointer? = CVPixelBufferGetBaseAddress) throws -> UnsafeMutableRawPointer {
        try validateBGRA(buffer)
        guard lockBaseAddress(buffer, flags) == kCVReturnSuccess else {
            throw Up60PEngineError.internalError
        }
        guard let base = baseAddress(buffer) else {
            _ = unlockBaseAddress(buffer, flags)
            throw Up60PEngineError.internalError
        }
        return base
    }
}
