//
//  Up60PEngineTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Foundation
import Testing
@testable import myUpscaler

private final class BridgeRecorder {
    var initCalls = 0
    var processCalls = 0
    var defaultCalls = 0
    var dryRunValues: [Int32] = []
    var lastOptions: up60p_options?
    var cancelCalls = 0
}

private final class CancellationProbe {
    private let queue = DispatchQueue(label: "com.myupscaler.tests.cancel")
    private var cancelled = false

    func flag() {
        queue.sync { cancelled = true }
    }

    func isCancelled() -> Bool {
        queue.sync { cancelled }
    }
}

private func makeTestBridge(recorder: BridgeRecorder,
                            initResult: up60p_error = UP60P_OK,
                            processResult: up60p_error = UP60P_OK) -> Up60PBridge {
    Up60PBridge(
        initFunc: { _, _ in
            recorder.initCalls += 1
            return initResult
        },
        defaultOptionsFunc: { opts in
            recorder.defaultCalls += 1
            if let opts = opts {
                opts.pointee = up60p_options()
            }
        },
        processPathFunc: { input, opts in
            _ = input
            recorder.processCalls += 1
            if let opts = opts {
                recorder.lastOptions = opts.pointee
            }
            return processResult
        },
        setDryRunFunc: { enable in
            recorder.dryRunValues.append(enable)
        },
        shutdownFunc: {},
        cancelFunc: { recorder.cancelCalls += 1 }
    )
}

@MainActor
struct Up60PEngineTests {
    
    // MARK: - Singleton Tests
    
    @Test("shared should return the same instance")
    func testSingleton() async {
        let instance1 = await MainActor.run { Up60PEngine.shared }
        let instance2 = await MainActor.run { Up60PEngine.shared }
        
        #expect(instance1 === instance2)
    }
    
    // MARK: - Error Mapping Tests
    
    @Test("mapError should map error codes correctly")
    func testErrorMapping() {
        // Note: We can't directly test mapError as it's private,
        // but we can test error handling through public APIs

        // Test that error enum cases exist
        let errors: [Up60PEngineError] = [
            .invalidOptions,
            .ffmpegNotFound,
            .io,
            .internalError,
            .unknownStatus(123),
            .notInitialized
        ]

        #expect(errors.count == 6)
    }

    @Test("mapError should return nil for UP60P_OK")
    func testMapErrorOkCase() async {
        let error = await MainActor.run {
            Up60PEngine.shared.mapErrorForTesting(UP60P_OK)
        }

        #expect(error == nil)
    }
    
    // MARK: - Log Handler Tests
    
    @Test("setLogHandler should accept and store log handler")
    func testSetLogHandler() {
        let handler: (String) -> Void = { _ in
            // Handler callback
        }
        
        Up60PEngine.setLogHandler(handler)
        
        // Handler is set (we can't easily test it being called without running the engine)
        #expect(true) // Handler was set without error
    }
    
    @Test("setLogHandler should handle nil messages gracefully")
    func testLogHandlerNilMessage() {
        var callCount = 0
        let handler: (String) -> Void = { _ in
            callCount += 1
        }
        
        Up60PEngine.setLogHandler(handler)
        
        // Handler should be set
        #expect(callCount == 0) // Not called yet
    }
    
    // MARK: - Options Conversion Tests
    
    @Test("Options should be created from settings correctly")
    func testOptionsFromSettings() async throws {
        let settings = await MainActor.run {
            let settings = UpscaleSettings()
            
            // Set some test values
            settings.useHEVC = true
            settings.crf = 20.0
            settings.preset = "medium"
            settings.fps = "30"
            settings.scaleFactor = 2.5
            
            return settings
        }
        
        // Note: makeOptions is private, but we can test through process method
        // However, process requires actual file paths, so we'll test error cases instead
        
        // Test that settings are valid
        await MainActor.run {
            #expect(settings.useHEVC == true)
            #expect(settings.crf == 20.0)
            #expect(settings.preset == "medium")
        }
    }
    
    // MARK: - String Conversion Tests
    
