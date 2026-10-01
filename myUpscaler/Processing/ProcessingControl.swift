import Foundation
import Synchronization

/// One engine invocation owns its resources until finish(), including cancellation.
/// All shared state is protected by a checked Sendable mutex on macOS 15+.
nonisolated final class ProcessingControl: Sendable {
    enum Failure: Error { case alreadyRunning }
    private struct State: Sendable {
        var running = false
        var cancelled = false
    }
    private let state = Mutex(State())

    func begin() throws {
        try state.withLock { state in
            guard !state.running else { throw Failure.alreadyRunning }
            state.running = true
            state.cancelled = false
        }
    }
    func finish() { state.withLock { $0.running = false } }
    func cancel() {
        state.withLock { state in if state.running { state.cancelled = true } }
    }
    func checkCancellation() throws {
        try Task.checkCancellation()
        if state.withLock({ $0.cancelled }) { throw CancellationError() }
    }

    /// Backpressure must also observe terminal failure and cancellation.
    nonisolated(nonsending) func waitUntilReady(isReady: () -> Bool, failure: () -> Error?) async throws {
        while true {
            try checkCancellation()
            if let error = failure() { throw error }
            if isReady() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
