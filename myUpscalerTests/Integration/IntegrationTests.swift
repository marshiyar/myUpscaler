//
//  IntegrationTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
@testable import myUpscaler

@MainActor
struct IntegrationTests {
    
    // MARK: - Helpers
    
    func createIntegratedRunner() -> (UpscaleRunner, MockFileSystem, MockEngine, MockAssetLoader) {
        let mockFS = MockFileSystem()
        let mockEngine = MockEngine()
        let mockLoader = MockAssetLoader()
        
        // Setup default behaviors
        mockFS.homeDirectoryForCurrentUser = URL(fileURLWithPath: "/Users/test")
        mockLoader.durationToReturn = 100.0
        
        let runner = UpscaleRunner(fileSystem: mockFS, engine: mockEngine, assetLoader: mockLoader)
        return (runner, mockFS, mockEngine, mockLoader)
    }
    
    // MARK: - Component Integration Tests
    
    @Test("UpscaleRunner should integrate with UpscaleSettings correctly")
    func testRunnerSettingsIntegration() {
        let (runner, _, _, _) = createIntegratedRunner()
        let settings = UpscaleSettings()
        
        // Modify settings
        settings.useHEVC = true
        settings.crf = 20.0
        settings.scaleFactor = 3.0
        
        // Assign to runner
        runner.settings = settings
        
        // Verify integration
        #expect(runner.settings.useHEVC == true)
        #expect(runner.settings.crf == 20.0)
        #expect(runner.settings.scaleFactor == 3.0)
    }
    
    @Test("FFmpegParser should integrate with UpscaleRunner via log updates")
    func testParserRunnerIntegration() async throws {
        let (runner, _, mockEngine, _) = createIntegratedRunner()
        runner.inputPath = "/test/video.mp4"
        
        // Simulate logs that FFmpegParser will parse
        mockEngine.simulateLogOutput = [
            "frame= 50 fps=5.0 time=00:00:25.00 bitrate= 1000.0kbits/s",
            "frame= 100 fps=5.0 time=00:00:50.00 bitrate= 1000.0kbits/s",
            "frame= 150 fps=5.0 time=00:00:75.00 bitrate= 1000.0kbits/s"
        ]
        mockEngine.simulateDelay = 0.1
        
        runner.run()
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify that logs were parsed and updated the runner state
        let progress = runner.progress
        let timeString = runner.timeString
        #expect(progress >= 0.7) // Should be around 0.75
        #expect(timeString.contains("00:00:75") || timeString.contains("01:15"))
    }
    
    @Test("Settings auto-toggles should work with multiple filter sets")
    func testMultipleFilterSetsIntegration() async throws {
        let settings = UpscaleSettings()
        
        // Enable second set filters
        settings.useDenoise2 = true
        settings.useDeblock2 = true
        settings.useDering2 = true
        settings.useSharpen2 = true
        settings.useDeband2 = true
        settings.useGrain2 = true
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Set all to zero
        settings.denoiseStrength2 = "0"
        settings.deblockThresh2 = "0"
        settings.deringStrength2 = "0"
        settings.sharpenStrength2 = "0"
        settings.debandStrength2 = "0"
        settings.grainStrength2 = "0"
        
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // All should be disabled
        #expect(settings.useDenoise2 == false)
        #expect(settings.useDeblock2 == false)
        #expect(settings.useDering2 == false)
        #expect(settings.useSharpen2 == false)
        #expect(settings.useDeband2 == false)
        #expect(settings.useGrain2 == false)
    }
    
    // MARK: - Error Handling Integration
    
    @Test("Error handling should propagate from Engine to Runner")
    func testErrorHandlingIntegration() async throws {
        let (runner, _, mockEngine, _) = createIntegratedRunner()
        runner.inputPath = "/test/video.mp4"
        
        // Simulate Engine error
        mockEngine.simulateError = Up60PEngineError.io
        
        runner.run()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should handle error gracefully
        let isRunning = runner.isRunning
        let log = runner.log
        #expect(isRunning == false)
        #expect(log.contains("I/O error"))
    }
    
