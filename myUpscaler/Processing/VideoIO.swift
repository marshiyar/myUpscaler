import AVFoundation
import CoreVideo

nonisolated enum VideoIOError: Error {
    case invalidConfiguration
    case failed
    case frameAlreadyFrozen
}

/// Decoder metadata and pixels stay owned by this sample; borrow callbacks must
/// finish synchronously and must not retain its raw sample or pixel buffer.
nonisolated final class VideoInputFrame {
    let presentationTimeStamp: CMTime
    private let borrow: ((CMSampleBuffer) throws -> Void) throws -> Void

    fileprivate init(time: CMTime, borrow: @escaping ((CMSampleBuffer) throws -> Void) throws -> Void) {
        presentationTimeStamp = time
        self.borrow = borrow
    }
    func withSampleBuffer(_ body: (CMSampleBuffer) throws -> Void) throws { try borrow(body) }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) throws {
        try borrow { sample in
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw VideoIOError.failed }
            try body(buffer)
        }
    }
}

nonisolated private protocol ReadOnlyFrameStorage: AnyObject {
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) rethrows
}
nonisolated private protocol MutableFrameStorage: AnyObject {
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) throws
    func freeze() throws -> any ReadOnlyFrameStorage
}

nonisolated private final class LegacyReadOnlyFrame: ReadOnlyFrameStorage {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) rethrows { try body(buffer) }
}
nonisolated private final class LegacyMutableFrame: MutableFrameStorage {
    private var buffer: CVPixelBuffer?
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) throws {
        guard let buffer else { throw VideoIOError.frameAlreadyFrozen }
        try body(buffer)
    }
    func freeze() throws -> any ReadOnlyFrameStorage {
        guard let buffer else { throw VideoIOError.frameAlreadyFrozen }
        self.buffer = nil
        return LegacyReadOnlyFrame(buffer)
    }
}

@available(macOS 26.0, *)
nonisolated private final class ModernReadOnlyFrame: ReadOnlyFrameStorage {
    let buffer: CVReadOnlyPixelBuffer
    init(_ buffer: CVReadOnlyPixelBuffer) { self.buffer = buffer }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) rethrows {
        try buffer.withUnsafeBuffer { raw in try body(raw) }
    }
}
@available(macOS 26.0, *)
nonisolated private final class ModernMutableFrame: MutableFrameStorage {
    private var buffer: CVMutablePixelBuffer?
    init(_ buffer: consuming CVMutablePixelBuffer) { self.buffer = consume buffer }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) throws {
        switch buffer {
        case .some(let borrowed): try borrowed.withUnsafeBuffer { raw in try body(raw) }
        case .none: throw VideoIOError.frameAlreadyFrozen
        }
    }
    func freeze() throws -> any ReadOnlyFrameStorage {
        guard let buffer = self.buffer.take() else { throw VideoIOError.frameAlreadyFrozen }
        return ModernReadOnlyFrame(CVReadOnlyPixelBuffer(consume buffer))
    }
}

/// A single processing job owns this mutable frame. freeze() consumes its
/// mutable storage; later mutation or a second freeze is rejected.
nonisolated final class OwnedVideoFrame {
    private let storage: any MutableFrameStorage
    fileprivate init(_ storage: any MutableFrameStorage) { self.storage = storage }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) throws { try storage.withPixelBuffer(body) }
    func freeze() throws -> ReadOnlyVideoFrame { ReadOnlyVideoFrame(try storage.freeze()) }
}

/// Immutable after processing, so encoder and temporal comparison can read the
/// same pixels without copying or keeping an alias to mutable storage.
nonisolated final class ReadOnlyVideoFrame {
    fileprivate let storage: any ReadOnlyFrameStorage
    fileprivate init(_ storage: any ReadOnlyFrameStorage) { self.storage = storage }
    func withPixelBuffer(_ body: (CVPixelBuffer) throws -> Void) rethrows { try storage.withPixelBuffer(body) }
}

/// One consumer owns each reader. The provider suspends rather than blocking the worker.
nonisolated final class VideoFrameReader {
    private let reader: AVAssetReader
    private let readNext: () async throws -> VideoInputFrame?
    private let checkCancellation: @Sendable () throws -> Void

    init(asset: AVAsset, track: AVAssetTrack, forceLegacy: Bool = false,
         checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) throws {
        self.checkCancellation = checkCancellation
        let reader = try AVAssetReader(asset: asset)
        self.reader = reader
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        if #available(macOS 26.0, *), !forceLegacy {
            let provider = reader.outputProvider(for: output)
            readNext = {
                guard let sample = try await provider.next() else { return nil }
                return VideoInputFrame(time: sample.presentationTimeStamp) { body in
                    try sample.withUnsafeSampleBuffer { raw in try body(raw) }
                }
            }
            try reader.start()
        } else {
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw VideoIOError.invalidConfiguration }
            reader.add(output)
            readNext = {
                guard let sample = output.copyNextSampleBuffer() else { return nil }
                return VideoInputFrame(time: CMSampleBufferGetPresentationTimeStamp(sample)) { body in try body(sample) }
            }
            guard reader.startReading() else { throw reader.error ?? VideoIOError.failed }
        }
    }

    nonisolated(nonsending) func next() async throws -> VideoInputFrame? {
        try checkCancellation()
        let sample = try await readNext()
        try checkCancellation()
        if sample == nil, reader.status != .completed { throw reader.error ?? VideoIOError.failed }
        return sample
    }
    func cancel() { reader.cancelReading() }
    deinit { if reader.status == .reading { reader.cancelReading() } }
}

