// Pre-fix blending implementation, retained only for parity and timing.
import Foundation
import CoreVideo
nonisolated extension CoreMLProcessingJob {
    func legacyBlendTileIntoCanvas(
        source: CVPixelBuffer,
        target: CVPixelBuffer,
        weightMap: UnsafeMutablePointer<Float>,
        destX: Int, destY: Int,
        width: Int, height: Int,
        margin: Int,
        useCosine: Bool,
        isLeft: Bool, isRight: Bool, isTop: Bool, isBottom: Bool
    ) throws {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(target, [])
        }

        guard let srcBase = CVPixelBufferGetBaseAddress(source),
              let dstBase = CVPixelBufferGetBaseAddress(target) else { return }

        let srcRowBytes = CVPixelBufferGetBytesPerRow(source)
        let dstRowBytes = CVPixelBufferGetBytesPerRow(target)
        let srcPtr = srcBase.assumingMemoryBound(to: UInt8.self)
        let dstPtr = dstBase.assumingMemoryBound(to: UInt8.self)
        let dstW = CVPixelBufferGetWidth(target)
        let dstH = CVPixelBufferGetHeight(target)
        let pi = Float.pi

        for r in 0..<height {
            let rowY = destY + r
            if rowY >= dstH { break }

            var wY: Float = 1.0
            if !isTop && r < margin {
                let t = Float(r) / Float(margin)
                wY = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
            } else if !isBottom && r >= height - margin {
                let t = Float(height - r) / Float(margin)
                wY = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
            }

            for c in 0..<width {
                let colX = destX + c
                if colX >= dstW { break }

                var wX: Float = 1.0
                if !isLeft && c < margin {
                    let t = Float(c) / Float(margin)
                    wX = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
                } else if !isRight && c >= width - margin {
                    let t = Float(width - c) / Float(margin)
                    wX = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
                }

                let weight = wX * wY
                let wIdx = rowY * dstW + colX
                let dstIdx = rowY * dstRowBytes + colX * 4
                let srcIdx = r * srcRowBytes + c * 4

                let sB = Float(srcPtr[srcIdx+0])
                let sG = Float(srcPtr[srcIdx+1])
                let sR = Float(srcPtr[srcIdx+2])

                let dB = Float(dstPtr[dstIdx+0])
                let dG = Float(dstPtr[dstIdx+1])
                let dR = Float(dstPtr[dstIdx+2])
                let curW = weightMap[wIdx]
                let newW = curW + weight

                if newW > 0.0 {
                    dstPtr[dstIdx+0] = UInt8(max(0, min(255, (dB * curW + sB * weight) / newW)))
                    dstPtr[dstIdx+1] = UInt8(max(0, min(255, (dG * curW + sG * weight) / newW)))
                    dstPtr[dstIdx+2] = UInt8(max(0, min(255, (dR * curW + sR * weight) / newW)))
                    dstPtr[dstIdx+3] = 255
                }
                weightMap[wIdx] = newW
            }
        }
    }
}
