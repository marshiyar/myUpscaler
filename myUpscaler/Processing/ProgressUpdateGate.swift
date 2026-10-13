import Foundation
import Synchronization

/// Throttle repetitive progress before enqueueing UI work; preserve diagnostics
/// and terminal stage events even when they arrive inside the sampling interval.
nonisolated final class ProgressUpdateGate: Sendable {
    private let lastUpdate = Mutex<TimeInterval>(-.infinity)
    func shouldEmit(_ message: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let lower = message.lowercased()
        let progress = lower.contains("time=") || lower.contains("fps=")
        let important = lower.contains("error") || lower.contains("fail") || lower.contains("duration:")
            || lower.contains("warning") || lower.contains("cancel") || lower.contains("lsize=")
            || lower.contains("done") || lower.contains("stage=")
        guard progress && !important else { return true }

        // Native pipe reads may combine progress with arbitrary diagnostics. Only
        // sample chunks whose every record starts with a recognized stats field.
        // `elapsed=` is part of modern FFmpeg stats, not a terminal marker.
        
        let records = lower.split(whereSeparator: { $0.isNewline })
        guard !records.isEmpty, records.allSatisfy({ record in
            let trimmed = record.drop(while: { $0 == " " || $0 == "\t" })
            return trimmed.hasPrefix("frame=") || trimmed.hasPrefix("time=") || trimmed.hasPrefix("fps=")
        }) else { return true }
        return lastUpdate.withLock { previous in
            guard now - previous >= 0.2 else { return false }
            previous = now
            return true
        }
    }
}
