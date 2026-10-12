import Foundation
import AVFoundation
import CoreVideo

@main struct VideoIORegression {
    static func main() async {
        do { try await run() }
        catch {
            fputs("FAIL/BLOCKED: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for legacy in [true, false] {
            let url = root.appendingPathComponent("\(legacy).mp4")
            let start = ContinuousClock.now
            let writer = try VideoFrameWriter(outputURL: url, videoSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64, AVVideoHeightKey: 48
            ], width: 64, height: 48, forceLegacy: legacy)
            for index in 0..<30 {
                let buffer = try writer.makePixelBuffer()
                CVPixelBufferLockBaseAddress(buffer, [])
                let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<48 { for x in 0..<64 {
                    let offset = y * stride + x * 4
                    bytes[offset] = UInt8(32 + index)
                    bytes[offset + 1] = 96
                    bytes[offset + 2] = 192
                    bytes[offset + 3] = 255
                } }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                try await writer.append(buffer, at: CMTime(value: Int64(index), timescale: 30))
            }
            try await writer.finish()
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let reader = try VideoFrameReader(asset: asset, track: tracks[0], forceLegacy: legacy)
            var count = 0
            while let sample = try await reader.next() {
                precondition(CMSampleBufferGetPresentationTimeStamp(sample) == CMTime(value: Int64(count), timescale: 30))
                let buffer = CMSampleBufferGetImageBuffer(sample)!
                precondition(CVPixelBufferGetWidth(buffer) == 64 && CVPixelBufferGetHeight(buffer) == 48)
                CVPixelBufferLockBaseAddress(buffer, .readOnly)
                let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
                precondition(Int(bytes[2]) > Int(bytes[1]) + 40)
                precondition(Int(bytes[1]) > Int(bytes[0]) + 10)
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                count += 1
            }
            precondition(count == 30)
            let cancelledReader = try VideoFrameReader(asset: asset, track: tracks[0], forceLegacy: legacy)
            cancelledReader.cancel()
            do { _ = try await cancelledReader.next(); fatalError("Cancelled reader must fail") }
            catch { }
            let cancelledWriter = try VideoFrameWriter(outputURL: root.appendingPathComponent("cancel-\(legacy).mp4"),
                videoSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48],
                width: 64, height: 48, forceLegacy: legacy)
            let pendingBuffer = try cancelledWriter.makePixelBuffer()
            cancelledWriter.cancel()
            do { try await cancelledWriter.append(pendingBuffer, at: .zero); fatalError("Cancelled writer must fail") }
            catch { }
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                _ = try await reader.next()
            }
            do { try await task.value; fatalError("Task cancellation must fail") }
            catch is CancellationError { }
            print("PASS \(legacy ? "legacy" : "modern") 30 frames, exact PTS, dimensions, BGRA colors, reader/writer/task cancellation; \(start.duration(to: .now))")
        }
    }
}
