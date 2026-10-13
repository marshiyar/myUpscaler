import Foundation
import CoreML
import CoreVideo
import AVFoundation

@main struct CoreAIIntegrationSmoke {
    nonisolated static func input(_ shape: [Int]) throws -> sending MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        let data = array.dataPointer.assumingMemoryBound(to: Float.self)
        for i in 0..<array.count { data[i] = Float(i % 191 + 32) / 255 }
        return array
    }
    nonisolated static func clip(_ url: URL, width: Int, height: Int) async throws {
        let writer = try VideoFrameWriter(outputURL: url,
            videoSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height],
            width: width, height: height)
        for index in 0..<2 {
            let frame = try writer.makeFrame()
            try frame.withPixelBuffer { buffer in
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<height { for x in 0..<width {
                    let p = y * stride + x * 4
                    bytes[p] = UInt8(60 + x % 90); bytes[p + 1] = UInt8(70 + y % 90)
                    bytes[p + 2] = UInt8(100 + index * 10); bytes[p + 3] = 255
                } }
            }
            try await writer.append(frame.freeze(), at: CMTime(value: Int64(index), timescale: 24))
        }
        try await writer.finish()
    }
    nonisolated static func verify(_ url: URL, width: Int, height: Int) async throws {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        precondition(size == CGSize(width: width * 2, height: height * 2))
        let reader = try VideoFrameReader(asset: asset, track: track)
        var times: [Double] = []
        while let frame = try await reader.next() {
            times.append(frame.presentationTimeStamp.seconds)
            try frame.withPixelBuffer { buffer in
                let bytes = try CoreMLBufferAccess.lock(buffer, flags: .readOnly).assumingMemoryBound(to: UInt8.self)
                defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                // Edge tiles and overlap seams must be composed, including padded bottom/right.
                for (x, y) in [(0, 0), (width * 2 - 1, height * 2 - 1), (width, height)] {
                    let p = y * stride + x * 4
                    precondition(Int(bytes[p]) + Int(bytes[p + 1]) + Int(bytes[p + 2]) > 20)
                }
            }
        }
        precondition(times.count == 2)
        for i in times.indices { precondition(abs(times[i] - Double(i) / 24) < 0.001) }
    }
    @MainActor static func main() async throws {
        let settings = UpscaleSettings()
        let bundled = CoreMLModelRegistry.bundledModels
        precondition(bundled.filter { $0.backend == .coreAI }.count == 17)
        precondition(bundled.filter { $0.backend == .coreML }.count == 6)
        precondition(settings.upscaling.coremlModelId == .realESRGANx4)
        let manager = ModelManager()
        for spec in bundled {
            settings.upscalingChoice = .model(spec.id)
            precondition(settings.availableUpscalingChoices.contains(.model(spec.id)))
            let decoded = try JSONDecoder().decode(UpscaleSettingsSnapshot.self,
                from: JSONEncoder().encode(UpscaleSettingsSnapshot(settings: settings)))
            let roundtrip = UpscaleSettings(); decoded.apply(to: roundtrip)
            precondition(roundtrip.upscalingChoice == .model(spec.id))
            let layout = try await manager.prepareModel(spec: spec)
            precondition(spec.supportsTensorShapes(input: layout.inputShape, output: layout.outputShape))
            if spec.backend == .coreAI || spec.id == .realESRGANx2FP16 {
                let start = ProcessInfo.processInfo.systemUptime
                let buffer = try await manager.prediction(input: input(layout.inputShape), specID: spec.id,
                    inputName: layout.inputName, outputName: layout.outputName,
                    width: layout.outputShape[3], height: layout.outputShape[2])
                precondition(CVPixelBufferGetWidth(buffer) == layout.outputShape[3])
                precondition(CVPixelBufferGetHeight(buffer) == layout.outputShape[2])
                print("PASS prediction \(spec.id.rawValue): \(layout.inputShape) → \(layout.outputShape), Float\(layout.float32Input ? 32 : 16)/Float\(layout.float32Output ? 32 : 16), \(ProcessInfo.processInfo.systemUptime - start)s")
            } else { print("PASS CoreML load \(spec.id.rawValue)") }
            fflush(stdout)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (id, width, height) in [(CoreMLModelID.coreAIlocX2FP16, 146, 134), (.coreAIx8W8, 80, 48)] {
            let folder = root.appendingPathComponent(id.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("fixture.mp4")
            try await clip(url, width: width, height: height)
            let config = UpscaleSettings()
            config.upscalingChoice = .model(id); config.video.scaleFactor = 2
            config.primary.useDenoise = false; config.primary.useSharpen = false
            config.primary.useDering = false; config.primary.useDeband = false; config.primary.useGrain = false
            config.color.noEq = true; config.codec.useHEVC = false
            try await CoreMLEngine.shared.process(inputPath: url.path, settings: config, outputDirectory: folder.path)
            try await verify(folder.appendingPathComponent("fixture_[restored].mp4"), width: width, height: height)
            print("PASS tiled CoreAI export \(id.rawValue), two decoded frames, corners/seam, 2x dimensions and source24fps PTS")
            fflush(stdout)
        }
        print("PASS 23 selectable model identities/preset roundtrips, native CoreAI/CoreML loading and bounded predictions, Float16/Float32 I/O, x2/x4/x8, padded/multiple tiles and actual exports")
    }
}
