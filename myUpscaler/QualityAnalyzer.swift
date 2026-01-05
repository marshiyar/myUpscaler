import Foundation
import AVFoundation
import Accelerate

struct QualityMetrics {
    let noise: Double
    let blur: Double
    let blockiness: Double
    let banding: Double
}

struct QualityAnalysis {
    let metrics: QualityMetrics
    let notes: [String]
    
    var summaryLines: [String] {
        var lines: [String] = []
        let header = String(
            format: "Quality scan → noise=%.3f, blur=%.3f, block=%.3f, band=%.3f",
            metrics.noise,
            metrics.blur,
            metrics.blockiness,
            metrics.banding
        )
        lines.append(header)
        lines.append(contentsOf: notes)
        return lines
    }
}

private struct FrameStats {
    let noise: Double
    let blur: Double
    let blockiness: Double
    let banding: Double
}

final class QualityAnalyzer {
    func analyze(inputPath: String, maxSamples: Int = 12) -> QualityAnalysis {
        guard FileManager.default.fileExists(atPath: inputPath) else {
            return QualityAnalysis(metrics: QualityMetrics(noise: 0, blur: 0, blockiness: 0, banding: 0), notes: ["Quality scan skipped (file missing)."])
        }
        
        let url = URL(fileURLWithPath: inputPath)
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return QualityAnalysis(metrics: QualityMetrics(noise: 0, blur: 0, blockiness: 0, banding: 0), notes: ["Quality scan skipped (no video track)."])
        }
        
        guard let reader = try? AVAssetReader(asset: asset) else {
            return QualityAnalysis(metrics: QualityMetrics(noise: 0, blur: 0, blockiness: 0, banding: 0), notes: ["Quality scan skipped (reader init failed)."])
        }
        
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        
        if !reader.startReading() {
            return QualityAnalysis(metrics: QualityMetrics(noise: 0, blur: 0, blockiness: 0, banding: 0), notes: ["Quality scan skipped (reader failed)."])
        }
        
        var stats: [FrameStats] = []
        var frameIndex = 0
        let sampleStride = max(1, Int(max(1, Double(track.nominalFrameRate)).rounded()) / 3)
        
        while let sample = output.copyNextSampleBuffer() {
            if frameIndex % sampleStride == 0, let buffer = CMSampleBufferGetImageBuffer(sample) {
                let frameStat = computeStats(from: buffer)
                stats.append(frameStat)
                if stats.count >= maxSamples { break }
            }
            frameIndex += 1
        }
        
        reader.cancelReading()
        
        if stats.isEmpty {
            return QualityAnalysis(metrics: QualityMetrics(noise: 0, blur: 0, blockiness: 0, banding: 0), notes: ["Quality scan skipped (no frames read)."])
        }
        
        let noise = stats.map(\.noise).reduce(0, +) / Double(stats.count)
        let blur = stats.map(\.blur).reduce(0, +) / Double(stats.count)
        let blockiness = stats.map(\.blockiness).reduce(0, +) / Double(stats.count)
        let banding = stats.map(\.banding).reduce(0, +) / Double(stats.count)
        
        let metrics = QualityMetrics(noise: noise, blur: blur, blockiness: blockiness, banding: banding)
        var notes: [String] = []
        if noise > 0.12 { notes.append("High noise detected → prioritizing denoise.") }
        if blockiness > 0.12 { notes.append("Blocking/ringing detected → enabling deblock/dering.") }
        if banding > 0.08 { notes.append("Banding risk detected → enabling deband.") }
        if blur > 0.10 { notes.append("Blur detected → gently boosting sharpen.") }
        
