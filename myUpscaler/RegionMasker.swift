import Foundation
import AVFoundation
import Accelerate

struct RegionMaskSample {
    let edge: Float
    let noise: Float
    let block: Float
    let band: Float
    let text: Float
}

struct RegionMaskSummary {
    let edge: Double
    let noise: Double
    let block: Double
    let band: Double
    let text: Double
}

struct RegionMaskContext {
    let width: Int
    let height: Int
    let edge: [Float]
    let noise: [Float]
    let block: [Float]
    let band: [Float]
    let text: [Float]
    
    func sample(normX: Double, normY: Double) -> RegionMaskSample {
        guard width > 0, height > 0 else {
            return RegionMaskSample(edge: 0, noise: 0, block: 0, band: 0, text: 0)
        }
        let x = Int(max(0, min(Double(width - 1), normX * Double(width - 1))))
        let y = Int(max(0, min(Double(height - 1), normY * Double(height - 1))))
        let idx = y * width + x
        return RegionMaskSample(
            edge: edge[idx],
            noise: noise[idx],
            block: block[idx],
            band: band[idx],
            text: text[idx]
        )
    }
    
    func summary() -> RegionMaskSummary {
        let count = max(1, width * height)
        func avg(_ arr: [Float]) -> Double {
            return Double(arr.reduce(0, +)) / Double(count)
        }
        return RegionMaskSummary(
            edge: avg(edge),
            noise: avg(noise),
            block: avg(block),
            band: avg(band),
            text: avg(text)
        )
    }
}

struct RegionMaskOutput {
    let context: RegionMaskContext?
    let summary: RegionMaskSummary
    let notes: [String]
}

