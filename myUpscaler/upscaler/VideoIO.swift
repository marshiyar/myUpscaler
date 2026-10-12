import AVFoundation
import CoreVideo

nonisolated enum VideoIOError: Error {
    case invalidConfiguration
    case failed
}

/// One consumer owns each reader. The provider suspends rather than blocking the worker.
nonisolated final class VideoFrameReader {
    private let reader: AVAssetReader
    private let readNext: () async throws -> CMSampleBuffer?
    private let checkCancellation: () throws -> Void

    init(asset: AVAsset, track: AVAssetTrack, forceLegacy: Bool = false,
         checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() }) throws {
        self.checkCancellation = checkCancellation
        let reader = try AVAssetReader(asset: asset)
        self.reader = reader
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        if #available(macOS 26.0, *), !forceLegacy {
            let provider = reader.outputProvider(for: output)
            readNext = {
                try await provider.next()?.withUnsafeSampleBuffer { $0 }
            }
            try reader.start()
        } else {
            guard reader.canAdd(output) else { throw VideoIOError.invalidConfiguration }
            reader.add(output)
            readNext = { output.copyNextSampleBuffer() }
            guard reader.startReading() else { throw reader.error ?? VideoIOError.failed }
        }
    }

    func next() async throws -> CMSampleBuffer? {
        try checkCancellation()
        let sample = try await readNext()
        try checkCancellation()
        if sample == nil, reader.status != .completed {
            throw reader.error ?? VideoIOError.failed
        }
        return sample
    }

    func cancel() { reader.cancelReading() }
    deinit { if reader.status == .reading { reader.cancelReading() } }
}

/// Bounded encoder backpressure with a reusable pixel buffer pool on every OS.
nonisolated final class VideoFrameWriter {
    private let writer: AVAssetWriter
    private let allocate: () throws -> CVPixelBuffer
    private let write: (CVPixelBuffer, CMTime) async throws -> Void
    private let endInput: () -> Void
    private let checkCancellation: () throws -> Void

    init(outputURL: URL, videoSettings: [String: Any], width: Int, height: Int,
         transform: CGAffineTransform = .identity, forceLegacy: Bool = false,
         checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() }) throws {
        self.checkCancellation = checkCancellation
        guard width > 0, height > 0 else { throw VideoIOError.invalidConfiguration }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.writer = writer
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        if #available(macOS 26.0, *), !forceLegacy {
            let attributes = CVPixelBufferCreationAttributes(
                pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                size: .init(width: width, height: height), compatibility: [.metalTexture])
            let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
            allocate = {
                guard let pool = receiver.pixelBufferPool else { throw VideoIOError.failed }
                return try pool.makeMutablePixelBuffer().withUnsafeBuffer { $0 }
            }
            write = { buffer, time in
                // Processing has finished before this immutable encoder view is created.
                try await receiver.append(CVReadOnlyPixelBuffer(unsafeBuffer: buffer), with: time)
            }
            endInput = { receiver.finish() }
            try writer.start()
        } else {
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
            guard writer.canAdd(input) else { throw VideoIOError.invalidConfiguration }
            writer.add(input)
            allocate = {
                guard let pool = adaptor.pixelBufferPool else { throw VideoIOError.failed }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw VideoIOError.failed }
                return buffer
            }
            write = { buffer, time in
                while !input.isReadyForMoreMediaData {
                    try checkCancellation()
                    guard writer.status == .writing else { throw writer.error ?? VideoIOError.failed }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw writer.error ?? VideoIOError.failed
                }
            }
            endInput = { input.markAsFinished() }
            guard writer.startWriting() else { throw writer.error ?? VideoIOError.failed }
        }
        writer.startSession(atSourceTime: .zero)
    }

    func makePixelBuffer() throws -> CVPixelBuffer { try allocate() }
    func append(_ buffer: CVPixelBuffer, at time: CMTime) async throws {
        try checkCancellation()
        guard writer.status == .writing else { throw writer.error ?? VideoIOError.failed }
        try await write(buffer, time)
        try checkCancellation()
    }
    func finish() async throws {
        try checkCancellation()
        endInput()
        await writer.finishWriting()
        try checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? VideoIOError.failed }
    }
    func cancel() { writer.cancelWriting() }
    deinit { if writer.status == .writing { writer.cancelWriting() } }
}