        return QualityAnalysis(metrics: metrics, notes: notes)
    }
    
    private func computeStats(from buffer: CVPixelBuffer) -> FrameStats {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return FrameStats(noise: 0, blur: 0, blockiness: 0, banding: 0)
        }
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelCount = width * height
        let src = base.assumingMemoryBound(to: UInt8.self)
        
        var luma = [Float](repeating: 0, count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let b = Float(src[idx + 0])
                let g = Float(src[idx + 1])
                let r = Float(src[idx + 2])
                let yVal = 0.299 * r + 0.587 * g + 0.114 * b
                luma[y * width + x] = yVal
            }
        }
        
        var mean: Float = 0
        var meanSquare: Float = 0
        vDSP_meanv(luma, 1, &mean, vDSP_Length(pixelCount))
        vDSP_measqv(luma, 1, &meanSquare, vDSP_Length(pixelCount))
        let variance = max(0, meanSquare - mean * mean)
        let noise = sqrt(variance) / 255.0
        
        // Simple sharpness proxy: average gradient magnitude (sparse sampling)
        var gradSum: Float = 0
        var gradCount: Int = 0
        let step = max(1, min(4, width / 256))
        for y in stride(from: 1, to: height - 1, by: step) {
            for x in stride(from: 1, to: width - 1, by: step) {
                let c = luma[y * width + x]
                let gx = luma[y * width + (x + 1)] - c
                let gy = luma[(y + 1) * width + x] - c
                gradSum += abs(gx) + abs(gy)
                gradCount += 1
            }
        }
        let gradMean = gradCount > 0 ? gradSum / Float(gradCount) : 0
        let blur = max(0, 0.12 - Double(gradMean) / 255.0) // higher grad → lower blur
        
        var boundaryDiff: Float = 0
        var interiorDiff: Float = 0
        var boundaryCount = 0
        var interiorCount = 0
        for y in stride(from: 0, to: height - 1, by: 2) {
            for x in stride(from: 1, to: width - 1, by: 2) {
                let idx = y * width + x
                let delta = abs(luma[idx] - luma[idx - 1])
                if x % 8 == 0 {
                    boundaryDiff += delta
                    boundaryCount += 1
                } else {
                    interiorDiff += delta
                    interiorCount += 1
                }
            }
        }
        let boundaryMean = boundaryCount > 0 ? boundaryDiff / Float(boundaryCount) : 0
        let interiorMean = interiorCount > 0 ? interiorDiff / Float(interiorCount) : 1
        let blockiness = Double(max(0, boundaryMean - interiorMean)) / 64.0
        
        // Banding: ratio of near-flat gradients
        var flatCount: Int = 0
        var totalCount: Int = 0
        for y in stride(from: 0, to: height - 1, by: 2) {
            for x in stride(from: 0, to: width - 1, by: 2) {
                let idx = y * width + x
                let delta = abs(luma[idx] - luma[min(idx + 1, pixelCount - 1)])
                if delta < 1.5 { flatCount += 1 }
                totalCount += 1
            }
        }
        let banding = totalCount > 0 ? Double(flatCount) / Double(totalCount) : 0
        
        return FrameStats(
            noise: Double(noise),
            blur: blur,
            blockiness: min(1.0, blockiness),
            banding: min(1.0, banding)
        )
    }
}

extension UpscaleSettings {
    func tuned(using analysis: QualityAnalysis) -> UpscaleSettings {
        var tuned = self
        let m = analysis.metrics
        
        // Noise handling
        if m.noise > 0.12 {
            tuned.noDenoise = false
            tuned.denoiser = "bm3d"
            tuned.denoiseStrength = "3.0"
            tuned.useDenoise2 = true
            tuned.denoiseStrength2 = "2.0"
        } else if m.noise < 0.03 {
            tuned.useDenoise2 = false
        }
        
        // Blockiness / ringing
        if m.blockiness > 0.12 {
            tuned.noDeblock = false
            tuned.deblockMode = "strong"
            tuned.deblockThresh = tuned.deblockThresh.isEmpty ? "0.5" : tuned.deblockThresh
            tuned.deringActive = true
            tuned.deringStrength = "0.6"
        }
        
        // Banding
        if m.banding > 0.08 {
            tuned.noDeband = false
            tuned.debandMethod = "f3kdb"
            tuned.debandStrength = tuned.debandStrength.isEmpty ? "0.0200" : tuned.debandStrength
            tuned.useDeband2 = true
            tuned.debandStrength2 = tuned.debandStrength2.isEmpty ? "0.0150" : tuned.debandStrength2
        }
        
        // Blur → gently bump sharpen
        if m.blur > 0.10 {
            tuned.noSharpen = false
            if tuned.sharpenMethod == "cas" {
                tuned.sharpenStrength = String(format: "%.3f", min(0.6, (Double(tuned.sharpenStrength) ?? 0.25) + 0.1))
            } else {
                tuned.sharpenMethod = "cas"
                tuned.sharpenStrength = "0.35"
            }
        }
        
        return tuned
    }
}

