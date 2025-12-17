//
//  SystemTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
import Darwin
@testable import myUpscaler

struct SystemTests {
    
    private func setFFmpegEnv(_ path: String) throws {
        let result: Int32 = path.withCString { cstr in
            setenv("UP60P_FFMPEG", cstr, 1)
        }
        guard result == 0 else {
            let err = String(cString: strerror(errno))
            throw TestError("Failed to set UP60P_FFMPEG env var: \(err)")
        }
    }
    
    private func getFFmpegPath() throws -> String {
        let fm = FileManager.default
        
        // 1) Prefer the bundle that contains Up60PEngine (host app bundle in hosted tests)
        if let path = Bundle(for: Up60PEngine.self).path(forResource: "ffmpeg", ofType: nil),
           fm.isExecutableFile(atPath: path) {
            return path
        }
        
        // 2) Sometimes the main bundle is the host app (hosted tests)
        if let path = Bundle.main.path(forResource: "ffmpeg", ofType: nil),
           fm.isExecutableFile(atPath: path) {
            return path
        }
        
        // 3) Derive the host app Resources path from Xcode-provided env vars
        for key in ["TEST_HOST", "XCInjectBundleInto"] {
            if let host = ProcessInfo.processInfo.environment[key], !host.isEmpty {
                let hostURL = URL(fileURLWithPath: host)
                // e.g. .../MyApp.app/Contents/MacOS/MyApp -> .../MyApp.app/Contents/Resources/ffmpeg
                let resourcesFFmpeg = hostURL
                    .deletingLastPathComponent()   // MacOS
                    .deletingLastPathComponent()   // Contents
                    .appendingPathComponent("Resources/ffmpeg")
                    .path
                
                if fm.isExecutableFile(atPath: resourcesFFmpeg) {
                    return resourcesFFmpeg
                }
            }
        }
        
        // 4) As a last resort, scan the build products directory for any *.app containing Resources/ffmpeg
        let probeBundles: [URL] = [
            Bundle(for: SystemTests.self).bundleURL,
            Bundle(for: Up60PEngine.self).bundleURL,
            Bundle.main.bundleURL
        ]
        
        for bundleURL in probeBundles {
            let productsDir = bundleURL.deletingLastPathComponent()
            
            if let items = try? fm.contentsOfDirectory(at: productsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for appURL in items where appURL.pathExtension == "app" {
                    let candidate = appURL.appendingPathComponent("Contents/Resources/ffmpeg").path
                    if fm.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
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
        try setFFmpegEnv(ffmpegPath)
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
