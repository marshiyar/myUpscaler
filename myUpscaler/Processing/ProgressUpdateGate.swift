import Foundation

/// Throttle repetitive progress before enqueueing UI work; preserve diagnostics
/// and terminal stage events even when they arrive inside the sampling interval.
nonisolated final class ProgressUpdateGate {
    private let lock = NSLock()
    private var lastUpdate: TimeInterval = -.infinity
    func shouldEmit(_ message: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let lower = message.lowercased()
        let progress = lower.contains("time=") || lower.contains("fps=")
        let important = lower.contains("error") || lower.contains("fail") || lower.contains("duration:")
            || lower.contains("elapsed=") || lower.contains("done") || lower.contains("stage=")
        guard progress && !important else { return true }
        lock.lock()
        defer { lock.unlock() }
        guard now - lastUpdate >= 0.2 else { return false }
        lastUpdate = now
        return true
    }
}
