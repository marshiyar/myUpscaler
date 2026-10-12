import Foundation

/// Final dimensions depend only on the requested scale. A fixed-scale model
/// predicts each tile once at its native scale before any final resampling.
nonisolated struct UpscaleGeometry {
    let outputWidth: Int
    let outputHeight: Int
    let nativeTileWidth: Int
    let nativeTileHeight: Int
    let requiresResampling: Bool

    init(inputWidth: Int, inputHeight: Int, requestedScale: Double,
         nativeScale: Double, tileWidth: Int, tileHeight: Int) throws {
        guard inputWidth > 0, inputHeight > 0, tileWidth > 16, tileHeight > 16,
              requestedScale.isFinite, requestedScale > 0,
              nativeScale.isFinite, nativeScale > 0 else { throw Up60PEngineError.invalidOptions }
        func dimension(_ value: Int, _ scale: Double) throws -> Int {
            let scaled = Double(value) * scale
            guard scaled.isFinite, scaled >= 2, scaled < Double(Int.max / 4) else {
                throw Up60PEngineError.invalidOptions
            }
            // H.264/HEVC dimensions match the FFmpeg path's even-pixel rounding.
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
}
