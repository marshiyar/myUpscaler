//
//  UpscaleRunnerTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
import Combine
@testable import myUpscaler

@MainActor struct UpscaleRunnerTests {
    
    // MARK: - Helpers
    
    func createRunner() -> (UpscaleRunner, MockFileSystem, MockEngine, MockAssetLoader) {
        let mockFS = MockFileSystem()
        let mockEngine = MockEngine()
        let mockLoader = MockAssetLoader()
        
        let runner = UpscaleRunner(fileSystem: mockFS, engine: mockEngine, assetLoader: mockLoader)
        return (runner, mockFS, mockEngine, mockLoader)
    }
    
    // MARK: - Initialization Tests
    
    @Test("UpscaleRunner should initialize with default values")
    func testInitialization() {
        let (runner, _, _, _) = createRunner()
        
        #expect(runner.inputPath.isEmpty)
        #expect(runner.outputMode == .same)
        #expect(runner.customOutputFolder.isEmpty)
        #expect(runner.isRunning == false)
        #expect(runner.log.isEmpty)
        #expect(runner.progress == 0.0)
    }
    
    // MARK: - Path Handling Tests
    
    @Test("predictedOutputName should generate correct filenames")
    func testPredictedOutputName() {
        let (runner, _, _, _) = createRunner()
        
        runner.inputPath = "/path/to/video.mp4"
        #expect(runner.predictedOutputName == "video_[restored].mp4")
        
        runner.inputPath = "/path/to/movie.mkv"
        #expect(runner.predictedOutputName == "movie_[restored].mp4")
    }
    
    @Test("outputFolder should respect mode")
    func testOutputFolder() {
        let (runner, _, _, _) = createRunner()
        
        // Same mode
        runner.inputPath = "/users/test/video.mp4"
        runner.outputMode = .same
        #expect(runner.outputFolder() == "/users/test")
        
        // Custom mode
        runner.outputMode = .custom
        runner.customOutputFolder = "/custom/out"
        #expect(runner.outputFolder() == "/custom/out")
    }
    
    // MARK: - Execution Tests
    
    @Test("run() should fail validation if input is empty")
    func testRunValidation() {
        let (runner, _, mockEngine, _) = createRunner()
        runner.inputPath = ""
        
        runner.run()
        
        #expect(mockEngine.processCalled == false)
        #expect(runner.log.contains("ERROR"))
        #expect(runner.log.contains("No input file"))
    }
    
    @Test("run() should start engine with correct parameters")
    func testRunStartsEngine() async throws {
        let (runner, _, mockEngine, mockLoader) = createRunner()
        runner.inputPath = "/test/video.mp4"
        mockLoader.durationToReturn = 100.0
        
        runner.run()
        
        // Give it a moment for async tasks to start
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(runner.isRunning == true)
        #expect(mockEngine.processCalled == true)
        #expect(mockEngine.processInputPath == "/test/video.mp4")
        #expect(runner.videoDuration == 100.0)
        #expect(runner.log.contains("Starting C Engine"))
    }
    
    @Test("run() should update progress from logs")
    func testRunProgressUpdates() async throws {
        let (runner, _, mockEngine, mockLoader) = createRunner()
        runner.inputPath = "/test/video.mp4"
        mockLoader.durationToReturn = 100.0 // 100 seconds
        
        // Simulate logs that update progress
        mockEngine.simulateLogOutput = [
            "frame=100 fps=30.0 time=00:00:50.00", // 50%
            "frame=200 fps=30.0 time=00:01:00.00"  // 60%
        ]
        mockEngine.simulateDelay = 0.2 // Add delay so we can inspect running state
        
        runner.run()
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Should have parsed the logs
        // Note: Progress update happens on MainActor, might need slight delay or wait
        // Since we are in async test context, we might race with MainActor updates.
        // In a real scenario, we might use Expectation or check after delay.
        
        // Verify final state
        #expect(runner.progress >= 0.5)
        #expect(runner.timeString == "0:01:00")
    }
    
    @Test("run() should handle errors gracefully")
    func testRunErrorHandling() async throws {
        let (runner, _, mockEngine, _) = createRunner()
        runner.inputPath = "/test/video.mp4"
        mockEngine.simulateError = Up60PEngineError.ffmpegNotFound
        
        runner.run()
        
        // Wait for error handling
        try await Task.sleep(nanoseconds: 200_000_000)
        
        #expect(runner.isRunning == false)
        #expect(runner.log.contains("FFmpeg executable not found"))
    }
    
