import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

// Writes the small test videos the regression scripts need with AVFoundation, so no test depends on FFmpeg:
//
//   make-test-media clip <output.mp4> <width> <height> <rate-numerator> <rate-denominator> <frames>
//   make-test-media timing-set <directory>     fractional, integer, variable, single .mp4 and audio.m4a
//   make-test-media audio-mux-set <directory>  source.mp4, rendered.mp4 (rotated) and audio.m4a
//   make-test-media verify <file>              decodes every track to the end
//
// Every video sample carries its exact duration, so constant-rate fixtures have identical frame durations in the
// track timescale and the last frame is as long as the others. B-frames come from H.264 frame reordering.

struct VideoSpec {
    var width: Int
    var height: Int
    /// Presentation time and duration of each frame, in `timescale` units.
    var frames: [(pts: Int64, duration: Int64)]
    var timescale: Int32
    var reorder = true
    var transform = CGAffineTransform.identity
}

struct ToneSpec {
    var frequency: Double
    var start: Double
    var duration: Double
}

enum FixtureError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

/// One stream of samples to interleave into the writer.
final class Feed {
    let input: AVAssetWriterInput
    var samples: [() throws -> CMSampleBuffer]
    var times: [Double]
    var next = 0
    init(input: AVAssetWriterInput, samples: [() throws -> CMSampleBuffer], times: [Double]) {
        self.input = input
        self.samples = samples
        self.times = times
    }
    var done: Bool { next >= samples.count }
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw FixtureError.failed("\(what) failed: \(status)") }
}

func pixelBuffer(width: Int, height: Int, frame: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    try check(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer),
              "CVPixelBufferCreate")
    guard let buffer else { throw FixtureError.failed("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
        throw FixtureError.failed("no pixel memory")
    }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    // A gradient with a bar that moves every frame, so every frame differs.
    let bar = (frame * 3) % max(width, 1)
    for y in 0..<height {
        for x in 0..<width {
            let p = base + y * stride + x * 4
            let onBar = abs(x - bar) < max(width / 16, 2)
            p[0] = UInt8((x * 255) / max(width - 1, 1))
            p[1] = UInt8((y * 255) / max(height - 1, 1))
            p[2] = onBar ? 255 : UInt8((frame * 17) % 256)
            p[3] = 255
        }
    }
    return buffer
}

func videoSample(_ buffer: CVPixelBuffer, pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
    var format: CMVideoFormatDescription?
    try check(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format),
              "CMVideoFormatDescriptionCreateForImageBuffer")
    guard let format else { throw FixtureError.failed("no video format") }
    var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    try check(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample),
              "CMSampleBufferCreateReadyWithImageBuffer")
    guard let sample else { throw FixtureError.failed("no video sample") }
    return sample
}

let audioRate = 48_000.0
let audioChunk = 1024

func audioSample(tone: ToneSpec, firstFrame: Int, count: Int) throws -> CMSampleBuffer {
    var description = AudioStreamBasicDescription(
        mSampleRate: audioRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    try check(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format),
              "CMAudioFormatDescriptionCreate")
    guard let format else { throw FixtureError.failed("no audio format") }
    let bytes = count * 4
    var block: CMBlockBuffer?
    try check(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
                                                 blockBufferOut: &block),
              "CMBlockBufferCreateWithMemoryBlock")
    guard let block else { throw FixtureError.failed("no audio block") }
    var values = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let t = Double(firstFrame + i) / audioRate
        values[i] = Float(0.3 * sin(2 * Double.pi * tone.frequency * t))
    }
    try values.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        try check(CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes),
                  "CMBlockBufferReplaceDataBytes")
    }
    var sample: CMSampleBuffer?
    let pts = CMTime(value: CMTimeValue(tone.start * audioRate) + CMTimeValue(firstFrame), timescale: CMTimeScale(audioRate))
    try check(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                                   sampleCount: count, presentationTimeStamp: pts,
                                                                   packetDescriptions: nil, sampleBufferOut: &sample),
              "CMAudioSampleBufferCreateReadyWithPacketDescriptions")
    guard let sample else { throw FixtureError.failed("no audio sample") }
    return sample
}

