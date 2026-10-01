import CoreVideo

extension ProcessingTests {
    nonisolated static func testBufferAccessValidation() throws {
        func invalid(_ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Invalid buffer geometry was accepted") }
            catch Up60PEngineError.invalidOptions {}
            catch { preconditionFailure("Unexpected error: \(error)") }
        }
        for (width, height) in [(0, 1), (1, 0), (-1, 1), (Int.max, 2)] {
            invalid { _ = try CoreMLBufferAccess.pixelCount(width: width, height: height) }
        }
        var pixelBuffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess)
        let buffer = pixelBuffer!
        // Failure injection verifies no false-success image and no unmatched unlock.
        var unlocks = 0
        do {
            _ = try CoreMLBufferAccess.lock(buffer, flags: .readOnly,
                lockBaseAddress: { _, _ in kCVReturnInvalidArgument },
                unlockBaseAddress: { _, _ in unlocks += 1; return kCVReturnSuccess })
            preconditionFailure("Failed lock accepted")
        } catch Up60PEngineError.internalError {}
        precondition(unlocks == 0)
        do {
            _ = try CoreMLBufferAccess.lock(buffer, flags: .readOnly,
                lockBaseAddress: { _, _ in kCVReturnSuccess },
                unlockBaseAddress: { _, flags in precondition(flags == .readOnly); unlocks += 1; return kCVReturnSuccess },
                baseAddress: { _ in nil })
            preconditionFailure("Missing base address accepted")
        } catch Up60PEngineError.internalError {}
        precondition(unlocks == 1)
        try CoreMLBufferAccess.validateRegion(x: 7, y: 7, width: 1, height: 1, buffer: buffer)
        for (x, y, width, height) in [(-1, 0, 1, 1), (0, -1, 1, 1), (7, 0, 2, 1), (0, 7, 1, 2), (Int.max, 0, 1, 1), (0, 0, Int.max, 1)] {
            invalid { try CoreMLBufferAccess.validateRegion(x: x, y: y, width: width, height: height, buffer: buffer) }
        }
        var unsupported: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_OneComponent8, nil, &unsupported) == kCVReturnSuccess)
        invalid { _ = try CoreMLBufferAccess.lock(unsupported!, flags: .readOnly) }
        let engine = CoreMLProcessingJob()
        invalid { _ = try engine.resizePixelBuffer(buffer, width: 4, height: 4, sourceWidth: -1, sourceHeight: 8) }
        invalid { _ = try engine.resizePixelBuffer(buffer, width: 4, height: 4, sourceWidth: 9, sourceHeight: 8) }
        let weights = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        weights.initialize(repeating: 0, count: 64)
        defer { weights.deallocate() }
        invalid { try engine.blendTileIntoCanvas(source: buffer, target: buffer, weightMap: weights,
            destX: -1, destY: 0, width: 8, height: 8, margin: 0, useCosine: false,
            isLeft: true, isRight: true, isTop: true, isBottom: true) }
        invalid { try engine.blendTileIntoCanvas(source: buffer, target: buffer, weightMap: weights,
            destX: 0, destY: 0, width: 9, height: 8, margin: 0, useCosine: false,
            isLeft: true, isRight: true, isTop: true, isBottom: true) }
        print("PASS: BGRA contract, region/overflow guards, invalid source crop and negative blend destination")
    }
}
