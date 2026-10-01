import Foundation
import AVFoundation
import CoreML
import VideoToolbox
import CoreVideo
import CoreImage
import Accelerate

// MARK: - Model Manager

nonisolated enum ModelError: Error {
    case compilationFailed(Error)
    case modelNotFound
    case invalidModel
    case fileSystemError(Error)
}

nonisolated class ModelManager {
    static let shared = ModelManager()
    private init() {}
    private let cacheLock = NSLock()
    private var cachedModel: (CoreMLModelID, MLModel)?

    private func cached(for id: CoreMLModelID) -> MLModel? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedModel?.0 == id ? cachedModel?.1 : nil
    }

    private func remember(_ model: MLModel, for id: CoreMLModelID) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        // Bound retained resources to one model, even after switching models.
        cachedModel = (id, model)
    }

    private func sourceModelURL(resourceName: String) -> URL? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") { return url }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") { return url }
        return nil
    }

    func prepareModel(spec: CoreMLModelSpec, progressHandler: ((Double) -> Void)? = nil) async throws -> MLModel {
        if let model = cached(for: spec.id) {
            progressHandler?(1.0)
            return model
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        config.allowLowPrecisionAccumulationOnGPU = true

        guard let modelURL = CoreMLModelRegistry.bundledURL(for: spec) else {
            throw ModelError.modelNotFound
        }
        let sourceURL = sourceModelURL(resourceName: spec.resourceName)

        progressHandler?(0.5)

        do {
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            remember(model, for: spec.id)
            progressHandler?(1.0)
            return model
        } catch {
            print("DEBUG: Failed to load model with .all compute units. Retry compiling...")

            if let src = sourceURL ?? (modelURL.pathExtension != "mlmodelc" ? modelURL : nil) {
                let compiledURL = try await MLModel.compileModel(at: src)
                let compiledModel = try MLModel(contentsOf: compiledURL, configuration: config)
                remember(compiledModel, for: spec.id)
                progressHandler?(1.0)
                return compiledModel
            }

            config.computeUnits = .cpuOnly
            config.allowLowPrecisionAccumulationOnGPU = false
            if let model = try? MLModel(contentsOf: modelURL, configuration: config) {
                remember(model, for: spec.id)
                progressHandler?(1.0)
                return model
            }
            throw ModelError.invalidModel
        }
    }
}

// MARK: - CoreML Engine