func write(_ url: URL, type: AVFileType, video: VideoSpec?, tones: [ToneSpec]) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: type)
    var feeds: [Feed] = []
    if let video {
        var compression: [String: Any] = [
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: video.reorder,
            AVVideoMaxKeyFrameIntervalKey: 60,
        ]
        compression[AVVideoAverageBitRateKey] = max(video.width * video.height * 4, 100_000)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: video.width,
            AVVideoHeightKey: video.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = video.timescale
        input.transform = video.transform
        guard writer.canAdd(input) else { throw FixtureError.failed("cannot add video track") }
        writer.add(input)
        let samples: [() throws -> CMSampleBuffer] = video.frames.enumerated().map { index, frame in
            {
                let buffer = try pixelBuffer(width: video.width, height: video.height, frame: index)
                return try videoSample(buffer, pts: CMTime(value: frame.pts, timescale: video.timescale),
                                       duration: CMTime(value: frame.duration, timescale: video.timescale))
            }
        }
        feeds.append(Feed(input: input, samples: samples,
                          times: video.frames.map { Double($0.pts) / Double(video.timescale) }))
    }
    for tone in tones {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audioRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw FixtureError.failed("cannot add audio track") }
        writer.add(input)
        let total = Int(tone.duration * audioRate)
        let starts = Array(stride(from: 0, to: total, by: audioChunk))
        feeds.append(Feed(input: input,
                          samples: starts.map { first in { try audioSample(tone: tone, firstFrame: first, count: min(audioChunk, total - first)) } },
                          times: starts.map { tone.start + Double($0) / audioRate }))
    }
    guard writer.startWriting() else { throw FixtureError.failed("startWriting: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    // Interleave by time; an input that is not ready yields to the others.
    var idle = 0
    while feeds.contains(where: { !$0.done }) {
        var appended = false
        for feed in feeds.filter({ !$0.done }).sorted(by: { $0.times[$0.next] < $1.times[$1.next] })
            where feed.input.isReadyForMoreMediaData {
            let sample = try feed.samples[feed.next]()
            guard feed.input.append(sample) else {
                throw FixtureError.failed("append failed: \(String(describing: writer.error))")
            }
            feed.next += 1
            if feed.done { feed.input.markAsFinished() }
            appended = true
            break
        }
        if appended {
            idle = 0
        } else {
            idle += 1
            if idle > 20_000 { throw FixtureError.failed("writer stalled") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
    await writer.finishWriting()
    guard writer.status == .completed else { throw FixtureError.failed("finishWriting: \(String(describing: writer.error))") }
}

/// Constant-rate frames: `count` frames at `num/den` frames per second, in a timescale where each lasts exactly
/// `den` ticks (`num` ticks per second; a whole rate uses a finer timescale with the same exactness).
func constantRate(num: Int64, den: Int64, count: Int, width: Int, height: Int) -> VideoSpec {
    let scale: Int64 = den == 1 ? 1000 : 1
    let timescale = Int32(num * scale)
    let duration = den * scale
    return VideoSpec(width: width, height: height,
                     frames: (0..<count).map { (pts: Int64($0) * duration, duration: duration) }, timescale: timescale)
}

/// 24 fps for `seconds` with every fifth frame (index 0, 5, 10, ...) dropped; each kept frame lasts until the next.
func variableRate(width: Int, height: Int, seconds: Int) -> VideoSpec {
    let kept = (0..<(24 * seconds)).filter { $0 % 5 != 0 }
    let frames = kept.enumerated().map { i, n -> (pts: Int64, duration: Int64) in
        let next = i + 1 < kept.count ? kept[i + 1] : 24 * seconds
        return (pts: Int64(n) * 1000, duration: Int64(next - n) * 1000)
    }
    return VideoSpec(width: width, height: height, frames: frames, timescale: 24_000)
}

func verify(_ url: URL) async throws {
    let asset = AVURLAsset(url: url)
    let reader = try AVAssetReader(asset: asset)
    for track in try await asset.loadTracks(withMediaType: .video) {
        reader.add(AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]))
    }
    for track in try await asset.loadTracks(withMediaType: .audio) {
        reader.add(AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM]))
    }
    guard !reader.outputs.isEmpty, reader.startReading() else { throw FixtureError.failed("\(url.path): nothing to read") }
    var samples = 0
    for output in reader.outputs {
        while let sample = output.copyNextSampleBuffer() { samples += max(CMSampleBufferGetNumSamples(sample), 1) }
    }
    guard reader.status == .completed else {
        throw FixtureError.failed("\(url.path): decode stopped: \(String(describing: reader.error))")
    }
    print("decoded \(url.lastPathComponent): \(samples) samples in \(reader.outputs.count) tracks")
}

