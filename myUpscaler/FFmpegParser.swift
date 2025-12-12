import Foundation

struct FFmpegProgressState {
    var fps: String?
    var timeString: String?
    var progress: Double?
    var eta: String?
    var newDuration: Double?
}

class FFmpegParser {
    private static let durationRegex = try? NSRegularExpression(pattern: "Duration:\\s*([0-9:.]+)")
    private static let frameRegex = try? NSRegularExpression(pattern: "frame=\\s*([0-9]+)")
    private static let fpsRegex = try? NSRegularExpression(pattern: "fps=([0-9\\.]+)")
    private static let timeRegex = try? NSRegularExpression(pattern: "time=([0-9:\\.]+)")
    
    static func parse(line: String, currentDuration: Double) -> FFmpegProgressState {
        var state = FFmpegProgressState()
        
        if currentDuration == 0 {
            if let durationStr = extract(durationRegex, from: line),
               let duration = parseTimeString(durationStr) {
                state.newDuration = duration
            }
        }
        
        if let timeStr = extract(timeRegex, from: line) {
            let fps = extract(fpsRegex, from: line)
            
            state.fps = fps
            state.timeString = timeStr
            
            if let currentTime = parseTimeString(timeStr) {
                let duration = state.newDuration ?? currentDuration
                
                if duration > 0 {
                    let calculatedProgress = currentTime / duration
                    state.progress = min(max(calculatedProgress, 0.0), 1.0)
                    
                    let remainingTime = max(0.0, duration - currentTime)
                    if let fpsVal = fps.flatMap({ Double($0) }), fpsVal > 0, remainingTime > 0 {
                        state.eta = formatTime(remainingTime)
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
    
    private static func extract(_ regex: NSRegularExpression?, from text: String) -> String? {
        guard let regex = regex else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = results.first, match.numberOfRanges > 1 {
            let range = match.range(at: 1)
            if range.location != NSNotFound {
                return nsString.substring(with: range)
            }
        }
        return nil
    }
    
    private static func parseTimeString(_ timeStr: String) -> Double? {
        let components = timeStr.split(separator: ":")
        
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
        
        return totalSeconds > 0 ? totalSeconds : nil
    }
    
    static func formatTime(_ seconds: Double) -> String {
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

