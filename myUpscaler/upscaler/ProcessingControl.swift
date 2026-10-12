import Foundation

/// One engine invocation owns the resources until finish(), including cancellation.
nonisolated final class ProcessingControl {
    enum Failure: Error { case alreadyRunning }
    private let lock = NSLock()
    private var running = false
    private var cancelled = false

    func begin() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { throw Failure.alreadyRunning }
        running = true
        cancelled = false
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        running = false
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if running { cancelled = true }
    }

    func checkCancellation() throws {
        try Task.checkCancellation()
        lock.lock()
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { throw CancellationError() }
    }

    /// Backpressure must also observe terminal failure and cancellation.
    func waitUntilReady(isReady: () -> Bool, failure: () -> Error?) async throws {
        while true {
            try checkCancellation()
            if let error = failure() { throw error }
            if isReady() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
