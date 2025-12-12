//
//  SystemTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
@testable import myUpscaler

struct SystemTests {
    
    private func getFFmpegPath() throws -> String {
        if let path = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return path
        }
        
        let bundleURL = Bundle(for: Up60PEngine.self).bundleURL
        let productsDir = bundleURL.deletingLastPathComponent()
        let appBundlePath = productsDir.appendingPathComponent("myUpscaler.app").appendingPathComponent("Contents/Resources/ffmpeg").path
        
        if FileManager.default.fileExists(atPath: appBundlePath) {
            return appBundlePath
        }
        
        throw TestError("FFmpeg not found in test environment")
    }
    
    private func generateTestVideo(at path: String, ffmpegPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-f", "lavfi",
            "-i", "testsrc=duration=1:size=1280x720:rate=30",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-y",
            path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw TestError("Failed to generate test video. Exit code: \(process.terminationStatus)")
        }
    }
    
    @Test("Bundled FFmpeg should exist and be executable")
    func testBundledFFmpeg() throws {
        let path = try getFFmpegPath()
        
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        #expect(process.terminationStatus == 0)
        #expect(output.contains("ffmpeg version"))
    }
    
    @Test("Engine should process a real video file without hanging")
    func testEngineRealProcessing() async throws {
        let ffmpegPath = try getFFmpegPath()
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input.mp4").path
        let outputDir = tempDir.appendingPathComponent("test_output").path
        
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: outputDir)
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        
        try await generateTestVideo(at: inputPath, ffmpegPath: ffmpegPath)
        #expect(FileManager.default.fileExists(atPath: inputPath))
        
        let engine = await MainActor.run { Up60PEngine.shared }
        let settings = await MainActor.run {
            let s = UpscaleSettings()
            s.scaleFactor = 1.0
            s.noDenoise = true
            s.noDeblock = true
            s.noSharpen = true
            s.noDeband = true
            s.fps = "30"
            s.preset = "ultrafast"
            s.encoder = "cpu"
            return s
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await engine.process(
                    inputPath: inputPath,
                    settings: settings,
                    outputDirectory: outputDir
                )
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds timeout
                throw TestError("Timeout: Engine did not finish in time")
            }
            
            try await group.next()
            group.cancelAll()
        }
        
        let expectedOutput = outputDir + "/test_input_[restored].mp4"
        #expect(FileManager.default.fileExists(atPath: expectedOutput))
        
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: outputDir)
    }
}

struct TestError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