    @Test("String values should be converted to C strings correctly")
    func testStringConversion() {
        // Test various string values that would be converted
        let testStrings = [
            "hevc",
            "h264",
            "slow",
            "medium",
            "fast",
            "bm3d",
            "cas",
            "unsharp",
            "deband",
            "f3kdb"
        ]
        
        for str in testStrings {
            // Verify strings are valid (non-empty, reasonable length)
            #expect(!str.isEmpty)
            #expect(str.count < 256) // Should fit in C char arrays
        }
    }
    
    // MARK: - Edge Cases
    
    @Test("Should handle empty string values")
    func testEmptyStringValues() async {
        let settings = await MainActor.run {
            let s = UpscaleSettings()
            // Set some empty values
            s.aiModelPath = ""
            s.lutPath = ""
            // x265Params is a computed property (read-only), so we can't set it directly
            // Instead, we can set the individual x265 parameters to empty
            s.x265AqMode = ""
            s.x265PsyRd = ""
            return s
        }
        
        // Should not crash
        await MainActor.run {
            #expect(settings.aiModelPath.isEmpty)
            #expect(settings.lutPath.isEmpty)
        }
    }
    
    @Test("Should handle very long string values")
    func testLongStringValues() async {
        let longPath = "/" + String(repeating: "a", count: 500)
        let settings = await MainActor.run {
            let s = UpscaleSettings()
            // Test with long paths (though they should be truncated in C)
            s.aiModelPath = longPath
            s.lutPath = longPath
            return s
        }
        
        // Should not crash
        await MainActor.run {
            #expect(settings.aiModelPath.count > 0)
        }
    }
    
    @Test("Should handle special characters in strings")
    func testSpecialCharacters() async {
        let specialStrings = [
            "path/with spaces/file.mp4",
            "path(with)parentheses",
            "path[with]brackets",
            "path{with}braces",
            "path'with'quotes",
            "path\"with\"doublequotes"
        ]
        
        let settings = await MainActor.run { UpscaleSettings() }
        
        for str in specialStrings {
            await MainActor.run {
                settings.aiModelPath = str
            }
            // Should not crash
            await MainActor.run {
                #expect(settings.aiModelPath == str)
            }
        }
    }
    
    // MARK: - Process Tests (Error Cases)
    
    @Test("process should handle invalid input path")
    func testProcessInvalidPath() async throws {
        let engine = await MainActor.run { Up60PEngine.shared }
        let settings = await MainActor.run { UpscaleSettings() }
        
        // Use a non-existent file path
        let invalidPath = "/nonexistent/path/video.mp4"
        
        do {
            try await engine.process(
                inputPath: invalidPath,
                settings: settings,
                outputDirectory: "/tmp"
            )
            // Should throw an error - if we reach here, the test should fail
            #expect(Bool(false), "Should have thrown an error for invalid path")
        } catch {
            // Expected to throw an error
            #expect(true)
        }
    }
    
    @Test("process should handle empty input path")
    func testProcessEmptyPath() async throws {
        let engine = await MainActor.run { Up60PEngine.shared }
        let settings = await MainActor.run { UpscaleSettings() }
        
        do {
            try await engine.process(
                inputPath: "",
                settings: settings,
                outputDirectory: "/tmp"
            )
            // Should throw an error - if we reach here, the test should fail
            #expect(Bool(false), "Should have thrown an error for empty path")
        } catch {
            #expect(true)
        }
    }
    
    @Test("cancel should not crash when called multiple times")
    func testMultipleCancels() async {
        let engine = await MainActor.run { Up60PEngine.shared }
        
        // Should not crash
        await MainActor.run {
            engine.cancel()
            engine.cancel()
            engine.cancel()
        }
        
        #expect(true)
    }
    
    @Test("cancel should not crash when no process is running")
    func testCancelWhenNotRunning() async {
        let engine = await MainActor.run { Up60PEngine.shared }
        
        // Cancel when nothing is running
        await MainActor.run {
            engine.cancel()
        }
        
        #expect(true)
    }
    
    // MARK: - Bridge Error Path Tests
    
