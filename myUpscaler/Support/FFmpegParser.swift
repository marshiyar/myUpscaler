import Foundation

nonisolated struct FFmpegProgressState {
    var fps: String?
    var timeString: String?
    var progress: Double?
    var eta: String?
    var newDuration: Double?
}

nonisolated class FFmpegParser {
    // Combined regex that captures duration, time, and fps in one pass
    private static let combinedRegex = try? NSRegularExpression(
        pattern: "(?:Duration:\\s*([0-9:.]+))|(?:time=([0-9:\\.]+))|(?:fps=([0-9\\.]+))|(?:speed=([0-9\\.]+)x)"
    )

    static func parse(line: String, currentDuration: Double) -> FFmpegProgressState {
        var state = FFmpegProgressState()

        guard let regex = combinedRegex else { return state }
        let nsString = line as NSString
        let range = NSRange(location: 0, length: nsString.length)

        // Single pass: find all matches
        let matches = regex.matches(in: line, options: [], range: range)

        var durationStr: String?
        var timeStr: String?
        var fpsStr: String?
        var speedStr: String?

        for match in matches {
            // Group 1: Duration
            if match.numberOfRanges > 1 {
                let durationRange = match.range(at: 1)
                if durationRange.location != NSNotFound {
                    durationStr = nsString.substring(with: durationRange)
                }
            }

            // Group 2: Time
            if match.numberOfRanges > 2 {
                let timeRange = match.range(at: 2)
                if timeRange.location != NSNotFound {
                    timeStr = nsString.substring(with: timeRange)
                }
            }

            // Group 3: FPS
            if match.numberOfRanges > 3 {
                let fpsRange = match.range(at: 3)
                if fpsRange.location != NSNotFound {
                    fpsStr = nsString.substring(with: fpsRange)
                }
            }
            if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound {
                speedStr = nsString.substring(with: match.range(at: 4))
            }
        }

        // Process duration
        if currentDuration == 0, let durationStr = durationStr,
           let duration = parseTimeString(durationStr) {
            state.newDuration = duration
        }

        // Process time and fps
        if let timeStr = timeStr {
            state.fps = fpsStr
            state.timeString = timeStr

            if let currentTime = parseTimeString(timeStr) {
                let duration = state.newDuration ?? currentDuration

                if duration > 0 {
                    let calculatedProgress = currentTime / duration
                    state.progress = min(max(calculatedProgress, 0.0), 1.0)

                    let remainingTime = max(0.0, duration - currentTime)
                    if let speed = speedStr.flatMap({ Double($0) }), speed.isFinite, speed > 0, remainingTime > 0 {
                        state.eta = formatTime(remainingTime / speed)
                    } else if remainingTime <= 0 {
                        state.progress = 1.0
                        state.eta = "0:00"
                    } else {
                        state.eta = "--:--"
                    }
                } else {
                    state.eta = "--:--"
                }
            }
        }

        return state
    }

    private static func parseTimeString(_ timeStr: String) -> Double? {
        let components = timeStr.split(separator: ":")

        if components.count == 1 {
            return Double(timeStr).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        guard components.count >= 2 else { return nil }

        var totalSeconds: Double = 0.0

        if components.count == 2 {
            if let minutes = Double(components[0]),
               let seconds = Double(components[1]) {
                totalSeconds = minutes * 60 + seconds
            }
        }
        else if components.count == 3 {
            if let hours = Double(components[0]),
               let minutes = Double(components[1]),
               let seconds = Double(components[2]) {
                totalSeconds = hours * 3600 + minutes * 60 + seconds
            }
        }

        return totalSeconds.isFinite && totalSeconds >= 0 ? totalSeconds : nil
    }
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
