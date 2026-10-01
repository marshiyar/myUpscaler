import Foundation
import AVFoundation
import CoreML
import VideoToolbox
import CoreVideo
import CoreImage
import Accelerate

/// Each run owns its I/O on this actor; inference executes on ModelManager's actor.
actor CoreMLProcessingJob {
    private let control: ProcessingControl
    private let logger: @Sendable (String) -> Void
    private var activeReader: VideoFrameReader?
    private var activeWriter: VideoFrameWriter?

    init(control: ProcessingControl = ProcessingControl(), logger: @escaping @Sendable (String) -> Void = { _ in }) {
        self.control = control
        self.logger = logger
    }
    private func log(_ message: String) { logger(message) }
    func cancelIO() { activeReader?.cancel(); activeWriter?.cancel() }

    private func logEffectiveKnobs(settings: SettingsConfiguration, useHEVC: Bool) {
        let feather = settings.tileFeatherMarginValue > 0
        let featherNote = feather ? "\(settings.tileFeatherMarginValue)px" : "off"
        log("CoreML honors: model=\(settings.upscaling.coremlModelId.rawValue), scale=\(settings.video.scaleFactor)x, codec=\(useHEVC ? "hevc" : "h264"), crf=\(Int(settings.codec.crf)), tile feather=\(featherNote).\n")
    }

    func process(inputPath: String, configuration: SettingsConfiguration,
                 outputDirectory: String) async throws {
        var settings = configuration
        defer { control.finish() }
        try control.checkCancellation()
        guard CodecSupport.isValidCRF(settings.codec.crf) else { throw Up60PEngineError.invalidOptions }
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
        let layout = try await ModelManager.shared.prepareModel(spec: modelSpec)
        try control.checkCancellation()
        guard layout.float32Input, layout.float32Output,
              modelSpec.supportsTensorShapes(input: layout.inputShape, output: layout.outputShape) else {
            log("CoreML model has an unsupported tensor layout; expected Float32 NCHW RGB at the model's native scale.\n")
            throw ModelError.invalidModel
        }
        let inputName = layout.inputName
        let outputName = layout.outputName
        let modelInputChannels = layout.inputShape[1]
        let tileHeight = layout.inputShape[2]
        let tileWidth = layout.inputShape[3]

        let reader = try VideoFrameReader(asset: asset, track: videoTrack,
            checkCancellation: { [control] in try control.checkCancellation() })
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
        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let minimumFrameDuration = try await videoTrack.load(.minFrameDuration)
        guard let sourceFrameRate = CodecSupport.encodingFrameRate(nominal: nominalFrameRate,
                  minimumDurationSeconds: minimumFrameDuration.seconds),
              let targetBitrate = CodecSupport.coreMLBitrate(pixelCount: pixelCount, crf: settings.codec.crf,
                  framesPerSecond: sourceFrameRate) else {
            throw Up60PEngineError.invalidOptions
        }
        log("CoreML encode target: \(targetBitrate) bits/s, source frame rate \(sourceFrameRate) fps, \(outputWidth)x\(outputHeight).\n")
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codecDecision.useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate
            ]
        ]

        for format in try await videoTrack.load(.formatDescriptions) {
            guard let rawExtensions = CMFormatDescriptionGetExtensions(format) else { continue }
            let extensions = rawExtensions as NSDictionary
            if let colors = CodecSupport.coreMLSDRColorProperties(
                primaries: extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String,
                transfer: extensions[kCMFormatDescriptionExtension_TransferFunction] as? String,
                matrix: extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String) {
                videoSettings[AVVideoColorPropertiesKey] = colors
                log("CoreML output color: BT.709 SDR.\n")
                break
            }
        }

        let writer = try VideoFrameWriter(outputURL: renderedURL, videoSettings: videoSettings,
            width: outputWidth, height: outputHeight,
            transform: geometry.outputTransform(for: sourceTransform),
            checkCancellation: { [control] in try control.checkCancellation() })
        activeReader = reader
        activeWriter = writer
        defer { activeReader = nil; activeWriter = nil }
        var completed = false
        defer { if !completed { writer.cancel() } }
        try control.checkCancellation()

        let tileOverlap = 16
        let effectiveTileSize = tileWidth - tileOverlap
        let tilesX = max(1, Int(ceil(Double(Int(inputSize.width) - tileOverlap) / Double(effectiveTileSize))))
        let tilesY = max(1, Int(ceil(Double(Int(inputSize.height) - tileOverlap) / Double(effectiveTileSize))))

        let weightBuffer = try createWeightBuffer(width: Int(outputWidth), height: Int(outputHeight))
        defer { weightBuffer.deallocate() }
        var frameCount = 0
        var previousFrame: ReadOnlyVideoFrame? = nil

        while let inputFrame = try await reader.next() {
            try control.checkCancellation()
            let pts = inputFrame.presentationTimeStamp
            let outputFrame = try writer.makeFrame()

            weightBuffer.update(repeating: 0, count: Int(outputWidth) * Int(outputHeight))

            for tileY in 0..<tilesY {
                for tileX in 0..<tilesX {
                    try control.checkCancellation()

                    let x = min(tileX * effectiveTileSize, max(0, Int(inputSize.width) - tileWidth))
                    let y = min(tileY * effectiveTileSize, max(0, Int(inputSize.height) - tileHeight))
                    let w = min(tileWidth, Int(inputSize.width) - x)
                    let h = min(tileHeight, Int(inputSize.height) - y)

                    let tileBuffer = try extractFromFrame(inputFrame, x: x, y: y, width: w, height: h,
                        targetWidth: tileWidth, targetHeight: tileHeight)
                    preprocessTileBuffer(tileBuffer, settings: settings)

                    let inputTensor = try pixelBufferToTensor(pixelBuffer: tileBuffer, inputName: inputName, expectedChannels: modelInputChannels)

                    let nativeBuffer = try await ModelManager.shared.prediction(input: inputTensor,
                        specID: modelSpec.id, inputName: inputName, outputName: outputName,
                        width: geometry.nativeTileWidth, height: geometry.nativeTileHeight)
                    try control.checkCancellation()
                    do {
                            let region = geometry.outputRegion(x: x, y: y, width: w, height: h)
                            let (outX, outY, outW, outH) = (region.x, region.y, region.width, region.height)
                            guard outW > 0, outH > 0 else { continue }

                            var finalTileBuffer = nativeBuffer
                            if outW != w * Int(modelScaleFactor) || outH != h * Int(modelScaleFactor) {
                                finalTileBuffer = try resizePixelBuffer(nativeBuffer, width: outW, height: outH,
                                    sourceWidth: w * Int(modelScaleFactor), sourceHeight: h * Int(modelScaleFactor))
                            }

                            let blendMargin = max(1, settings.tileFeatherMarginValue > 0 ? settings.tileFeatherMarginValue : Int(Double(tileOverlap) * Double(userScaleFactor)))

                            try blendFrame(outputFrame, source: finalTileBuffer, weightMap: weightBuffer,
                                destX: outX, destY: outY, width: outW, height: outH, margin: blendMargin,
                                useCosine: settings.metal.useCosineFeather,
                                isLeft: tileX == 0, isRight: tileX == tilesX - 1,
                                isTop: tileY == 0, isBottom: tileY == tilesY - 1)

                    }
                }
            }

            try postprocessOwnedFrame(outputFrame, previous: previousFrame, settings: settings)
            let completedFrame = try outputFrame.freeze()
            try await writer.append(completedFrame, at: pts)
            previousFrame = completedFrame
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
            checkCancellation: { [control] in try control.checkCancellation() })
        try control.checkCancellation()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: muxedURL)
        } else {
            try FileManager.default.moveItem(at: muxedURL, to: outputURL)
        }
        completed = true
        log("Done. Output saved to: \(outputURL.path)\n")
    }

    // Synchronous helpers keep borrowed buffers local: no suspension or escape.
    nonisolated private func extractFromFrame(_ frame: VideoInputFrame, x: Int, y: Int, width: Int, height: Int,
                                               targetWidth: Int, targetHeight: Int) throws -> CVPixelBuffer {
        var extracted: CVPixelBuffer?
        try frame.withPixelBuffer { buffer in
            extracted = try extractTile(from: buffer, x: x, y: y, width: width, height: height,
                targetWidth: targetWidth, targetHeight: targetHeight)
        }
        guard let extracted else { throw Up60PEngineError.io }
        return extracted
    }
    nonisolated private func blendFrame(_ frame: OwnedVideoFrame, source: CVPixelBuffer,
        weightMap: UnsafeMutablePointer<Float>, destX: Int, destY: Int, width: Int, height: Int,
        margin: Int, useCosine: Bool, isLeft: Bool, isRight: Bool, isTop: Bool, isBottom: Bool) throws {
        try frame.withPixelBuffer { target in
            try blendTileIntoCanvas(source: source, target: target, weightMap: weightMap,
                destX: destX, destY: destY, width: width, height: height, margin: margin,
                useCosine: useCosine, isLeft: isLeft, isRight: isRight, isTop: isTop, isBottom: isBottom)
        }
    }
    nonisolated private func postprocessOwnedFrame(_ frame: OwnedVideoFrame, previous: ReadOnlyVideoFrame?,
                                                  settings: SettingsConfiguration) throws {
        try frame.withPixelBuffer { output in
            if let previous {
                previous.withPixelBuffer { prior in postprocessFrameBuffer(output, previous: prior, settings: settings) }
            } else { postprocessFrameBuffer(output, previous: nil, settings: settings) }
        }
    }

    // MARK: - Helper Methods
    nonisolated private func createPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        try Self.allocatePixelBuffer(width: width, height: height)
    }

    nonisolated private static func allocatePixelBuffer(width: Int, height: Int) throws -> sending CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        _ = try CoreMLBufferAccess.pixelCount(width: width, height: height)
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, options as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { throw Up60PEngineError.internalError }
        return buffer
    }

    nonisolated private func createWeightBuffer(width: Int, height: Int) throws -> UnsafeMutablePointer<Float> {
        let count = try CoreMLBufferAccess.pixelCount(width: width, height: height)
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        return buffer
    }

    nonisolated private func extractTile(from sourceBuffer: CVPixelBuffer, x: Int, y: Int, width: Int, height: Int, targetWidth: Int, targetHeight: Int) throws -> CVPixelBuffer {
        try CoreMLBufferAccess.validateRegion(x: x, y: y, width: width, height: height, buffer: sourceBuffer)
        guard width <= targetWidth, height <= targetHeight else { throw Up60PEngineError.invalidOptions }
        let tileBuffer = try createPixelBuffer(width: targetWidth, height: targetHeight)
        let srcBase = try CoreMLBufferAccess.lock(sourceBuffer, flags: .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly) }
        let dstBase = try CoreMLBufferAccess.lock(tileBuffer, flags: [])
        defer { CVPixelBufferUnlockBaseAddress(tileBuffer, []) }

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

    nonisolated private func pixelBufferToTensor(pixelBuffer: CVPixelBuffer, inputName: String, expectedChannels: Int) throws -> sending MLMultiArray {
        guard expectedChannels == 3 else { throw ModelError.invalidModel }
        let baseAddr = try CoreMLBufferAccess.lock(pixelBuffer, flags: .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelCount = width * height

        let channels = 3
        let shape = [1, NSNumber(value: channels), NSNumber(value: height), NSNumber(value: width)]
        let tensor = try MLMultiArray(shape: shape, dataType: .float32)

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

    nonisolated func tensorToPixelBuffer(tensor: MLMultiArray, width: Int, height: Int) throws -> CVPixelBuffer {
        try Self.makePixelBuffer(tensor: tensor, width: width, height: height)
    }

    nonisolated static func makePixelBuffer(tensor: MLMultiArray, width: Int, height: Int) throws -> sending CVPixelBuffer {
        let buffer = try allocatePixelBuffer(width: width, height: height)
        let baseAddr = try CoreMLBufferAccess.lock(buffer, flags: [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard tensor.dataType == .float32,
              tensor.shape.map({ $0.intValue }) == [1, 3, height, width] else {
            throw ModelError.invalidModel
        }
        let strides = tensor.strides.map { $0.intValue }
        let tensorPtr = UnsafePointer<Float>(OpaquePointer(tensor.dataPointer))

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

    nonisolated func resizePixelBuffer(_ source: CVPixelBuffer, width: Int, height: Int, sourceWidth: Int, sourceHeight: Int) throws -> CVPixelBuffer {
        try CoreMLBufferAccess.validateRegion(x: 0, y: 0, width: sourceWidth, height: sourceHeight, buffer: source)
        let dest = try createPixelBuffer(width: width, height: height)
        let srcBase = try CoreMLBufferAccess.lock(source, flags: .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        let dstBase = try CoreMLBufferAccess.lock(dest, flags: [])
        defer { CVPixelBufferUnlockBaseAddress(dest, []) }

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

    nonisolated func blendTileIntoCanvas(
        source: CVPixelBuffer,
        target: CVPixelBuffer,
        weightMap: UnsafeMutablePointer<Float>,
        destX: Int, destY: Int,
        width: Int, height: Int,
        margin: Int,
        useCosine: Bool,
        isLeft: Bool, isRight: Bool, isTop: Bool, isBottom: Bool
    ) throws {
        try CoreMLBufferAccess.validateRegion(x: 0, y: 0, width: width, height: height, buffer: source)
        try CoreMLBufferAccess.validateBGRA(target)
        guard destX >= 0, destY >= 0, destX < CVPixelBufferGetWidth(target),
              destY < CVPixelBufferGetHeight(target), margin >= 0 else { throw Up60PEngineError.invalidOptions }
        let srcBase = try CoreMLBufferAccess.lock(source, flags: .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        let dstBase = try CoreMLBufferAccess.lock(target, flags: [])
        defer { CVPixelBufferUnlockBaseAddress(target, []) }

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
