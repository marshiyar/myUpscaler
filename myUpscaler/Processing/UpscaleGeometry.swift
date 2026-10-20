import Foundation
import CoreGraphics

/// Final dimensions depend only on the requested scale. A fixed-scale model
/// predicts each tile once at its native scale before any final resampling.
nonisolated struct UpscaleGeometry {
    let outputWidth: Int
    let outputHeight: Int
    let nativeTileWidth: Int
    let nativeTileHeight: Int
    let requiresResampling: Bool
    private let inputWidth: Int
    private let inputHeight: Int
    private let requestedScale: Double

    init(inputWidth: Int, inputHeight: Int, requestedScale: Double,
         nativeScale: Double, tileWidth: Int, tileHeight: Int) throws {
        guard inputWidth > 0, inputHeight > 0, tileWidth > 16, tileHeight > 16,
              requestedScale.isFinite, requestedScale > 0,
              nativeScale.isFinite, nativeScale > 0 else { throw Up60PEngineError.invalidOptions }
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.requestedScale = requestedScale
        func dimension(_ value: Int, _ scale: Double) throws -> Int {
            let scaled = Double(value) * scale
            guard scaled.isFinite, scaled >= 2, scaled < Double(Int.max / 4) else {
                throw Up60PEngineError.invalidOptions
            }
            // H.264/HEVC dimensions match the Rust engine's even-pixel rounding.
            return Int(scaled / 2) * 2
        }
        outputWidth = try dimension(inputWidth, requestedScale)
        outputHeight = try dimension(inputHeight, requestedScale)
        nativeTileWidth = try dimension(tileWidth, nativeScale)
        nativeTileHeight = try dimension(tileHeight, nativeScale)
        guard outputWidth <= Int.max / outputHeight / MemoryLayout<Float>.stride else {
            throw Up60PEngineError.invalidOptions
        }
        requiresResampling = requestedScale != nativeScale
    }

    /// Quantize both endpoints together so fractional scaling cannot leave gaps.
    func outputRegion(x: Int, y: Int, width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let left = min(outputWidth, Int(Double(x) * requestedScale))
        let top = min(outputHeight, Int(Double(y) * requestedScale))
        let right = min(outputWidth, Int(Double(x + width) * requestedScale))
        let bottom = min(outputHeight, Int(Double(y + height) * requestedScale))
        return (left, top, right - left, bottom - top)
    }

    /// Keep the source orientation and display origin while accommodating the
    /// output's even-pixel rounding. Standard rotated tracks remain at origin zero.
    func outputTransform(for source: CGAffineTransform) -> CGAffineTransform {
        let sourceBounds = CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight).applying(source)
        var result = CGAffineTransform(a: source.a, b: source.b, c: source.c, d: source.d, tx: 0, ty: 0)
        let outputBounds = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight).applying(result)
        result.tx = sourceBounds.minX * requestedScale - outputBounds.minX
        result.ty = sourceBounds.minY * requestedScale - outputBounds.minY
        return result
    }
}
