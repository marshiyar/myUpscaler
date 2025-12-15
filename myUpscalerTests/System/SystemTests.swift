//
//  SystemTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import AVFoundation
import Darwin
import Testing
import Foundation
@testable import myUpscaler

struct SystemTests {

    private let requiredDylibs = [
        "libavcodec.62.dylib",
        "libavformat.62.dylib",
        "libavutil.60.dylib",
        "libavfilter.11.dylib",
        "libavdevice.62.dylib",
        "libswscale.9.dylib",
        "libswresample.6.dylib"
    ]

    private func ffmpegFrameworksDirectory() throws -> String {
        let fm = FileManager.default
        let bundle = Bundle(for: Up60PEngine.self)
        let candidates: [String] = [
            bundle.privateFrameworksPath,
            Bundle.main.privateFrameworksPath,
            bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("Frameworks").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path
        ].compactMap { $0 }

        if let dir = candidates.first(where: { fm.fileExists(atPath: $0) }) {
            return dir
        }

        throw TestError("FFmpeg dylibs not found in test environment")
    }

    private func generateTestVideo(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240
            ]
        )

        #expect(writer.canAdd(input))
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = 30
        for i in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            #expect(status == kCVReturnSuccess)
            guard let pixelBuffer = buffer else { throw TestError("Failed to allocate pixel buffer") }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                memset(base, (i * 3) % 255, bytesPerRow * height)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let time = CMTime(value: CMTimeValue(i), timescale: 30)
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishSemaphore.signal()
        }
        finishSemaphore.wait()

        guard writer.status == .completed else {
            throw TestError("Failed to generate test video: \(writer.error?.localizedDescription ?? "unknown error")")
        }
    }

    @Test("Bundled FFmpeg dylibs should exist")
    func testBundledFFmpegDylibs() throws {
        let frameworksDir = try ffmpegFrameworksDirectory()

        for lib in requiredDylibs {
            let path = (frameworksDir as NSString).appendingPathComponent(lib)
            #expect(FileManager.default.fileExists(atPath: path), "Missing \(lib)")
        }
    }
    
    @Test("Engine should process a real video file without hanging")
    func testEngineRealProcessing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input.mp4").path
        let outputDir = tempDir.appendingPathComponent("test_output").path
        
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: outputDir)
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        
        try generateTestVideo(at: inputPath)
        #expect(FileManager.default.fileExists(atPath: inputPath))

        // Ensure the in-process pipeline can see the dylibs when run from tests
        let frameworksDir = try ffmpegFrameworksDirectory()
        setenv("DYLD_LIBRARY_PATH", frameworksDir, 1)
        
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

