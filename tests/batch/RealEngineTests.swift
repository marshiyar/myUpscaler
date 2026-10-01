import Foundation
import AVFoundation
import CoreVideo

@main struct RealBatchTests {
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
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try fm.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try await makeClip(at: source.appendingPathComponent("clip.MOV"))
        try await makeClip(at: source.appendingPathComponent("nested/clip.mp4"))
        let backends = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : ["lanczos", "coreml"]
        precondition(backends.allSatisfy { ["lanczos", "coreml"].contains($0) })
        for backend in backends {
            let runner = UpscaleRunner()
            runner.inputPath = source.path
            runner.customOutputFolder = root.appendingPathComponent(backend).path
            var config = runner.settings.configuration
            config.upscaling.scaler = backend
            config.upscaling.coremlModelId = .realESRGANx4
            config.video.scaleFactor = 2; config.video.fps.text = "24"; config.modes.noInterpolate = true
            config.primary.useDenoise = false; config.primary.useSharpen = false
            config.primary.useDeblock = false; config.primary.useDeband = false; config.primary.useGrain = false
            config.hardware.encoder = "cpu"; config.hardware.hwAccel = "none"; config.codec.useHEVC = false
            runner.settings.replaceConfiguration(config)
            runner.run(); runner.run()
            let deadline = Date().addingTimeInterval(120)
            while runner.isRunning {
                guard Date() < deadline else { runner.cancel(); throw BatchPlan.Failure("Engine batch timed out: " + runner.log) }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let folder = runner.completedOutputPath else { throw BatchPlan.Failure(backend + " batch failed: " + runner.log) }
            precondition(runner.batchTotal == 2 && runner.batchCompleted == 2 && runner.progress == 1)
            for relative in ["clip_[restored].mp4", "nested/clip_[restored].mp4"] {
                try await verifyClip(at: URL(fileURLWithPath: folder).appendingPathComponent(relative))
            }
            print("PASS actual \(backend) folder export: uppercase and nested duplicate basenames, 2 outputs, decoded 3 frames each, 128x96, preserved 24fps timestamps")
        }
    }
}
