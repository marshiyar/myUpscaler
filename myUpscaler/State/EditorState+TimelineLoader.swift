import AVFoundation
import CoreGraphics

nonisolated struct TimelineSample: Sendable {
    let image: CGImage
    let presentationTime: CMTime
}

nonisolated struct TimelineLoadResult: Sendable {
    let fps: Double
    let estimatedTotalFrames: Int
    let samples: [TimelineSample]
    let failedRequests: Int
}

/// One request owns its decoder and bounded metadata walk off the UI actor.
actor VideoTimelineLoader {
    private var generator: AVAssetImageGenerator?

    func cancel() { generator?.cancelAllCGImageGeneration() }

    func load(url: URL) async throws -> TimelineLoadResult {
        try await withTaskCancellationHandler {
            try await generate(url: url)
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func generate(url: URL) async throws -> TimelineLoadResult {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return TimelineLoadResult(fps: 0, estimatedTotalFrames: 0, samples: [], failedRequests: 0)
        }
        let duration = try await asset.load(.duration).seconds
        let rate = Double(try await track.load(.nominalFrameRate))
        let fps = rate.isFinite && rate > 0 ? rate : 30
        guard duration.isFinite, duration >= 0, duration * fps < Double(Int.max) else {
            return TimelineLoadResult(fps: fps, estimatedTotalFrames: 0, samples: [], failedRequests: 0)
        }
        let total = Int(duration * fps)
        let limit = min(total, 50)
        let exact = try await sampleTimes(asset: asset, track: track, limit: limit)
        // Formats without precise cursors retain bounded temporal sampling. The
        // returned actual time, rather than this estimate, always owns selection.
        let interval = CMTime(seconds: 1 / fps, preferredTimescale: 60_000)
        let times = exact ?? (0..<limit).map { CMTimeMultiply(interval, multiplier: Int32($0)) }
        let generator = AVAssetImageGenerator(asset: asset)
        self.generator = generator
        defer { self.generator = nil }
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        let tolerance = exact == nil ? CMTimeMultiplyByRatio(interval, multiplier: 1, divisor: 2) : .zero
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        try Task.checkCancellation()
        var samples: [TimelineSample] = []
        var failures = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                samples.append(TimelineSample(image: image, presentationTime: actual))
            case .failure:
                failures += 1
            }
        }
        try Task.checkCancellation()
        samples.sort { CMTimeCompare($0.presentationTime, $1.presentationTime) < 0 }
        return TimelineLoadResult(fps: fps, estimatedTotalFrames: total, samples: samples, failedRequests: failures)
    }

    /// Inspect at most the first 50 displayed samples, with edit-list mapping.
    /// VFR gaps and B-frame decode order do not become invented frame timestamps.
    private func sampleTimes(asset: AVAsset, track: AVAssetTrack, limit: Int) async throws -> [CMTime]? {
        guard limit > 0 else { return [] }
        guard try await asset.load(.providesPreciseDurationAndTiming),
              try await track.load(.canProvideSampleCursors) else { return nil }
        let segments = try await track.load(.segments)
        guard segments.count == 1, !segments[0].isEmpty else { return nil }
        let mapping = segments[0].timeMapping
        guard CMTimeCompare(mapping.source.duration, mapping.target.duration) == 0,
              let cursor = track.makeSampleCursor(presentationTimeStamp: mapping.source.start) else { return nil }
        let end = CMTimeRangeGetEnd(mapping.source)
        var times: [CMTime] = []
        // A precise cursor starts at the sample <= source.start; skip at most
        // one preroll sample before the visible range, never scan the whole asset.
        for _ in 0..<(limit + 1) {
            try Task.checkCancellation()
            let time = cursor.presentationTimeStamp
            if time >= end { break }
            if time >= mapping.source.start {
                times.append(time - mapping.source.start + mapping.target.start)
                if times.count == limit { break }
            }
            if cursor.stepInPresentationOrder(byCount: 1) != 1 { break }
        }
        return times
    }
}