//final class RegionMasker {
//    func analyze(inputPath: String, maxSamples: Int = 8) -> RegionMaskOutput {
//        guard FileManager.default.fileExists(atPath: inputPath) else {
//            return RegionMaskOutput(context: nil, summary: RegionMaskSummary(edge: 0, noise: 0, block: 0, band: 0, text: 0), notes: ["Region masks skipped (file missing)."])
//        }
//        
//        let url = URL(fileURLWithPath: inputPath)
//        let asset = AVAsset(url: url)
//        guard let track = asset.tracks(withMediaType: .video).first else {
//            return RegionMaskOutput(context: nil, summary: RegionMaskSummary(edge: 0, noise: 0, block: 0, band: 0, text: 0), notes: ["Region masks skipped (no video track)."])
//        }
//        
//        guard let reader = try? AVAssetReader(asset: asset) else {
//            return RegionMaskOutput(context: nil, summary: RegionMaskSummary(edge: 0, noise: 0, block: 0, band: 0, text: 0), notes: ["Region masks skipped (reader init failed)."])
//        }
//        
//        let outputSettings: [String: Any] = [
//            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
//        ]
//        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
//        reader.add(output)
//        
//        if !reader.startReading() {
//            return RegionMaskOutput(context: nil, summary: RegionMaskSummary(edge: 0, noise: 0, block: 0, band: 0, text: 0), notes: ["Region masks skipped (reader failed)."])
//        }
//        
//        var framesProcessed = 0
//        let fps = max(1, Int(max(1, Double(track.nominalFrameRate)).rounded()))
//        let stride = max(1, fps / 3)
//        
//        var accumEdge: [Double] = []
//        var accumNoise: [Double] = []
//        var accumBlock: [Double] = []
//        var accumBand: [Double] = []
//        var accumText: [Double] = []
//        var accumCount: [Int] = []
//        var gridW = 0
//        var gridH = 0
//        
//        var frameIndex = 0
//        while let sample = output.copyNextSampleBuffer() {
//            if frameIndex % stride == 0, let buffer = CMSampleBufferGetImageBuffer(sample) {
//                let result = computeMasks(from: buffer)
//                if accumEdge.isEmpty {
//                    gridW = result.gridW
//                    gridH = result.gridH
//                    let total = gridW * gridH
//                    accumEdge = Array(repeating: 0, count: total)
//                    accumNoise = Array(repeating: 0, count: total)
//                    accumBlock = Array(repeating: 0, count: total)
//                    accumBand = Array(repeating: 0, count: total)
//                    accumText = Array(repeating: 0, count: total)
//                    accumCount = Array(repeating: 0, count: total)
//                }
//                
//                for i in 0..<(gridW * gridH) {
//                    accumEdge[i] += Double(result.edge[i])
//                    accumNoise[i] += Double(result.noise[i])
//                    accumBlock[i] += Double(result.block[i])
//                    accumBand[i] += Double(result.band[i])
//                    accumText[i] += Double(result.text[i])
//                    accumCount[i] += 1
//                }
//                
//                framesProcessed += 1
//                if framesProcessed >= maxSamples { break }
//            }
//            frameIndex += 1
//        }
//        
//        reader.cancelReading()
//        
//        guard !accumEdge.isEmpty else {
//            return RegionMaskOutput(context: nil, summary: RegionMaskSummary(edge: 0, noise: 0, block: 0, band: 0, text: 0), notes: ["Region masks skipped (no frames read)."])
//        }
//        
//        let totalCells = gridW * gridH
//        var edgeArr = [Float](repeating: 0, count: totalCells)
//        var noiseArr = [Float](repeating: 0, count: totalCells)
//        var blockArr = [Float](repeating: 0, count: totalCells)
//        var bandArr = [Float](repeating: 0, count: totalCells)
//        var textArr = [Float](repeating: 0, count: totalCells)
//        
//        for i in 0..<totalCells {
//            let c = max(1, accumCount[i])
//            edgeArr[i] = Float(accumEdge[i] / Double(c))
//            noiseArr[i] = Float(accumNoise[i] / Double(c))
//            blockArr[i] = Float(accumBlock[i] / Double(c))
//            bandArr[i] = Float(accumBand[i] / Double(c))
//            textArr[i] = Float(accumText[i] / Double(c))
//        }
//        
//        let context = RegionMaskContext(
//            width: gridW,
//            height: gridH,
//            edge: edgeArr,
//            noise: noiseArr,
//            block: blockArr,
//            band: bandArr,
//            text: textArr
//        )
//        let summary = context.summary()
//        
//        var notes: [String] = []
//        if summary.edge > 0.25 { notes.append("Rich edges detected → preserve detail, moderate sharpen.") }
//        if summary.noise > 0.12 { notes.append("Noise pockets detected → local denoise boost.") }
//        if summary.block > 0.12 { notes.append("Blocking detected → local deblock boost.") }
//        if summary.band > 0.10 { notes.append("Banding risk → local deband boost.") }
//        if summary.text > 0.08 { notes.append("Text detected → reduce sharpen over text.") }
//        
//        return RegionMaskOutput(context: context, summary: summary, notes: notes)
//    }
//    
//    private struct GridMetrics {
//        let gridW: Int
//        let gridH: Int
//        let edge: [Float]
//        let noise: [Float]
//        let block: [Float]
//        let band: [Float]
//        let text: [Float]
//    }
//    
//    private func computeMasks(from buffer: CVPixelBuffer) -> GridMetrics {
//        CVPixelBufferLockBaseAddress(buffer, .readOnly)
//        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
//        
//        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
//            return GridMetrics(gridW: 1, gridH: 1, edge: [0], noise: [0], block: [0], band: [0], text: [0])
//        }
//        
//        let srcWidth = CVPixelBufferGetWidth(buffer)
//        let srcHeight = CVPixelBufferGetHeight(buffer)
//        
//        // Downscale to manageable size
//        let targetW = max(160, min(360, srcWidth / 2))
//        let targetH = max(160, min(360, srcHeight / 2))
//        
//        var srcBuffer = vImage_Buffer()
//        var destBuffer = vImage_Buffer()
//        srcBuffer.data = UnsafeMutableRawPointer(mutating: base)
//        srcBuffer.width = vImagePixelCount(srcWidth)
//        srcBuffer.height = vImagePixelCount(srcHeight)
//        srcBuffer.rowBytes = CVPixelBufferGetBytesPerRow(buffer)
//        
//        let bytesPerPixel = 4
//        let destRowBytes = targetW * bytesPerPixel
//        
//        // Use Swift array for memory safety to prevent aborts/crashes
//        var destData = [UInt8](repeating: 0, count: destRowBytes * targetH)
//        
//        let error = destData.withUnsafeMutableBufferPointer { bufferPtr -> vImage_Error in
//            guard let destBase = bufferPtr.baseAddress else { return kvImageMemoryAllocationError }
//            destBuffer.data = UnsafeMutableRawPointer(destBase)
//            destBuffer.width = vImagePixelCount(targetW)
//            destBuffer.height = vImagePixelCount(targetH)
//            destBuffer.rowBytes = destRowBytes
//            
//            return vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
//        }
//        
//        if error != kvImageNoError {
//            return GridMetrics(gridW: 1, gridH: 1, edge: [0], noise: [0], block: [0], band: [0], text: [0])
//        }
//        
//        let gridW = max(8, min(32, targetW / 16))
//        let gridH = max(8, min(32, targetH / 16))
//        let total = gridW * gridH
//        
//        var edge = [Float](repeating: 0, count: total)
//        var noise = [Float](repeating: 0, count: total)
//        var block = [Float](repeating: 0, count: total)
//        var band = [Float](repeating: 0, count: total)
//        var text = [Float](repeating: 0, count: total)
//        var counts = [Int](repeating: 0, count: total)
//        var lowGradCounts = [Int](repeating: 0, count: total)
//        
//        let rowBytes = destRowBytes
//        
//        for y in stride(from: 1, to: targetH - 1, by: 2) {
//            for x in stride(from: 1, to: targetW - 1, by: 2) {
//                let idx = y * rowBytes + x * bytesPerPixel
//                
//                // Safe bounds check
//                if idx + bytesPerPixel + rowBytes + 3 >= destData.count { continue }
//                
//                let b = Float(destData[idx + 0])
//                let g = Float(destData[idx + 1])
//                let r = Float(destData[idx + 2])
//                let l = 0.299 * r + 0.587 * g + 0.114 * b
//                
//                let rightIdx = idx + bytesPerPixel
//                let downIdx = idx + rowBytes
//                
//                let bR = Float(destData[rightIdx + 0])
//                let gR = Float(destData[rightIdx + 1])
//                let rR = Float(destData[rightIdx + 2])
//                let lR = 0.299 * rR + 0.587 * gR + 0.114 * bR
//                
//                let bD = Float(destData[downIdx + 0])
//                let gD = Float(destData[downIdx + 1])
//                let rD = Float(destData[downIdx + 2])
//                let lD = 0.299 * rD + 0.587 * gD + 0.114 * bD
//                
//                let grad = abs(l - lR) + abs(l - lD)
//                
//                // High-pass noise proxy
//                let avgLocal = (l + lR + lD) / 3.0
//                let hp = abs(l - avgLocal)
//                
//                // Blockiness on 8px boundaries
//                let onBlockEdge = (x % 8 == 0) || (y % 8 == 0)
//                let blockDelta = onBlockEdge ? grad : 0
//                
//                // Banding: count very low gradients
//                let isLowGrad = grad < 1.5
//                
//                // Text-ish: strong contrast and mid luma
//                let isTextish = (grad > 24) && (l > 32) && (l < 224)
//                
//                let cellX = min(gridW - 1, x * gridW / targetW)
//                let cellY = min(gridH - 1, y * gridH / targetH)
//                let cell = cellY * gridW + cellX
//                
//                edge[cell] += Float(min(1.0, grad / 64.0))
//                noise[cell] += Float(min(1.0, hp / 24.0))
//                if onBlockEdge { block[cell] += Float(min(1.0, blockDelta / 48.0)) }
//                if isLowGrad { lowGradCounts[cell] += 1 }
//                if isTextish { text[cell] += 0.5 }
//                counts[cell] += 1
//            }
//        }
//        
//        for i in 0..<total {
//            let c = max(1, counts[i])
//            edge[i] = min(1.0, edge[i] / Float(c))
//            noise[i] = min(1.0, noise[i] / Float(c))
//            block[i] = min(1.0, block[i] / Float(c))
//            let low = lowGradCounts[i]
//            band[i] = min(1.0, Float(low) / Float(c))
//            text[i] = min(1.0, text[i] / Float(c))
//        }
//        
//        return GridMetrics(gridW: gridW, gridH: gridH, edge: edge, noise: noise, block: block, band: band, text: text)
//    }
//}

