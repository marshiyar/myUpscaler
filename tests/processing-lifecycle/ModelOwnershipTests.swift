import Foundation
import CoreML
import CoreVideo
import AVFoundation
import Darwin

@main struct ModelOwnershipTests {
    nonisolated static func input(shape: [Int]) throws -> sending MLMultiArray {
        let tensor = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .float32)
        let values = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        values.update(repeating: 0.5, count: tensor.count)
        return tensor
    }
    nonisolated static func makeClip(at url: URL) async throws {
        let writer = try VideoFrameWriter(outputURL: url,
            videoSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48],
            width: 64, height: 48)
        for index in 0..<3 {
            let frame = try writer.makeFrame()
            try frame.withPixelBuffer { buffer in
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<48 { for x in 0..<64 {
                    let offset = y * stride + x * 4
                    bytes[offset] = UInt8(70 + index * 10); bytes[offset + 1] = 100
                    bytes[offset + 2] = 140; bytes[offset + 3] = 255
                } }
            }
            try await writer.append(frame.freeze(), at: CMTime(value: Int64(index), timescale: 24))
        }
        try await writer.finish()
    }
    nonisolated static func verifyClip(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        precondition(size.width == 128 && size.height == 96)
        let reader = try VideoFrameReader(asset: asset, track: track)
        var times: [CMTime] = []
        while let frame = try await reader.next() { times.append(frame.presentationTimeStamp) }
        precondition(times.count == 3)
        for index in times.indices {
            precondition(abs(times[index].seconds - Double(index) / 24) < 0.001)
        }
    }
    @MainActor static func main() async throws {
        let sourceBundle = Bundle(path: CommandLine.arguments[1])!
        let manager = ModelManager(bundle: sourceBundle)
        let x2 = CoreMLModelRegistry.model(for: .realESRGANx2)
        let spec = CoreMLModelRegistry.bundledURL(for: x2, bundle: sourceBundle) == nil
            ? CoreMLModelRegistry.model(for: .realESRGANx4) : x2
        let layout = try await manager.prepareModel(spec: spec)
        precondition(layout.float32Input && layout.float32Output)
        precondition(spec.supportsTensorShapes(input: layout.inputShape, output: layout.outputShape))
        let second = try await manager.prepareModel(spec: spec)
        precondition(layout.inputShape == second.inputShape && layout.outputShape == second.outputShape)
        var mainActorHeartbeats = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                mainActorHeartbeats += 1
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        defer { heartbeat.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<2 {
            let tensor = try input(shape: layout.inputShape)
            let buffer = try await manager.prediction(input: tensor, specID: spec.id,
                inputName: layout.inputName, outputName: layout.outputName,
                width: layout.outputShape[3], height: layout.outputShape[2])
            precondition(CVPixelBufferGetWidth(buffer) == layout.outputShape[3])
            precondition(CVPixelBufferGetHeight(buffer) == layout.outputShape[2])
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            precondition(bytes[3] == 255 && bytes[0] > 0 && bytes[0] < 255)
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        precondition(mainActorHeartbeats > 0, "UI actor must run while inference executes")
        let predictionElapsed = ProcessInfo.processInfo.systemUptime - start
        let predictionHeartbeats = mainActorHeartbeats
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        print("Starting synthetic input"); fflush(stdout)
        let clip = directory.appendingPathComponent("input.mp4")
        try await makeClip(at: clip)
        let settings = UpscaleSettings()
        var configuration = settings.configuration
        configuration.upscaling.coremlModelId = spec.id
        configuration.video.scaleFactor = 2
        settings.replaceConfiguration(configuration)
        print("Starting real engine"); fflush(stdout)
        let engine = CoreMLEngine()
        try await engine.process(inputPath: clip.path, settings: settings, outputDirectory: directory.path)
        let rendered = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "mp4" && $0.lastPathComponent != clip.lastPathComponent }!
        print("Verifying exported clip \(rendered.path)"); fflush(stdout)
        try await verifyClip(at: rendered)
        let sourceDuration = try await AVURLAsset(url: clip).load(.duration).seconds
        let outputDuration = try await AVURLAsset(url: rendered).load(.duration).seconds
        precondition(abs(sourceDuration - outputDuration) <= 1.0 / 24)
        print("Testing cancellation"); fflush(stdout)
        let cancelled = Task { try await engine.process(inputPath: clip.path, settings: settings, outputDirectory: directory.path) }
        await Task.yield()
        engine.cancel(); cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("Cancelled run unexpectedly completed") }
        catch is CancellationError { }
        print("PASS real CoreML export: 3 frames, 128x96, preserved 24fps timestamps and duration, cancellation")
        print("PASS actor-owned existing \(spec.resourceName) model, repeated metadata/predictions, sending tensors/pixels, UI actor heartbeats=\(predictionHeartbeats), seconds=\(predictionElapsed)")
    }
}