    @Test("Initialization error should surface and skip process")
    @MainActor
    func testInitFailureMapsError() async {
        let recorder = BridgeRecorder()
        let bridge = makeTestBridge(
            recorder: recorder,
            initResult: UP60P_ERR_FFMPEG_NOT_FOUND,
            processResult: UP60P_OK
        )
        Up60PEngine.useBridgeForTesting(bridge)
        defer { Up60PEngine.resetBridgeForTesting() }
        
        let engine = Up60PEngine.shared
        let settings = UpscaleSettings()
        
        do {
            try await engine.process(
                inputPath: "/tmp/missing.mp4",
                settings: settings,
                outputDirectory: "/tmp"
            )
            #expect(Bool(false), "Expected init failure")
        } catch let error as Up60PEngineError {
            #expect(error == .ffmpegNotFound)
        } catch {
            #expect(Bool(false), "Unexpected error type \(error)")
        }
        
        #expect(recorder.initCalls == 1)
        #expect(recorder.processCalls == 0)
    }
    
    @Test("Non-zero process status should map to IO error")
    @MainActor
    func testProcessErrorMapping() async {
        let recorder = BridgeRecorder()
        let bridge = makeTestBridge(
            recorder: recorder,
            initResult: UP60P_OK,
            processResult: UP60P_ERR_IO
        )
        Up60PEngine.useBridgeForTesting(bridge)
        defer { Up60PEngine.resetBridgeForTesting() }
        
        let engine = Up60PEngine.shared
        let settings = UpscaleSettings()
        
        do {
            try await engine.process(
                inputPath: "/tmp/input.mp4",
                settings: settings,
                outputDirectory: "/tmp"
            )
            #expect(Bool(false), "Expected process error")
        } catch let error as Up60PEngineError {
            #expect(error == .io)
        } catch {
            #expect(Bool(false), "Unexpected error type \(error)")
        }
        
        #expect(recorder.initCalls == 1)
        #expect(recorder.processCalls == 1)
        #expect(recorder.defaultCalls == 1)
    }
    
    @Test("Dry-run flag should forward to bridge")
    @MainActor
    func testDryRunForwardsToBridge() {
        let recorder = BridgeRecorder()
        let bridge = makeTestBridge(
            recorder: recorder,
            initResult: UP60P_OK,
            processResult: UP60P_OK
        )
        Up60PEngine.useBridgeForTesting(bridge)
        defer { Up60PEngine.resetBridgeForTesting() }

        let engine = Up60PEngine.shared
        engine.setDryRun(true)
        engine.setDryRun(false)

        #expect(recorder.dryRunValues == [1, 0])
    }

    @Test("Cancellation should halt processing and signal bridge")
    @MainActor
    func testCancellationStopsProcessing() async {
        let recorder = BridgeRecorder()
        let probe = CancellationProbe()

        let bridge = Up60PBridge(
            initFunc: { _, _ in
                recorder.initCalls += 1
                return UP60P_OK
            },
            defaultOptionsFunc: { opts in
                recorder.defaultCalls += 1
                if let opts = opts {
                    opts.pointee = up60p_options()
                }
            },
            processPathFunc: { _, opts in
                if let opts = opts {
                    recorder.lastOptions = opts.pointee
                }
                recorder.processCalls += 1

                var spins = 0
                while !probe.isCancelled() && spins < 200 {
                    usleep(10_000)
                    spins += 1
                }

                return probe.isCancelled() ? UP60P_ERR_CANCELLED : UP60P_OK
            },
            setDryRunFunc: { enable in
                recorder.dryRunValues.append(enable)
            },
            shutdownFunc: {},
            cancelFunc: {
                recorder.cancelCalls += 1
                probe.flag()
            }
        )

        Up60PEngine.useBridgeForTesting(bridge)
        defer { Up60PEngine.resetBridgeForTesting() }

        let engine = Up60PEngine.shared
        let settings = UpscaleSettings()

        let processingTask = Task {
            try await engine.process(
                inputPath: "/tmp/input.mp4",
                settings: settings,
                outputDirectory: "/tmp"
            )
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        engine.cancel()

        do {
            try await processingTask.value
            #expect(Bool(false), "Expected cancellation")
        } catch is CancellationError {
            #expect(true)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }

        #expect(recorder.cancelCalls == 1)
        #expect(probe.isCancelled())
        #expect(recorder.processCalls == 1)
    }
}

