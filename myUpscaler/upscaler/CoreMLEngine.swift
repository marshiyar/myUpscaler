import Foundation
import AVFoundation
import CoreML
import VideoToolbox
import CoreVideo
import CoreImage
import Accelerate

enum CoreMLModelID: String, CaseIterable, Codable, Hashable {
    case realESRGANx2 = "RealESRGAN_x2"
    case realESRGANx4 = "RealESRGAN_x4"
    case realESRGANx8 = "RealESRGAN_x8"
}

struct CoreMLModelSpec: Identifiable, Hashable {
    let id: CoreMLModelID
    let displayName: String
    let resourceName: String
    let nativeScale: Double
}

enum CoreMLModelRegistry {
    static let models: [CoreMLModelSpec] = [
        CoreMLModelSpec(id: .realESRGANx2, displayName: "Real-ESRGAN x2", resourceName: "RealESRGAN_x2", nativeScale: 2.0),
        CoreMLModelSpec(id: .realESRGANx4, displayName: "Real-ESRGAN x4", resourceName: "RealESRGAN_x4", nativeScale: 4.0),
        CoreMLModelSpec(id: .realESRGANx8, displayName: "Real-ESRGAN x8", resourceName: "RealESRGAN_x8", nativeScale: 8.0)
    ]
    
    static var defaultModel: CoreMLModelSpec { models.first(where: { $0.id == .realESRGANx4 }) ?? models[0] }
    
    static func model(for id: CoreMLModelID) -> CoreMLModelSpec {
        models.first(where: { $0.id == id }) ?? defaultModel
    }
}

// MARK: - Model Manager

enum ModelError: Error {
    case compilationFailed(Error)
    case modelNotFound
    case invalidModel
    case fileSystemError(Error)
}

class ModelManager {
    static let shared = ModelManager()
    private init() {}
    
    private func bundledModelURL(resourceName: String) -> URL? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") { return url }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") { return url }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") { return url }
        return nil
    }
    
    private func sourceModelURL(resourceName: String) -> URL? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") { return url }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") { return url }
        return nil
    }
    
    func prepareModel(spec: CoreMLModelSpec, progressHandler: ((Double) -> Void)? = nil) async throws -> MLModel {
        
        var config = MLModelConfiguration()
        
        
        
        
        config.computeUnits = .all
        config.allowLowPrecisionAccumulationOnGPU = true
        
        guard let modelURL = bundledModelURL(resourceName: spec.resourceName) else {
            throw ModelError.modelNotFound
        }
        let sourceURL = sourceModelURL(resourceName: spec.resourceName)
        
        progressHandler?(0.5)
        
        do {
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            progressHandler?(1.0)
            return model
        } catch {
            print("DEBUG: Failed to load model with .all compute units. Retry compiling...")
            
            if let src = sourceURL ?? (modelURL.pathExtension != "mlmodelc" ? modelURL : nil) {
                let compiledURL = try await MLModel.compileModel(at: src)
                let compiledModel = try MLModel(contentsOf: compiledURL, configuration: config)
                progressHandler?(1.0)
                return compiledModel
            }
            
            config.computeUnits = .cpuOnly
            config.allowLowPrecisionAccumulationOnGPU = false
            if let model = try? MLModel(contentsOf: modelURL, configuration: config) {
                progressHandler?(1.0)
                return model
            }
            throw ModelError.invalidModel
        }
    }
}

// MARK: - CoreML Engine

class CoreMLEngine: EngineProtocol {
    static let shared = CoreMLEngine()
    
    private var logHandler: ((String) -> Void)?
    private var isCancelled = false
    var regionContext: RegionMaskContext?
    var driftGuardEnabled: Bool = false
    
    func setLogHandler(_ handler: @escaping (String) -> Void) {
        self.logHandler = handler
    }
    
    private func log(_ message: String) {
        logHandler?(message)
    }
    
    func cancel() {
        isCancelled = true
    }
    
