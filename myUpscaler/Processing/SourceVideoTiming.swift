import AVFoundation

/// Timing verified from sample metadata, without decoding or trusting nominal frame rate.
nonisolated struct SourceVideoTiming {
    let duration: CMTime
    let frameCount: Int64?
    let rateNumerator: Int64?
    let rateDenominator: Int64?
    let isVerifiedCFR: Bool

    static func inspect(url: URL,
        checkCancellation: @escaping () throws -> Void = { try Task.checkCancellation() }) async throws -> SourceVideoTiming {
        try checkCancellation()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return SourceVideoTiming(duration: .invalid, frameCount: nil,
                rateNumerator: nil, rateDenominator: nil, isVerifiedCFR: false)
        }
        let range = try await track.load(.timeRange)
        func result(_ count: Int64? = nil, _ interval: CMTime? = nil) -> SourceVideoTiming {
            guard let interval, interval.isNumeric, interval.value > 0 else {
                return SourceVideoTiming(duration: range.duration, frameCount: count,
                    rateNumerator: nil, rateDenominator: nil, isVerifiedCFR: false)
            }
            let factor = gcd(interval.value, Int64(interval.timescale))
            return SourceVideoTiming(duration: range.duration, frameCount: count,
                rateNumerator: Int64(interval.timescale) / factor,
                rateDenominator: interval.value / factor, isVerifiedCFR: true)
        }
        let segments = try await track.load(.segments)
        // Cursor PTS are in the media timeline. A normal MP4 edit list shifts
        // B-frame encoder preroll into the track timeline; map that offset exactly.
        // Repeated edits, gaps and time scaling remain conservatively unverified.
        guard segments.count == 1, !segments[0].isEmpty else { return result() }
        let mapping = segments[0].timeMapping
        guard CMTimeCompare(mapping.source.duration, mapping.target.duration) == 0 else { return result() }
        guard range.duration.isNumeric, range.duration > .zero,
              try await asset.load(.providesPreciseDurationAndTiming),
              try await track.load(.canProvideSampleCursors),
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return result() }
        // Decode order can differ from display order for B frames.
        _ = cursor.stepInPresentationOrder(byCount: -Int64.max)
        var count: Int64 = 0
        var firstPTS: CMTime?
        var previousPTS: CMTime?
        var interval: CMTime?
        var durations: CMTime?
        var constant = true
        let end = CMTimeRangeGetEnd(range)
        while true {
            try checkCancellation()
            let mediaPTS = cursor.presentationTimeStamp
            let pts = mediaPTS - mapping.source.start + mapping.target.start
            let duration = cursor.currentSampleDuration
            if !pts.isNumeric { constant = false }
            if pts.isNumeric, pts >= range.start, pts < end {
                if let previousPTS {
                    let delta = pts - previousPTS
                    if !delta.isNumeric || delta <= .zero { constant = false }
                    if let interval {
                        if CMTimeCompare(delta, interval) != 0 { constant = false }
                    } else { interval = delta }
                } else { firstPTS = pts }
                if !duration.isNumeric || duration <= .zero { constant = false }
                if let durations {
                    if CMTimeCompare(duration, durations) != 0 { constant = false }
                } else { durations = duration }
                previousPTS = pts
                count += 1
            }
            if cursor.stepInPresentationOrder(byCount: 1) != 1 { break }
            if count % 1024 == 0 { await Task.yield() }
        }
        try checkCancellation()
        if count == 1, constant, let durations, let firstPTS,
           CMTimeCompare(firstPTS, range.start) == 0,
           abs((durations - range.duration).seconds) <= 1.0 / Double(range.duration.timescale) {
            // One displayed sample has a finite duration even when the MP4 edit
            // list rounds its end to a coarser container tick.
            return result(count, range.duration)
        }
        guard constant, count >= 2, let interval, let durations, let firstPTS,
              CMTimeCompare(firstPTS, range.start) == 0,
              CMTimeCompare(durations, interval) == 0,
              count <= Int64(Int32.max),
              CMTimeCompare(CMTimeMultiply(interval, multiplier: Int32(count)), range.duration) == 0 else {
            return result(count)
        }
        return result(count, interval)
    }

    private static func gcd(_ left: Int64, _ right: Int64) -> Int64 {
        var a = left
        var b = right
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