    @Test("Cancellation should propagate to Engine")
    func testCancellationIntegration() async throws {
        let (runner, _, mockEngine, _) = createIntegratedRunner()
        runner.inputPath = "/test/video.mp4"
        mockEngine.simulateDelay = 1.0
        
        runner.run()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        runner.cancel()
        
        // Verify propagation
        let isRunning = runner.isRunning
        #expect(mockEngine.cancelCalled == true)
        #expect(isRunning == false)
    }
    
    @Test("FFmpeg not found should be surfaced to the log")
    func testFFmpegFailureInjection() async throws {
        let (runner, _, mockEngine, _) = createIntegratedRunner()
        runner.inputPath = "/test/video.mp4"
        
        mockEngine.simulateError = Up60PEngineError.ffmpegNotFound
        
        runner.run()
        try await Task.sleep(nanoseconds: 150_000_000)
        
        #expect(runner.log.contains("FFmpeg executable not found"))
        #expect(runner.isRunning == false)
    }
    
    @Test("Output directory errors should halt run and report path")
    func testOutputDirectoryFailure() {
        let (runner, mockFS, _, _) = createIntegratedRunner()
        runner.inputPath = "/Users/test/Videos/input.mov"
        runner.outputMode = .custom
        runner.customOutputFolder = "/Users/test/Output"
        
        mockFS.createDirectoryError = NSError(domain: "fs", code: 13, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        
        runner.run()
        
        #expect(runner.isRunning == false)
        #expect(runner.log.contains("Could not create output directory"))
        #expect(runner.log.contains("/Users/test/Output"))
    }
    
    // MARK: - Path Handling Integration
    
    @Test("Path handling should integrate with MockFileSystem")
    func testPathHandlingIntegration() {
        let (runner, mockFS, _, _) = createIntegratedRunner()
        
        // Setup home dir in mock
        mockFS.homeDirectoryForCurrentUser = URL(fileURLWithPath: "/Users/mockuser")
        
        runner.inputPath = "/Users/test/Videos/input.mkv"
        runner.outputMode = .same
        
        // Test path computations
        let outputFolder = runner.outputFolder()
        let outputPath = runner.outputVideoPath
        let outputName = runner.predictedOutputName
        
        #expect(outputFolder == "/Users/test/Videos")
        #expect(outputName == "input_[restored].mp4")
        #expect(outputPath == "/Users/test/Videos/input_[restored].mp4")
    }
    
    @Test("Custom output folder should work correctly")
    func testCustomOutputFolderIntegration() {
        let (runner, _, _, _) = createIntegratedRunner()
        runner.inputPath = "/Users/test/Videos/input.mkv"
        runner.outputMode = .custom
        runner.customOutputFolder = "/Users/test/Output"
        
        let outputFolder = runner.outputFolder()
        let outputPath = runner.outputVideoPath
        
        #expect(outputFolder == "/Users/test/Output")
        #expect(outputPath == "/Users/test/Output/input_[restored].mp4")
    }
    
    // MARK: - Settings Persistence Integration
    
    @Test("x265Params should round-trip correctly")
    func testX265ParamsRoundTrip() {
        let settings = UpscaleSettings()
        
        // Set individual values
        settings.x265AqMode = "3"
        settings.x265PsyRd = "2.0"
        settings.x265Deblock1 = "-2"
        settings.x265Deblock2 = "-2"
        
        // Get params string
        let paramsString = settings.x265Params
        
        // Parse it back
        let newSettings = UpscaleSettings()
        newSettings.parseX265Params(from: paramsString)
        
        // Should match
        #expect(newSettings.x265AqMode == "3")
        #expect(newSettings.x265PsyRd == "2.0")
        #expect(newSettings.x265Deblock1 == "-2")
        #expect(newSettings.x265Deblock2 == "-2")
    }
    
    // MARK: - Edge Case Integration Tests
    
    @Test("Should handle rapid state changes")
    func testRapidStateChanges() {
        let (runner, _, _, _) = createIntegratedRunner()
        
        // Rapidly change states
        runner.isRunning = true
        runner.isRunning = false
        runner.isRunning = true
        runner.cancel()
        runner.isRunning = true
        runner.cancel()
        
        // Should end in consistent state
        #expect(runner.isRunning == false)
    }
    
    @Test("Should handle concurrent progress updates")
    func testConcurrentProgressUpdates() async throws {
        let (runner, _, mockEngine, _) = createIntegratedRunner()
        runner.inputPath = "/test/video.mp4"
        
        // Simulate rapid concurrent updates
        mockEngine.simulateLogOutput = (1...10).map { i in
            "frame= \(i * 10) fps=5.0 time=00:00:\(i).00 bitrate= 1000.0kbits/s"
        }
        
        runner.run()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Progress should be reasonable
        let progress = runner.progress
        #expect(progress >= 0.0 && progress <= 1.0)
    }
    
    @Test("Should handle empty and nil values gracefully")
    func testEmptyNilValues() {
        let (runner, _, _, _) = createIntegratedRunner()
        let settings = UpscaleSettings()
        
        // Set empty values
        runner.inputPath = ""
        settings.aiModelPath = ""
        settings.lutPath = ""
        // x265Params is read-only, so we can't set it directly
        // Instead, set individual x265 parameters to empty
        settings.x265AqMode = ""
        settings.x265PsyRd = ""
        
        // Should not crash
        #expect(runner.inputPath.isEmpty)
        #expect(settings.aiModelPath.isEmpty)
    }
    
    // MARK: - Real-World Scenario Tests
    
    @Test("Should handle typical video processing workflow")
    func testTypicalWorkflow() {
        let (runner, _, _, _) = createIntegratedRunner()
        let settings = UpscaleSettings()
        
        // 1. Configure settings
        settings.useHEVC = true
        settings.crf = 18.0
        settings.scaleFactor = 2.0
        settings.fps = "60"
        
        // 2. Set input
        runner.inputPath = "/Users/test/video.mp4"
        runner.outputMode = .same
        runner.settings = settings
        
        // 3. Verify configuration
        #expect(runner.inputPath == "/Users/test/video.mp4")
        #expect(runner.settings.useHEVC == true)
        #expect(runner.settings.crf == 18.0)
        
        // 4. Verify output path
        let outputPath = runner.outputVideoPath
        #expect(outputPath.contains("video_[restored].mp4"))
    }
    
    // MARK: - End-to-End Pipeline (Mocked FFmpeg)
    
    @Test("Full pipeline should drive engine, parser, and output tracking")
    func testFullPipelineWithMocks() async throws {
        let mockFS = MockFileSystem()
        let mockLoader = MockAssetLoader()
        mockLoader.durationToReturn = 12.0
        
        #if DEBUG
        let engine = AdvancedMockEngine()
        #else
        let engine = MockEngine()
        #endif
        
        let runner = UpscaleRunner(fileSystem: mockFS, engine: engine, assetLoader: mockLoader)
        runner.inputPath = "/Users/test/Videos/sample.mp4"
        runner.outputMode = .custom
        runner.customOutputFolder = "/Users/test/Output"
        runner.settings.useHEVC = true
        runner.settings.scaleFactor = 1.5
        
        // Ensure the input file "exists" for the runner
        mockFS.mockFile(atPath: runner.inputPath, size: 10_000)
        
        #if DEBUG
        engine.simulatedLogs = [
            "frame= 60 fps=30.0 time=00:00:02.00 bitrate= 900.0kbits/s",
            "frame= 120 fps=30.0 time=00:00:04.00 bitrate= 900.0kbits/s",
            "elapsed=4.0s",
            "Done."
        ]
        engine.processingDelay = 0.05
        #endif
        
        runner.run()
        
        // Simulate the output file appearing and stabilizing
        try await Task.sleep(nanoseconds: 150_000_000)
        mockFS.mockFile(atPath: runner.outputVideoPath, size: 50_000)
        
        // Allow completion polling to fire
        try await Task.sleep(nanoseconds: 700_000_000)
        
        // Validate the pipeline touched all components
        #if DEBUG
        #expect(engine.processCallCount == 1)
        #endif
        #expect(runner.completedOutputPath == runner.outputVideoPath)
        #expect(runner.progress >= 0.99)
        #expect(runner.timeString.contains("00:00:04") || runner.timeString.contains("0:04"))
        #expect(runner.log.contains("Starting C Engine"))
    }
}

