import AVFoundation
import Foundation

@main struct VideoAudioMuxRegression {
    static func main() async {
        do { try await run(); print("PASS audio mux: multiple tracks, VFR timestamps, rotation, offsets, durations, decode, silent source, missing video, cancellation and cleanup") }
        catch { fputs("FAIL audio mux: \(error)\n", stderr); exit(1) }
    }
    static func close(_ left: CMTime, _ right: CMTime) {
        precondition(abs(left.seconds - right.seconds) < 0.04, "Timeline mismatch \(left.seconds), \(right.seconds)")
    }
    static func run() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceURL = root.appendingPathComponent("source.mp4")
        let renderedURL = root.appendingPathComponent("rendered.mp4")
        let outputURL = root.appendingPathComponent("muxed.mp4")
        try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL, originalURL: sourceURL, outputURL: outputURL)
        let source = AVURLAsset(url: sourceURL)
        let rendered = AVURLAsset(url: renderedURL)
        let output = AVURLAsset(url: outputURL)
        let sourceAudio = try await source.loadTracks(withMediaType: .audio)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        precondition(sourceAudio.count == outputAudio.count && outputAudio.count == 2)
        for index in sourceAudio.indices {
            close(try await sourceAudio[index].load(.timeRange).start, try await outputAudio[index].load(.timeRange).start)
            close(try await sourceAudio[index].load(.timeRange).duration, try await outputAudio[index].load(.timeRange).duration)
        }
        let video = try await output.loadTracks(withMediaType: .video)[0]
        let originalVideo = try await rendered.loadTracks(withMediaType: .video)[0]
        close(try await video.load(.timeRange).start, try await originalVideo.load(.timeRange).start)
        close(try await video.load(.timeRange).duration, try await originalVideo.load(.timeRange).duration)
        close(try await output.load(.duration), try await source.load(.duration))
        let sourceTransform = try await originalVideo.load(.preferredTransform)
        let outputTransform = try await video.load(.preferredTransform)
        precondition(sourceTransform == outputTransform)
        let originalReader = try VideoFrameReader(asset: rendered, track: originalVideo)
        var timestamps: [CMTime] = []
        while let sample = try await originalReader.next() { timestamps.append(CMSampleBufferGetPresentationTimeStamp(sample)) }
        let videoReader = try VideoFrameReader(asset: output, track: video)
        var frameCount = 0
        while let sample = try await videoReader.next() {
            precondition(CMSampleBufferGetImageBuffer(sample) != nil)
            close(CMSampleBufferGetPresentationTimeStamp(sample), timestamps[frameCount])
            frameCount += 1
        }
        precondition(frameCount == timestamps.count && frameCount == 38)
        let audioReader = try AVAssetReader(asset: output)
        let audioOutput = AVAssetReaderTrackOutput(track: outputAudio[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        audioReader.add(audioOutput)
        precondition(audioReader.startReading())
        var samples = 0
        while let buffer = audioOutput.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(buffer) }
        precondition(audioReader.status == .completed && samples > 100_000)
        let silentOutput = root.appendingPathComponent("silent.mp4")
        try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL, originalURL: renderedURL, outputURL: silentOutput)
        let originalBytes = try Data(contentsOf: renderedURL)
        let silentBytes = try Data(contentsOf: silentOutput)
        precondition(originalBytes == silentBytes)
        let invalidOutput = root.appendingPathComponent("invalid.mp4")
        do {
            try await VideoAudioMuxer.preserveAudio(renderedVideoURL: root.appendingPathComponent("audio.m4a"), originalURL: sourceURL, outputURL: invalidOutput)
            fatalError("Missing video accepted")
        } catch VideoAudioMuxError.missingVideo { }
        precondition(!FileManager.default.fileExists(atPath: invalidOutput.path))
        let cancelOutput = root.appendingPathComponent("cancel.mp4")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL, originalURL: sourceURL, outputURL: cancelOutput)
        }
        do { try await task.value; fatalError("Cancellation accepted") } catch is CancellationError { }
        precondition(!FileManager.default.fileExists(atPath: cancelOutput.path))
        var checkpoints = 0
        do {
            try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL, originalURL: sourceURL, outputURL: cancelOutput, checkCancellation: {
                checkpoints += 1
                if checkpoints >= 6 { throw CancellationError() }
            })
            fatalError("Custom cancellation accepted")
        } catch is CancellationError { }
        precondition(!FileManager.default.fileExists(atPath: cancelOutput.path))
        precondition(FileManager.default.fileExists(atPath: renderedURL.path))
        do {
            try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL, originalURL: sourceURL, outputURL: outputURL)
            fatalError("Existing output overwritten")
        } catch VideoAudioMuxError.destinationExists { }
        precondition(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
