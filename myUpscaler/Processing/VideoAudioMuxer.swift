import AVFoundation
import Foundation

nonisolated enum VideoAudioMuxError: Error, LocalizedError {
    case missingVideo
    case destinationExists
    case unsupportedMP4Audio
    case cannotCreateComposition

    var errorDescription: String? {
        switch self {
        case .missingVideo: return "The rendered file contains no video track."
        case .destinationExists: return "The output file already exists."
        case .unsupportedMP4Audio: return "The source audio cannot be preserved in an MP4 container. Choose a compatible source audio format."
        case .cannotCreateComposition: return "The audio and video composition could not be created."
        }
    }
}

/// Adds original audio without re-encoding the rendered video or shortening either stream.
nonisolated enum VideoAudioMuxer {
    static func preserveAudio(renderedVideoURL: URL, originalURL: URL, outputURL: URL,
        checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() }) async throws {
        try checkCancellation()
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoAudioMuxError.destinationExists
        }
        let rendered = AVURLAsset(url: renderedVideoURL)
        guard let video = try await rendered.loadTracks(withMediaType: .video).first else {
            throw VideoAudioMuxError.missingVideo
        }
        let source = AVURLAsset(url: originalURL)
        let audioTracks = try await source.loadTracks(withMediaType: .audio)
        try checkCancellation()
        var ownsOutput = false
        var completed = false
        defer {
            if ownsOutput && !completed { try? FileManager.default.removeItem(at: outputURL) }
        }
        if audioTracks.isEmpty {
            // Leave the caller-owned intermediate untouched, including on failure.
            ownsOutput = true
            try FileManager.default.copyItem(at: renderedVideoURL, to: outputURL)
            try checkCancellation()
            completed = true
            return
        }
        let composition = AVMutableComposition()
        guard let composedVideo = composition.addMutableTrack(withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoAudioMuxError.cannotCreateComposition
        }
        let videoRange = try await video.load(.timeRange)
        try composedVideo.insertTimeRange(videoRange, of: video, at: videoRange.start)
        composedVideo.preferredTransform = try await video.load(.preferredTransform)
        for audio in audioTracks {
            try checkCancellation()
            guard let composedAudio = composition.addMutableTrack(withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoAudioMuxError.cannotCreateComposition
            }
            let range = try await audio.load(.timeRange)
            try composedAudio.insertTimeRange(range, of: audio, at: range.start)
        }
        guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough,
            with: composition, outputFileType: .mp4),
            let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoAudioMuxError.unsupportedMP4Audio
        }
        try checkCancellation()
        ownsOutput = true
        // Task cancellation interrupts AVFoundation export; the monitor also supports
        // direct engine cancellation flags while export is suspended.
        try await withThrowingTaskGroup(of: Void.self) { group in
            defer { group.cancelAll() }
            group.addTask { try await exporter.export(to: outputURL, as: .mp4) }
            group.addTask {
                while true {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    try checkCancellation()
                }
            }
            _ = try await group.next()
        }
        try checkCancellation()
        completed = true
    }
}