    private func logEffectiveKnobs(settings: UpscaleSettings, useHEVC: Bool) {
        let feather = settings.tileFeatherMarginValue > 0
        let featherNote = feather ? "\(settings.tileFeatherMarginValue)px" : "off"
        log("CoreML honors: model=\(settings.coremlModelId.rawValue), scale=\(settings.scaleFactor)x, codec=\(useHEVC ? "hevc" : "h264"), crf=\(Int(settings.crf)), tile feather=\(featherNote).\n")
    }
    
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        isCancelled = false
        log("CoreML Engine: Starting processing...\n")
        let codecDecision = CodecSupport.resolve(requestHEVC: settings.useHEVC)
        
        // FIX: Force Linearize OFF for Real-ESRGAN to prevent dark/washed-out results
        if settings.coremlModelId.rawValue.contains("RealESRGAN") {
            settings.enableColorLinearize = false
            settings.enableToneMap = false
            settings.encodeToSRGB = false
        }
        
        logEffectiveKnobs(settings: settings, useHEVC: codecDecision.useHEVC)
        let modelSpec = CoreMLModelRegistry.model(for: settings.coremlModelId)
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: inputURL)
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw Up60PEngineError.io
        }
        
        log("Loading AI Model (\(modelSpec.displayName))...\n")
        let mlModel = try await ModelManager.shared.prepareModel(spec: modelSpec)
        
        let modelDescription = mlModel.modelDescription
        guard let inputName = modelDescription.inputDescriptionsByName.keys.first,
              let outputName = modelDescription.outputDescriptionsByName.keys.first,
              let inputDescription = modelDescription.inputDescriptionsByName[inputName],
              let multiArrayConstraint = inputDescription.multiArrayConstraint else {
            throw Up60PEngineError.internalError
        }
        
        let modelInputShape = multiArrayConstraint.shape
        let modelInputChannels = modelInputShape[1].intValue
        let tileHeight = modelInputShape[2].intValue
        let tileWidth = modelInputShape[3].intValue
        
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)
        reader.startReading()
        
        let inputFilename = inputURL.deletingPathExtension().lastPathComponent
        let outputFilename = inputFilename + "_[restored].mp4"
        let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(outputFilename)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        let userScaleFactor = CGFloat(settings.scaleFactor)
        let modelScaleFactor = CGFloat(modelSpec.nativeScale)
        
        let inputSize = try await videoTrack.load(.naturalSize)
        let outputWidth = inputSize.width * userScaleFactor
        let outputHeight = inputSize.height * userScaleFactor
        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
        
        let pixelCount = Double(outputWidth * outputHeight)
        let crfScale = 1.5 - (Double(settings.crf) / 51.0)
        let targetBitrate = Int(pixelCount * 0.15 * crfScale)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codecDecision.useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.mediaTimeScale = CMTimeScale(originalFrameRate * 1000)
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let tileOverlap = 16
        let effectiveTileSize = tileWidth - tileOverlap
        let tilesX = max(1, Int(ceil(Double(Int(inputSize.width) - tileOverlap) / Double(effectiveTileSize))))
        let tilesY = max(1, Int(ceil(Double(Int(inputSize.height) - tileOverlap) / Double(effectiveTileSize))))
        
        let predictionOptions = MLPredictionOptions()
