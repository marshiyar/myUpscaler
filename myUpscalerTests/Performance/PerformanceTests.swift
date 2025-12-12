import XCTest
@testable import myUpscaler

final class PerformanceTests: XCTestCase {

    @MainActor
    func testUpscaleStartLatency() {
        let runner = UpscaleRunner(engine: AdvancedMockEngine())
        runner.inputPath = "/test/dummy.mp4"
        
        measure(metrics: [XCTClockMetric()]) {
            let exp = expectation(description: "Started")
            
            Task { @MainActor in
                runner.run()
                // Wait for isRunning to flip
                // In a real scenario we might need a better signal, but for latency we measure the synchronous part + quick async dispatch
                if runner.isRunning {
                    exp.fulfill()
                } else {
                    // Poll briefly
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    if runner.isRunning { exp.fulfill() }
                }
            }
            
            wait(for: [exp], timeout: 1.0)
            runner.cancel()
        }
    }
    
    @MainActor
    func testMemoryUsageDuringInit() {
        measure(metrics: [XCTMemoryMetric()]) {
            _ = UpscaleRunner(engine: AdvancedMockEngine())
        }
    }
    
    func testLogParserThroughput() {
        let hugeLog = (0..<1000).map { "frame= \($0) fps=60.0 time=00:00:\($0).00" }
        let testDuration: Double = 1000.0 // Duration in seconds matching the max time in the log
        
        measure {
            for line in hugeLog {
                _ = FFmpegParser.parse(line: line, currentDuration: testDuration)
            }
        }
    }
    
    @MainActor
    func testSmallClipPerformanceBudget() {
        let mockFS = MockFileSystem()
        let mockLoader = MockAssetLoader()
        mockLoader.durationToReturn = 5.0
        let engine = AdvancedMockEngine()
        engine.processingDelay = 0.01
        engine.simulatedLogs = [
            "frame= 30 fps=30.0 time=00:00:01.00 bitrate= 800.0kbits/s",
            "elapsed=1.0s",
            "Done."
        ]
        
        let runner = UpscaleRunner(fileSystem: mockFS, engine: engine, assetLoader: mockLoader)
        runner.inputPath = "/Users/test/Videos/small.mp4"
        runner.outputMode = .custom
        runner.customOutputFolder = "/tmp/out"
        mockFS.mockFile(atPath: runner.inputPath, size: 2_048)
        
        measure(metrics: [XCTClockMetric()]) {
            let exp = expectation(description: "budget")
            Task { @MainActor in
                runner.run()
                exp.fulfill()
            }
            wait(for: [exp], timeout: 0.5)
            runner.cancel()
        }
    }
    
    // Manual benchmark for reporting (non-XCTest based, for the dashboard)
    static func runThroughputBenchmark() -> Double {
        let start = Date()
        let iterations = 50_000
        let testDuration: Double = 10.0 // Duration in seconds matching the test time string
        
        for i in 0..<iterations {
             _ = FFmpegParser.parse(line: "frame= \(i) fps=60.0 time=00:00:10.00", currentDuration: testDuration)
        }
        
        let elapsed = Date().timeIntervalSince(start)
        return Double(iterations) / elapsed // lines per second
    }
}