nonisolated class CoreMLEngine: EngineProtocol {
    static let shared = CoreMLEngine()

    private let logLock = NSLock()
    private var logHandler: ((String) -> Void)?
    private let control = ProcessingControl()
    private let ioLock = NSLock()
    private var cancelIO: (() -> Void)?

    func setLogHandler(_ handler: @escaping (String) -> Void) {
        logLock.lock()
        self.logHandler = handler
        logLock.unlock()
    }

    private func log(_ message: String) {
        logLock.lock()
        let handler = logHandler
        logLock.unlock()
        handler?(message)
    }

    func cancel() {
        control.cancel()
        ioLock.lock()
        let cancel = cancelIO
        ioLock.unlock()
        cancel?()
    }

    private func setCancelIO(_ cancel: (() -> Void)?) {
        ioLock.lock()
        cancelIO = cancel
        ioLock.unlock()
    }

    private func logEffectiveKnobs(settings: UpscaleSettings, useHEVC: Bool) {
        let feather = settings.tileFeatherMarginValue > 0
        let featherNote = feather ? "\(settings.tileFeatherMarginValue)px" : "off"
        log("CoreML honors: model=\(settings.upscaling.coremlModelId.rawValue), scale=\(settings.video.scaleFactor)x, codec=\(useHEVC ? "hevc" : "h264"), crf=\(Int(settings.codec.crf)), tile feather=\(featherNote).\n")
    }

    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        try control.begin()
        defer { control.finish() }
        try control.checkCancellation()
        log("CoreML Engine: Starting processing...\n")
        let codecDecision = CodecSupport.resolve(requestHEVC: settings.codec.useHEVC)

        // FIX: Force Linearize OFF for Real-ESRGAN to prevent dark/washed-out results
        if settings.upscaling.coremlModelId.rawValue.contains("RealESRGAN") {
            settings.metal.enableColorLinearize = false
            settings.metal.enableToneMap = false
            settings.metal.encodeToSRGB = false
        }

        logEffectiveKnobs(settings: settings, useHEVC: codecDecision.useHEVC)
        let modelSpec = CoreMLModelRegistry.model(for: settings.upscaling.coremlModelId)

        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: inputURL)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw Up60PEngineError.io
        }

        log("Loading AI Model (\(modelSpec.displayName))...\n")
        let mlModel = try await ModelManager.shared.prepareModel(spec: modelSpec)

        let modelDescription = mlModel.modelDescription
        guard modelDescription.inputDescriptionsByName.count == 1,
              modelDescription.outputDescriptionsByName.count == 1,
              let inputName = modelDescription.inputDescriptionsByName.keys.first,
              let outputName = modelDescription.outputDescriptionsByName.keys.first,
              let inputDescription = modelDescription.inputDescriptionsByName[inputName],
              let multiArrayConstraint = inputDescription.multiArrayConstraint,
              let outputConstraint = modelDescription.outputDescriptionsByName[outputName]?.multiArrayConstraint,
              multiArrayConstraint.dataType == .float32,
              outputConstraint.dataType == .float32,
              modelSpec.supportsTensorShapes(input: multiArrayConstraint.shape.map { $0.intValue },
                                             output: outputConstraint.shape.map { $0.intValue }) else {
            log("CoreML model has an unsupported tensor layout; expected Float32 NCHW RGB at the model's native scale.\n")
            throw ModelError.invalidModel
        }

        let modelInputShape = multiArrayConstraint.shape
        let modelInputChannels = modelInputShape[1].intValue
        let tileHeight = modelInputShape[2].intValue
        let tileWidth = modelInputShape[3].intValue

        let reader = try VideoFrameReader(asset: asset, track: videoTrack,
            checkCancellation: { try self.control.checkCancellation() })
        defer { reader.cancel() }

        let inputFilename = inputURL.deletingPathExtension().lastPathComponent
        let outputFilename = inputFilename + "_[restored].mp4"
        let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(outputFilename)
        let temporaryDirectory = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent(".myUpscaler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let renderedURL = temporaryDirectory.appendingPathComponent("rendered.mp4")
        let muxedURL = temporaryDirectory.appendingPathComponent("muxed.mp4")

        let userScaleFactor = CGFloat(settings.video.scaleFactor)
        let modelScaleFactor = CGFloat(modelSpec.nativeScale)

        let inputSize = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        if duration.isFinite, duration > 0 {
            log(String(format: "Duration: %02d:%02d:%09.6f\n", Int(duration) / 3600, (Int(duration) % 3600) / 60, duration.truncatingRemainder(dividingBy: 60)))
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        var lastProgressAt = startedAt
        let geometry = try UpscaleGeometry(inputWidth: Int(inputSize.width), inputHeight: Int(inputSize.height),
            requestedScale: settings.video.scaleFactor, nativeScale: modelSpec.nativeScale,
            tileWidth: tileWidth, tileHeight: tileHeight)
        let outputWidth = geometry.outputWidth
        let outputHeight = geometry.outputHeight
        let sourceTransform = try await videoTrack.load(.preferredTransform)

        let pixelCount = Double(outputWidth) * Double(outputHeight)
        let crfScale = 1.5 - (Double(settings.codec.crf) / 51.0)
        let targetBitrate = Int(pixelCount * 0.15 * crfScale)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codecDecision.useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate
            ]
        ]

        let writer = try VideoFrameWriter(outputURL: renderedURL, videoSettings: videoSettings,
            width: outputWidth, height: outputHeight,
            transform: geometry.outputTransform(for: sourceTransform),
            checkCancellation: { try self.control.checkCancellation() })
        setCancelIO { reader.cancel(); writer.cancel() }
        defer { setCancelIO(nil) }
        var completed = false
        defer { if !completed { writer.cancel() } }
        try control.checkCancellation()

        let tileOverlap = 16
        let effectiveTileSize = tileWidth - tileOverlap
        let tilesX = max(1, Int(ceil(Double(Int(inputSize.width) - tileOverlap) / Double(effectiveTileSize))))
        let tilesY = max(1, Int(ceil(Double(Int(inputSize.height) - tileOverlap) / Double(effectiveTileSize))))

        let predictionOptions = MLPredictionOptions()



        let weightBuffer = try createWeightBuffer(width: Int(outputWidth), height: Int(outputHeight))
        defer { weightBuffer.deallocate() }
        var frameCount = 0
        var previousFrameBuffer: CVPixelBuffer? = nil

        while let sampleBuffer = try await reader.next() {
            try control.checkCancellation()
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let outputBuffer = try writer.makePixelBuffer()

            weightBuffer.update(repeating: 0, count: Int(outputWidth) * Int(outputHeight))

            var tilesFailed = 0

            for tileY in 0..<tilesY {
                for tileX in 0..<tilesX {
                    try control.checkCancellation()

                    let x = min(tileX * effectiveTileSize, max(0, Int(inputSize.width) - tileWidth))
                    let y = min(tileY * effectiveTileSize, max(0, Int(inputSize.height) - tileHeight))
                    let w = min(tileWidth, Int(inputSize.width) - x)
                    let h = min(tileHeight, Int(inputSize.height) - y)

                    let tileBuffer = try extractTile(from: pixelBuffer, x: x, y: y, width: w, height: h, targetWidth: tileWidth, targetHeight: tileHeight)

                    preprocessTileBuffer(tileBuffer, settings: settings)

                    let inputTensor = try pixelBufferToTensor(pixelBuffer: tileBuffer, inputName: inputName, expectedChannels: modelInputChannels)

                    let inputProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputTensor])

                    let prediction = try await mlModel.prediction(from: inputProvider, options: predictionOptions)
                    if let outputFeature = prediction.featureValue(for: outputName),
                       let outputTensor = outputFeature.multiArrayValue {

                        // High Quality Resampling Logic
                        let nativeTileW = geometry.nativeTileWidth
                        let nativeTileH = geometry.nativeTileHeight

                        if let nativeBuffer = try? tensorToPixelBuffer(tensor: outputTensor, width: nativeTileW, height: nativeTileH) {

                            let region = geometry.outputRegion(x: x, y: y, width: w, height: h)
                            let (outX, outY, outW, outH) = (region.x, region.y, region.width, region.height)
                            guard outW > 0, outH > 0 else { continue }

                            var finalTileBuffer = nativeBuffer
                            if outW != w * Int(modelScaleFactor) || outH != h * Int(modelScaleFactor) {
                                finalTileBuffer = try resizePixelBuffer(nativeBuffer, width: outW, height: outH,
                                    sourceWidth: w * Int(modelScaleFactor), sourceHeight: h * Int(modelScaleFactor))
                            }

                            let blendMargin = max(1, settings.tileFeatherMarginValue > 0 ? settings.tileFeatherMarginValue : Int(Double(tileOverlap) * Double(userScaleFactor)))

                            try blendTileIntoCanvas(
                                source: finalTileBuffer,
                                target: outputBuffer,
                                weightMap: weightBuffer,
                                destX: outX, destY: outY,
                                width: outW, height: outH,
                                margin: blendMargin,
                                useCosine: settings.metal.useCosineFeather,
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

            guard tilesFailed == 0 else { throw ModelError.invalidModel }
            try await writer.append(outputBuffer, at: pts)
            previousFrameBuffer = outputBuffer
            frameCount += 1
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProgressAt >= 0.2 {
                let elapsed = now - startedAt
                let processedTime = max(0, pts.seconds)
                let fps = Double(frameCount) / elapsed
                let speed = processedTime / elapsed
                log(String(format: "frame=%d fps=%.2f time=%.6f speed=%.4fx\n", frameCount, fps, processedTime, speed))
                lastProgressAt = now
            }
        }

        try control.checkCancellation()
        log("stage=finalizing\n")
        try await writer.finish()
        try control.checkCancellation()
        log("Preserving source audio...\n")
        try await VideoAudioMuxer.preserveAudio(renderedVideoURL: renderedURL,
            originalURL: inputURL, outputURL: muxedURL,
            checkCancellation: { try self.control.checkCancellation() })
        try control.checkCancellation()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: muxedURL)
        } else {
            try FileManager.default.moveItem(at: muxedURL, to: outputURL)
        }
        completed = true
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
        guard expectedChannels == 3 else { throw ModelError.invalidModel }
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

    func tensorToPixelBuffer(tensor: MLMultiArray, width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try createPixelBuffer(width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard tensor.dataType == .float32,
              tensor.shape.map({ $0.intValue }) == [1, 3, height, width] else {
            throw ModelError.invalidModel
        }
        let strides = tensor.strides.map { $0.intValue }
        let tensorPtr = UnsafePointer<Float>(OpaquePointer(tensor.dataPointer))

        guard let baseAddr = CVPixelBufferGetBaseAddress(buffer) else { throw Up60PEngineError.internalError }
        let dstData = baseAddr.assumingMemoryBound(to: UInt8.self)

        // Fast Plane Merging (RGB Planar -> BGRA)
        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = y * strides[2] + x * strides[3]
                let dstIdx = y * bytesPerRow + x * 4

                let r = tensorPtr[srcIdx]
                let g = tensorPtr[strides[1] + srcIdx]
                let b = tensorPtr[strides[1] * 2 + srcIdx]
                guard r.isFinite, g.isFinite, b.isFinite else { throw ModelError.invalidModel }

                dstData[dstIdx + 0] = UInt8(max(0, min(255, b * 255.0))) // B
                dstData[dstIdx + 1] = UInt8(max(0, min(255, g * 255.0))) // G
                dstData[dstIdx + 2] = UInt8(max(0, min(255, r * 255.0))) // R
                dstData[dstIdx + 3] = 255 // A
            }
        }
        return buffer
    }

    func resizePixelBuffer(_ source: CVPixelBuffer, width: Int, height: Int, sourceWidth: Int, sourceHeight: Int) throws -> CVPixelBuffer {
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
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )

        var destVImage = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(dest)
        )

        guard vImageScale_ARGB8888(&srcVImage, &destVImage, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else {
            throw Up60PEngineError.internalError
        }
        return dest
    }

    func blendTileIntoCanvas(
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

        // Horizontal feather weights are identical for every row of this tile.
        let horizontalWeights: [Float] = (0..<width).map { c in
            if !isLeft && c < margin {
                let t = Float(c) / Float(margin)
                return useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
            } else if !isRight && c >= width - margin {
                let t = Float(width - c) / Float(margin)
                return useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
            }
            return 1.0
        }

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

                let weight = horizontalWeights[c] * wY
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