//        predictionOptions.usesCPUOnly = false
        
        var frameCount = 0
        var previousFrameBuffer: CVPixelBuffer? = nil
        
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if isCancelled { break }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            guard let outputBuffer = try? createPixelBuffer(width: Int(outputWidth), height: Int(outputHeight)) else { continue }
            
            // FIX: Manual memory management with defer to prevent Double Free
            guard let weightBuffer = try? createWeightBuffer(width: Int(outputWidth), height: Int(outputHeight)) else { continue }
            defer { weightBuffer.deallocate() } // Automatically freed at end of this loop iteration
            
            var tilesFailed = 0
            
            for tileY in 0..<tilesY {
                for tileX in 0..<tilesX {
                    if isCancelled { break }
                    
                    let x = min(tileX * effectiveTileSize, max(0, Int(inputSize.width) - tileWidth))
                    let y = min(tileY * effectiveTileSize, max(0, Int(inputSize.height) - tileHeight))
                    let w = min(tileWidth, Int(inputSize.width) - x)
                    let h = min(tileHeight, Int(inputSize.height) - y)
                    
                    guard let tileBuffer = try? extractTile(from: pixelBuffer, x: x, y: y, width: w, height: h, targetWidth: tileWidth, targetHeight: tileHeight) else { continue }
                    
                    preprocessTileBuffer(tileBuffer, settings: settings)
                    
                    guard let inputTensor = try? pixelBufferToTensor(pixelBuffer: tileBuffer, inputName: inputName, expectedChannels: modelInputChannels) else { continue }
                    
                    let inputProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputTensor])
                    
                    if let prediction = try? await mlModel.prediction(from: inputProvider, options: predictionOptions),
                       let outputFeature = prediction.featureValue(for: outputName),
                       let outputTensor = outputFeature.multiArrayValue {
                        
                        // High Quality Resampling Logic
                        let nativeTileW = tileWidth * Int(modelScaleFactor)
                        let nativeTileH = tileHeight * Int(modelScaleFactor)
                        
                        if let nativeBuffer = try? tensorToPixelBuffer(tensor: outputTensor, width: nativeTileW, height: nativeTileH) {
                            
                            let outX = Int(Double(x) * Double(userScaleFactor))
                            let outY = Int(Double(y) * Double(userScaleFactor))
                            let outW = Int(Double(w) * Double(userScaleFactor))
                            let outH = Int(Double(h) * Double(userScaleFactor))
                            
                            var finalTileBuffer = nativeBuffer
                            if abs(Double(userScaleFactor) - Double(modelScaleFactor)) > 0.001 {
                                if let scaled = try? resizePixelBuffer(nativeBuffer, width: outW, height: outH) {
                                    finalTileBuffer = scaled
                                }
                            }
                            
                            let blendMargin = max(1, settings.tileFeatherMarginValue > 0 ? settings.tileFeatherMarginValue : Int(Double(tileOverlap) * Double(userScaleFactor)))
                            
                            try? blendTileIntoCanvas(
                                source: finalTileBuffer,
                                target: outputBuffer,
                                weightMap: weightBuffer,
                                destX: outX, destY: outY,
                                width: outW, height: outH,
                                margin: blendMargin,
                                useCosine: settings.useCosineFeather,
                                isLeft: tileX == 0, isRight: tileX == tilesX - 1,
                                isTop: tileY == 0, isBottom: tileY == tilesY - 1
                            )
                        } else {
                            tilesFailed += 1
                        }
                    } else {
                        tilesFailed += 1
                    }
                }
            }
            
            postprocessFrameBuffer(outputBuffer, previous: previousFrameBuffer, settings: settings)
            
            while !writerInput.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            pixelBufferAdaptor.append(outputBuffer, withPresentationTime: pts)
            previousFrameBuffer = outputBuffer
            frameCount += 1
            if frameCount % 10 == 0 { log("Processed frame \(frameCount)\n") }
        }
        
        writerInput.markAsFinished()
        await writer.finishWriting()
        log("Done. Output saved to: \(outputURL.path)\n")
    }
    
    // MARK: - Helper Methods
    
    private func createPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { throw Up60PEngineError.internalError }
        return buffer
    }
    
    private func createWeightBuffer(width: Int, height: Int) throws -> UnsafeMutablePointer<Float> {
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: width * height)
        buffer.initialize(repeating: 0, count: width * height)
        return buffer
    }
    
    private func extractTile(from sourceBuffer: CVPixelBuffer, x: Int, y: Int, width: Int, height: Int, targetWidth: Int, targetHeight: Int) throws -> CVPixelBuffer {
        let tileBuffer = try createPixelBuffer(width: targetWidth, height: targetHeight)
        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(tileBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(tileBuffer, [])
        }
        
        guard let srcBase = CVPixelBufferGetBaseAddress(sourceBuffer),
              let dstBase = CVPixelBufferGetBaseAddress(tileBuffer) else { return tileBuffer }
        
        let srcBytes = CVPixelBufferGetBytesPerRow(sourceBuffer)
        let dstBytes = CVPixelBufferGetBytesPerRow(tileBuffer)
        let srcData = srcBase.assumingMemoryBound(to: UInt8.self)
        let dstData = dstBase.assumingMemoryBound(to: UInt8.self)
        
        memset(dstBase, 0, dstBytes * targetHeight) // Zero init padding
        
        for row in 0..<height {
            let srcOffset = (y + row) * srcBytes + x * 4
            let dstOffset = row * dstBytes
            memcpy(dstData + dstOffset, srcData + srcOffset, width * 4)
        }
        return tileBuffer
    }
    
    private func pixelBufferToTensor(pixelBuffer: CVPixelBuffer, inputName: String, expectedChannels: Int) throws -> MLMultiArray {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelCount = width * height
        
        let channels = 3
        let shape = [1, NSNumber(value: channels), NSNumber(value: height), NSNumber(value: width)]
        let tensor = try MLMultiArray(shape: shape, dataType: .float32)
        
        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw Up60PEngineError.internalError }
        let srcData = baseAddr.assumingMemoryBound(to: UInt8.self)
        let tensorPtr = UnsafeMutablePointer<Float>(OpaquePointer(tensor.dataPointer))
        
        // Fast Plane Separation (BGR -> RGB Planar)
        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = y * bytesPerRow + x * 4
                let dstIdx = y * width + x
                // BGRA -> RGB Planar
                tensorPtr[dstIdx] = Float(srcData[srcIdx + 2]) / 255.0 // R
                tensorPtr[pixelCount + dstIdx] = Float(srcData[srcIdx + 1]) / 255.0 // G
                tensorPtr[pixelCount * 2 + dstIdx] = Float(srcData[srcIdx + 0]) / 255.0 // B
            }
        }
        return tensor
    }
    
    private func tensorToPixelBuffer(tensor: MLMultiArray, width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try createPixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelCount = width * height
        let tensorPtr = UnsafePointer<Float>(OpaquePointer(tensor.dataPointer))
        
        guard let baseAddr = CVPixelBufferGetBaseAddress(buffer) else { throw Up60PEngineError.internalError }
        let dstData = baseAddr.assumingMemoryBound(to: UInt8.self)
        
        // Fast Plane Merging (RGB Planar -> BGRA)
        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = y * width + x
                let dstIdx = y * bytesPerRow + x * 4
                
                let r = tensorPtr[srcIdx]
                let g = tensorPtr[pixelCount + srcIdx]
                let b = tensorPtr[pixelCount * 2 + srcIdx]
                
                dstData[dstIdx + 0] = UInt8(max(0, min(255, b * 255.0))) // B
                dstData[dstIdx + 1] = UInt8(max(0, min(255, g * 255.0))) // G
                dstData[dstIdx + 2] = UInt8(max(0, min(255, r * 255.0))) // R
                dstData[dstIdx + 3] = 255 // A
            }
        }
        return buffer
    }
    
    private func resizePixelBuffer(_ source: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
        let dest = try createPixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dest, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(dest, [])
        }
        
        guard let srcBase = CVPixelBufferGetBaseAddress(source),
              let dstBase = CVPixelBufferGetBaseAddress(dest) else { throw Up60PEngineError.internalError }
        
        var srcVImage = vImage_Buffer(
            data: srcBase,
            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )
        
        var destVImage = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(dest)
        )
        
        vImageScale_ARGB8888(&srcVImage, &destVImage, nil, vImage_Flags(kvImageHighQualityResampling))
        return dest
    }
    
    private func blendTileIntoCanvas(
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