@main struct MakeTestMedia {
    static func main() async {
        let args = CommandLine.arguments
        do {
            guard args.count >= 3 else { throw FixtureError.failed("usage: make-test-media clip|timing-set|audio-mux-set|verify ...") }
            switch args[1] {
            case "clip":
                guard args.count == 8, let w = Int(args[3]), let h = Int(args[4]), let num = Int64(args[5]),
                      let den = Int64(args[6]), let count = Int(args[7]) else {
                    throw FixtureError.failed("usage: make-test-media clip <out> <w> <h> <rate-num> <rate-den> <frames>")
                }
                try await write(URL(fileURLWithPath: args[2]), type: .mp4,
                                video: constantRate(num: num, den: den, count: count, width: w, height: h), tones: [])
            case "timing-set":
                let dir = URL(fileURLWithPath: args[2])
                // 48 frames at 24000/1001 with three seconds of audio: the video duration must exclude the longer audio.
                try await write(dir.appendingPathComponent("fractional.mp4"), type: .mp4,
                                video: constantRate(num: 24_000, den: 1001, count: 48, width: 64, height: 48),
                                tones: [ToneSpec(frequency: 440, start: 0, duration: 3)])
                try await write(dir.appendingPathComponent("integer.mp4"), type: .mp4,
                                video: constantRate(num: 30, den: 1, count: 60, width: 64, height: 48), tones: [])
                try await write(dir.appendingPathComponent("variable.mp4"), type: .mp4,
                                video: variableRate(width: 64, height: 48, seconds: 2), tones: [])
                try await write(dir.appendingPathComponent("audio.m4a"), type: .m4a, video: nil,
                                tones: [ToneSpec(frequency: 440, start: 0, duration: 1)])
                try await write(dir.appendingPathComponent("single.mp4"), type: .mp4,
                                video: constantRate(num: 30, den: 1, count: 1, width: 64, height: 48), tones: [])
            case "audio-mux-set":
                let dir = URL(fileURLWithPath: args[2])
                let tones = [ToneSpec(frequency: 440, start: 0.2, duration: 3), ToneSpec(frequency: 660, start: 0.4, duration: 2.5)]
                // 38 frames: 24 fps for two seconds without every fifth frame.
                try await write(dir.appendingPathComponent("source.mp4"), type: .mp4,
                                video: variableRate(width: 64, height: 48, seconds: 2), tones: tones)
                var rotated = variableRate(width: 64, height: 48, seconds: 2)
                rotated.transform = CGAffineTransform(rotationAngle: .pi / 2)
                try await write(dir.appendingPathComponent("rendered.mp4"), type: .mp4, video: rotated, tones: [])
                try await write(dir.appendingPathComponent("audio.m4a"), type: .m4a, video: nil, tones: tones)
            case "verify":
                try await verify(URL(fileURLWithPath: args[2]))
            default:
                throw FixtureError.failed("unknown command \(args[1])")
            }
        } catch {
            FileHandle.standardError.write(Data("make-test-media: \(error)\n".utf8))
            exit(1)
        }
    }
}