nonisolated private protocol FrameWriterBackend: AnyObject {
    func makeFrame() throws -> OwnedVideoFrame
    nonisolated(nonsending) func append(_ frame: ReadOnlyVideoFrame, at time: CMTime) async throws
    func finishInput()
}

@available(macOS 26.0, *)
nonisolated private final class ModernWriterBackend: FrameWriterBackend {
    private let receiver: AVAssetWriterInput.PixelBufferReceiver
    init(_ receiver: AVAssetWriterInput.PixelBufferReceiver) { self.receiver = receiver }
    func makeFrame() throws -> OwnedVideoFrame {
        guard let pool = receiver.pixelBufferPool else { throw VideoIOError.failed }
        return OwnedVideoFrame(ModernMutableFrame(try pool.makeMutablePixelBuffer()))
    }
    nonisolated(nonsending) func append(_ frame: ReadOnlyVideoFrame, at time: CMTime) async throws {
        guard let storage = frame.storage as? ModernReadOnlyFrame else { throw VideoIOError.invalidConfiguration }
        try await receiver.append(storage.buffer, with: time)
    }
    func finishInput() { receiver.finish() }
}

nonisolated private final class LegacyWriterBackend: FrameWriterBackend {
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let input: AVAssetWriterInput
    private let writer: AVAssetWriter
    private let checkCancellation: @Sendable () throws -> Void
    init(adaptor: AVAssetWriterInputPixelBufferAdaptor, input: AVAssetWriterInput,
         writer: AVAssetWriter, checkCancellation: @escaping @Sendable () throws -> Void) {
        self.adaptor = adaptor
        self.input = input
        self.writer = writer
        self.checkCancellation = checkCancellation
    }
    func makeFrame() throws -> OwnedVideoFrame {
        guard let pool = adaptor.pixelBufferPool else { throw VideoIOError.failed }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { throw VideoIOError.failed }
        return OwnedVideoFrame(LegacyMutableFrame(buffer))
    }
    nonisolated(nonsending) func append(_ frame: ReadOnlyVideoFrame, at time: CMTime) async throws {
        while !input.isReadyForMoreMediaData {
            try checkCancellation()
            guard writer.status == .writing else { throw writer.error ?? VideoIOError.failed }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        try frame.withPixelBuffer { buffer in
            guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? VideoIOError.failed }
        }
    }
    func finishInput() { input.markAsFinished() }
}

/// Bounded encoder backpressure with a reusable pixel buffer pool on every OS.
nonisolated final class VideoFrameWriter {
    private let writer: AVAssetWriter
    private let backend: any FrameWriterBackend
    private let checkCancellation: @Sendable () throws -> Void

    init(outputURL: URL, videoSettings: [String: Any], width: Int, height: Int,
         transform: CGAffineTransform = .identity, forceLegacy: Bool = false,
         checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }) throws {
        self.checkCancellation = checkCancellation
        guard width > 0, height > 0 else { throw VideoIOError.invalidConfiguration }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        self.writer = writer
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.transform = transform
        if #available(macOS 26.0, *), !forceLegacy {
            let attributes = CVPixelBufferCreationAttributes(
                pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                size: .init(width: width, height: height), compatibility: [.metalTexture])
            let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
            backend = ModernWriterBackend(receiver)
            try writer.start()
        } else {
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
            guard writer.canAdd(input) else { throw VideoIOError.invalidConfiguration }
            writer.add(input)
            backend = LegacyWriterBackend(adaptor: adaptor, input: input, writer: writer,
                checkCancellation: checkCancellation)
            guard writer.startWriting() else { throw writer.error ?? VideoIOError.failed }
        }
        writer.startSession(atSourceTime: .zero)
    }

    func makeFrame() throws -> OwnedVideoFrame { try backend.makeFrame() }
    nonisolated(nonsending) func append(_ frame: ReadOnlyVideoFrame, at time: CMTime) async throws {
        try checkCancellation()
        guard writer.status == .writing else { throw writer.error ?? VideoIOError.failed }
        try await backend.append(frame, at: time)
        try checkCancellation()
    }
    nonisolated(nonsending) func finish() async throws {
        try checkCancellation()
        backend.finishInput()
        await writer.finishWriting()
        try checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? VideoIOError.failed }
    }
    func cancel() { writer.cancelWriting() }
    deinit { if writer.status == .writing { writer.cancelWriting() } }
}