extension UpscaleSettings {
    func regionAdjusted(using summary: RegionMaskSummary, enabled: Bool) -> UpscaleSettings {
        guard enabled else { return self }
        var tuned = self
        
        // Gentle deband/deblock boosts based on masks
        if summary.block > 0.12 {
            tuned.noDeblock = false
            tuned.deblockMode = "strong"
            tuned.deblockThresh = tuned.deblockThresh.isEmpty ? "0.5" : tuned.deblockThresh
            tuned.deringActive = true
            tuned.deringStrength = "0.6"
        }
        if summary.band > 0.10 {
            tuned.noDeband = false
            tuned.debandMethod = "f3kdb"
            tuned.debandStrength = tuned.debandStrength.isEmpty ? "0.0200" : tuned.debandStrength
            tuned.useDeband2 = true
            tuned.debandStrength2 = tuned.debandStrength2.isEmpty ? "0.0150" : tuned.debandStrength2
        }
        if summary.noise > 0.12 {
            tuned.noDenoise = false
            tuned.denoiser = "bm3d"
            tuned.denoiseStrength = tuned.denoiseStrength.isEmpty ? "3.0" : tuned.denoiseStrength
            tuned.useDenoise2 = true
            tuned.denoiseStrength2 = tuned.denoiseStrength2.isEmpty ? "2.0" : tuned.denoiseStrength2
        }
        if summary.text > 0.08 {
            // Ease off sharpening to avoid halos on text
            if let val = Double(tuned.sharpenStrength) {
                tuned.sharpenStrength = String(format: "%.3f", max(0.10, val * 0.8))
            }
        }
        return tuned
    }
}

