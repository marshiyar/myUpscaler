//
//  BackendGuiConnectivityTests.swift
//  myUpscalerTests
//

import Testing
import Foundation
@testable import myUpscaler

@MainActor
struct BackendGuiConnectivityTests {
    
    // MARK: - Helpers
    
    private func makeRunner() -> (UpscaleRunner, MockFileSystem, MockEngine, MockAssetLoader) {
        let fs = MockFileSystem()
        let engine = MockEngine()
        let loader = MockAssetLoader()
        let runner = UpscaleRunner(fileSystem: fs, engine: engine, assetLoader: loader)
        return (runner, fs, engine, loader)
    }
    
    // MARK: - Tests
    
    @Test("Runner should bridge engine logs into UI-facing state")
    func testEngineLogsReachUI() async throws {
        let (runner, mockFS, mockEngine, mockLoader) = makeRunner()
        let input = "/Users/test/video.mp4"
        mockFS.mockFile(atPath: input, size: 50_000)
        mockLoader.durationToReturn = 120.0
        
        runner.inputPath = input
        
        mockEngine.simulateLogOutput = [
            "Duration: 00:02:00.00, start: 0.000000, bitrate: 1000 kb/s",
            "frame= 200 fps=25.0 time=00:01:00.00 bitrate= 1000.0kbits/s"
        ]
        mockEngine.simulateDelay = 0.05
        
        runner.run()
        
        // Allow async callbacks + log flush to run
        try await Task.sleep(nanoseconds: 250_000_000)
        
        // Stop background tasks to avoid long completion checks
        runner.cancel()
        
        #expect(mockEngine.logHandler != nil, "Runner must register a log handler")
        #expect(runner.log.contains("Duration:"), "Log stream should surface in UI log text")
        #expect(runner.fpsString == "25.0")
        #expect(runner.timeString.contains("00:01:00"))
        #expect(runner.progress > 0.45 && runner.progress < 0.55, "Progress should reflect parsed time vs duration")
    }
    
    @Test("Runner should rebind handlers and reset state across runs")
    func testRebindingAcrossRuns() async throws {
        let (runner, mockFS, mockEngine, mockLoader) = makeRunner()
        let input = "/Users/test/video.mp4"
        mockFS.mockFile(atPath: input, size: 50_000)
        mockLoader.durationToReturn = 60.0
        runner.inputPath = input
        
        func performRun(logs: [String]) async throws -> String {
            mockEngine.simulateLogOutput = logs
            mockEngine.simulateDelay = 0.02
            runner.run()
            try await Task.sleep(nanoseconds: 180_000_000)
            runner.cancel()
            return runner.log
        }
        
        let firstLog = try await performRun(logs: [
            "frame= 50 fps=5.0 time=00:00:05.00 bitrate= 900.0kbits/s"
        ])
        #expect(firstLog.contains("00:00:05.00"))
        
        let secondLog = try await performRun(logs: [
            "frame= 100 fps=10.0 time=00:00:10.00 bitrate= 900.0kbits/s"
        ])
        #expect(secondLog.contains("00:00:10.00"))
        #expect(!secondLog.contains("00:00:05.00"), "Runner log should reset between runs")
        #expect(mockEngine.logHandler != nil, "Log handler must stay bound on reruns")
        #expect(runner.isRunning == false)
    }
}


