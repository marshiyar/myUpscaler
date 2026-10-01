import AVFoundation
import CoreVideo
import Foundation

enum Up60PEngineError: Error { case invalidOptions }

/// Synthetic buffers exercise writer metadata without models or source decoding.
@main struct UpscaleOrientationRegression {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let geometry = try UpscaleGeometry(inputWidth: 64, inputHeight: 48,
            requestedScale: 1.3, nativeScale: 4, tileWidth: 64, tileHeight: 64)
        let source = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0)
        let expected = geometry.outputTransform(for: source)
        for legacy in [false, true] {
            let url = root.appendingPathComponent(legacy ? "legacy.mp4" : "modern.mp4")
            let writer = try VideoFrameWriter(outputURL: url,
                videoSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: geometry.outputWidth, AVVideoHeightKey: geometry.outputHeight],
                width: geometry.outputWidth, height: geometry.outputHeight,
                transform: expected, forceLegacy: legacy)
            for frame in 0..<3 {
                let buffer = try writer.makePixelBuffer()
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                try await writer.append(buffer, at: CMTime(value: Int64(frame), timescale: 30))
            }
            try await writer.finish()
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .video)[0]
            let transform = try await track.load(.preferredTransform)
            precondition(transform == expected)
            let size = try await track.load(.naturalSize)
            precondition(size.width == CGFloat(geometry.outputWidth) && size.height == CGFloat(geometry.outputHeight))
            let bounds = CGRect(origin: .zero, size: size).applying(transform)
            precondition(bounds.minX == 0 && bounds.minY == 0)
            precondition(bounds.width == 62 && bounds.height == 82)
            print("PASS \(legacy ? "legacy" : "modern") writer: fractional rounded dimensions and source rotation metadata")
        }
    }
}