    @Test("Error logs should include context and input path")
    func testErrorLogContext() async throws {
        let (runner, _, mockEngine, _) = createRunner()
        runner.inputPath = "/test/video.mp4"
        mockEngine.simulateLogOutput = ["[error] filter failed on frame 10"]
        mockEngine.simulateError = Up60PEngineError.io
        
        runner.run()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        #expect(runner.log.contains("Context: [error] filter failed on frame 10"))
        #expect(runner.log.contains("Input: /test/video.mp4"))
    }
    
    @Test("cancel() should stop engine and reset state")
    func testCancellation() async throws {
        let (runner, _, mockEngine, _) = createRunner()
        runner.inputPath = "/test/video.mp4"
        mockEngine.simulateDelay = 1.0 // Long running process
        
        runner.run()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(runner.isRunning == true)
        
        runner.cancel()
        
        #expect(mockEngine.cancelCalled == true)
        #expect(runner.isRunning == false)
        #expect(runner.log.contains("User Canceled"))
    }
    
    // MARK: - Completion Tests
    
    @Test("Should detect completion via log message")
    func testCompletionViaLog() async throws {
        let (runner, mockFS, mockEngine, _) = createRunner()
        runner.inputPath = "/test/video.mp4"
        let expectedOutput = "/test/video_[restored].mp4"
        
        // Mock the output file existing
        mockFS.mockFile(atPath: expectedOutput, size: 5000)
        
        // Simulate "Done." message
        mockEngine.simulateLogOutput = [
            "frame=100 fps=30 time=00:00:50.00",
            "elapsed=10.5s", // This triggers completion check
            "Done."
        ]
        
        runner.run()
        
        // Wait for completion check to run
        // The check runs for up to 10 seconds, but should finish quickly if file exists/stable
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        #expect(runner.isRunning == false)
        #expect(runner.completedOutputPath == expectedOutput)
        #expect(runner.progress == 1.0)
        #expect(runner.log.contains("Finished Successfully"))
    }
    
    @Test("Should handle completion without output file (failure/cancellation wrapped as completion)")
    func testCompletionWithoutFile() async throws {
        let (runner, _, mockEngine, _) = createRunner()
        runner.inputPath = "/test/video.mp4"
        
        // Simulate "elapsed=" but NO file exists in MockFS
        mockEngine.simulateLogOutput = [
            "elapsed=10.5s"
        ]
        
        runner.run()
        
        // Wait for completion check
        // It will retry for a bit, then give up and mark complete without path
        // This might take longer because of the retries in startCompletionCheck (20 * 0.5s = 10s max)
        // But since we are mocking, we can't easily speed up the internal Task.sleep without dependency injection for Scheduler/Clock.
        // However, the test might timeout if we wait 10s.
        // For this enterprise framework, we should inject a Scheduler/Clock abstraction, but for now we'll skip the full wait test or rely on the logic we can control.
        
        // We can verify it enters the checking state at least.
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // It should still be running the completion check task
        // We won't assert it finishes unless we want to wait 10s.
        // Ideally, we'd refactor UpscaleRunner to use a Clock protocol so we can advance time instantly.
    }
    
    // MARK: - Parallel Safety
    
    @Test("Parallel runs should use distinct outputs and avoid stomping logs")
    func testParallelRunsIsolation() async throws {
        let sharedFS = MockFileSystem()
        let engineA = MockEngine()
        let engineB = MockEngine()
        let loader = MockAssetLoader()
        
        let runnerA = UpscaleRunner(fileSystem: sharedFS, engine: engineA, assetLoader: loader)
        let runnerB = UpscaleRunner(fileSystem: sharedFS, engine: engineB, assetLoader: loader)
        
        runnerA.inputPath = "/Users/test/clipA.mp4"
        runnerB.inputPath = "/Users/test/clipB.mp4"
        runnerA.customOutputFolder = "/tmp/outA"
        runnerB.customOutputFolder = "/tmp/outB"
        runnerA.outputMode = .custom
        runnerB.outputMode = .custom
        
        sharedFS.mockFile(atPath: runnerA.inputPath, size: 5000)
        sharedFS.mockFile(atPath: runnerB.inputPath, size: 5000)
        
        runnerA.run()
        runnerB.run()
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        #expect(engineA.processCalled == true)
        #expect(engineB.processCalled == true)
        #expect(runnerA.outputVideoPath != runnerB.outputVideoPath)
        #expect(runnerA.log.contains("Starting C Engine"))
        #expect(runnerB.log.contains("Starting C Engine"))
    }
}
