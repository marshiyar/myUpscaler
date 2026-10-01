import Foundation

@main struct ProgressGateTests {
    static func main() throws {
        let benchmark = CommandLine.arguments.contains("--benchmark")
        if !benchmark {
            let gate = ProgressUpdateGate()
            precondition(gate.shouldEmit("frame=1 fps=20 time=0.1 speed=1x elapsed=0:00:00.01\r", now: 0))
            precondition(!gate.shouldEmit("frame=2 fps=20 time=0.2 speed=1x elapsed=0:00:00.02\r", now: 0.1))
            for message in ["ERROR: time=2", "WARNING: time=2", "Processing cancelled. time=2", "Duration: 0:00:10 time=2",
                "stage=finalizing time=2", "Done. time=2", "frame=2 fps=20 time=0.2 Lsize=20KiB elapsed=0:00:00.02\n",
                "frame=2 fps=20 time=0.2 elapsed=0:00:00.02\rUnrecognized diagnostic detail\n", "frame=2 fps=20 time=0.2 elapsed=0:00:00.02\r\nUnrecognized diagnostic detail\r\n", "elapsed=1\n"] {
                precondition(gate.shouldEmit(message, now: 0.1), "lost diagnostic or terminal event: \(message)")
            }
            precondition(!gate.shouldEmit("time=0.3 fps=20\rframe=3 fps=20 time=0.3 elapsed=0:00:00.03\r", now: 0.1))
            precondition(gate.shouldEmit("time=0.3 fps=20", now: 0.3))
            print("PASS: modern elapsed stats throttled; terminal stats, standalone elapsed, errors, warnings, cancellation, duration and mixed chunks preserved")
            return
        }
        var timings: [Double] = [], counts: [Int] = []
        let messages = (0..<10_000).map { "frame=\($0) fps=100 time=\(Double($0)/100) speed=1x elapsed=0:00:01.00\r" }
        for _ in 0..<12 {
            let gate = ProgressUpdateGate()
            let start = ProcessInfo.processInfo.systemUptime
            var accepted = 0
            for index in messages.indices {
                if gate.shouldEmit(messages[index], now: Double(index) / 100) { accepted += 1 }
            }
            timings.append(ProcessInfo.processInfo.systemUptime - start); counts.append(accepted)
        }
        let data = try JSONSerialization.data(withJSONObject: ["recordsPerTrial": messages.count, "virtualFrequencyHz": 100,
            "trials": timings, "accepted": counts], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
