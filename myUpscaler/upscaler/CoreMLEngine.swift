//import Foundation
//import AVFoundation
//import CoreML
//import VideoToolbox
//import CoreVideo
//import CoreImage
//import Accelerate  
//
//
//
//enum CoreMLModelID: String, CaseIterable, Codable, Hashable {
//    case realESRGANx2 = "RealESRGAN_x2"
//    case realESRGANx4 = "RealESRGAN_x4"
//    case realESRGANx8 = "RealESRGAN_x8"
//}
//
//struct CoreMLModelSpec: Identifiable, Hashable {
//    let id: CoreMLModelID
//    let displayName: String
//    let resourceName: String
//    let nativeScale: Double
//}
//
//enum CoreMLModelRegistry {
//    static let models: [CoreMLModelSpec] = [
//        CoreMLModelSpec(id: .realESRGANx2, displayName: "Real-ESRGAN x2", resourceName: "RealESRGAN_x2", nativeScale: 2.0),
//        CoreMLModelSpec(id: .realESRGANx4, displayName: "Real-ESRGAN x4", resourceName: "RealESRGAN_x4", nativeScale: 4.0),
//        CoreMLModelSpec(id: .realESRGANx8, displayName: "Real-ESRGAN x8", resourceName: "RealESRGAN_x8", nativeScale: 8.0)
//    ]
//    
//    static var defaultModel: CoreMLModelSpec { models.first(where: { $0.id == .realESRGANx4 }) ?? models[0] }
//    
//    static func model(for id: CoreMLModelID) -> CoreMLModelSpec {
//        models.first(where: { $0.id == id }) ?? defaultModel
//    }
//}
//
//// MARK: -
//
//private struct DriftGuardDecision {
//    let blendWeight: Float  
//    let note: String?
//    
//    static var passThrough: DriftGuardDecision {
//        DriftGuardDecision(blendWeight: 1.0, note: nil)
//    }
//}
//
//private final class DriftGuard {
//    func evaluate(
//        tensor: MLMultiArray,
//        baseline: CVPixelBuffer?,
//        targetWidth: Int,
//        targetHeight: Int,
//        scaleRatio: Double
//    ) -> DriftGuardDecision {
//        guard let baseline = baseline else { return .passThrough }
//        
//        CVPixelBufferLockBaseAddress(baseline, .readOnly)
//        defer { CVPixelBufferUnlockBaseAddress(baseline, .readOnly) }
//        
//        guard let basePtr = CVPixelBufferGetBaseAddress(baseline) else {
//            return .passThrough
//        }
//        
//        let baseBytes = basePtr.assumingMemoryBound(to: UInt8.self)
//        let baseBytesPerRow = CVPixelBufferGetBytesPerRow(baseline)
//        
//        let tensorWidth = tensor.shape[3].intValue
//        let tensorHeight = tensor.shape[2].intValue
//        let tensorPixelCount = tensorWidth * tensorHeight
//        let tensorPtr = UnsafePointer<Float>(OpaquePointer(tensor.dataPointer))
//        let rPlane = tensorPtr
//        let gPlane = tensorPtr + tensorPixelCount
//        let bPlane = tensorPtr + tensorPixelCount * 2
//        
//        var srMean: Float = 0
//        var baseMean: Float = 0
//        var srHF: Float = 0
//        var baseHF: Float = 0
//        var samples = 0
//        
//        let step = max(2, min(8, targetWidth / 64))
//        for y in stride(from: 1, to: targetHeight - 1, by: step) {
//            for x in stride(from: 1, to: targetWidth - 1, by: step) {
//                let baseIndex = y * baseBytesPerRow + x * 4
//                let b = Float(baseBytes[baseIndex + 0])
//                let g = Float(baseBytes[baseIndex + 1])
//                let r = Float(baseBytes[baseIndex + 2])
//                let baseL = 0.299 * r + 0.587 * g + 0.114 * b
//                
//                let srcX = min(tensorWidth - 1, Int(Double(x) / scaleRatio))
//                let srcY = min(tensorHeight - 1, Int(Double(y) / scaleRatio))
//                let tIndex = srcY * tensorWidth + srcX
//                let srR = rPlane[tIndex] * 255.0
//                let srG = gPlane[tIndex] * 255.0
//                let srB = bPlane[tIndex] * 255.0
//                let srL = 0.299 * srR + 0.587 * srG + 0.114 * srB
//                
//                srMean += srL
//                baseMean += baseL
//                
//                
//                let nextX = min(targetWidth - 1, x + 1)
//                let nextY = min(targetHeight - 1, y + 1)
//                let baseIdxX = y * baseBytesPerRow + nextX * 4
//                let baseIdxY = nextY * baseBytesPerRow + x * 4
//                let baseLX = 0.299 * Float(baseBytes[baseIdxX + 2]) + 0.587 * Float(baseBytes[baseIdxX + 1]) + 0.114 * Float(baseBytes[baseIdxX + 0])
//                let baseLY = 0.299 * Float(baseBytes[baseIdxY + 2]) + 0.587 * Float(baseBytes[baseIdxY + 1]) + 0.114 * Float(baseBytes[baseIdxY + 0])
//                
//                let srIdxX = min(tensorWidth - 1, Int(Double(nextX) / scaleRatio))
//                let srIdxY = min(tensorHeight - 1, Int(Double(nextY) / scaleRatio))
//                let tIndexX = srIdxX + srcY * tensorWidth
//                let tIndexY = srcX + srIdxY * tensorWidth
//                let srLX = 0.299 * rPlane[tIndexX] * 255.0 + 0.587 * gPlane[tIndexX] * 255.0 + 0.114 * bPlane[tIndexX] * 255.0
//                let srLY = 0.299 * rPlane[tIndexY] * 255.0 + 0.587 * gPlane[tIndexY] * 255.0 + 0.114 * bPlane[tIndexY] * 255.0
//                
//                srHF += abs(srLX - srL) + abs(srLY - srL)
//                baseHF += abs(baseLX - baseL) + abs(baseLY - baseL)
//                samples += 1
//            }
//        }
//        
//        guard samples > 0 else { return .passThrough }
//        
//        srMean /= Float(samples)
//        baseMean /= Float(samples)
//        let colorDrift = abs(srMean - baseMean)
//        let baseHFClamped = max(baseHF, 1.0)
//        let hfRatio = srHF / baseHFClamped
//        
//        var weight: Float = 1.0
//        if colorDrift > 6.0 { weight -= 0.15 }
//        if hfRatio > 1.20 {
//            let reduction = min(0.35, (hfRatio - 1.20) * 0.4)
//            weight -= Float(reduction)
//        }
//        weight = min(1.0, max(0.55, weight))
//        
//        let note: String?
//        if weight < 0.98 {
//            note = String(format: "DriftGuard: blended to %.2f to limit drift (ΔL=%.1f, HFx=%.2f)", weight, colorDrift, hfRatio)
//        } else {
//            note = nil
//        }
//        
//        return DriftGuardDecision(blendWeight: weight, note: note)
//    }
//}
//
//// MARK: -
//
//enum ModelError: Error {
//    case compilationFailed(Error)
//    case modelNotFound
//    case invalidModel
//    case fileSystemError(Error)
//}
//
//class ModelManager {
//    static let shared = ModelManager()
//    private init() {}
//    
//    
//    
//    private func bundledModelURL(resourceName: String) -> URL? {
//        
//        
//        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") {
//            print("DEBUG: Found compiled model at: \(url.path)")
//            return url
//        }
//        
//        
//        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") {
//            print("DEBUG: Found source model at: \(url.path)")
//            return url
//        }
//        
//        
//        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") {
//            print("DEBUG: Found legacy model at: \(url.path)")
//            return url
//        }
//        
//        print("DEBUG: Model not found in bundle!")
//        return nil
//    }
//    
//    
//    private func sourceModelURL(resourceName: String) -> URL? {
//        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlpackage") {
//            print("DEBUG: Found source model (mlpackage) at: \(url.path)")
//            return url
//        }
//        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mlmodel") {
//            print("DEBUG: Found source model (mlmodel) at: \(url.path)")
//            return url
//        }
//        return nil
//    }
//    
//    
//    // MARK: -
//    
//    func prepareModel(spec: CoreMLModelSpec, progressHandler: ((Double) -> Void)? = nil) async throws -> MLModel {
//        
//        var config = MLModelConfiguration()
//        
//        
//        
//        
//        config.computeUnits = .all
//        
//        
//        config.allowLowPrecisionAccumulationOnGPU = true
//        
//        print("DEBUG: CoreML configured for Apple Silicon (Neural Engine + GPU + CPU)")
//        print("DEBUG: Bundle path: \(Bundle.main.bundlePath)")
//        
//        guard let modelURL = bundledModelURL(resourceName: spec.resourceName) else {
//            throw ModelError.modelNotFound
//        }
//        let sourceURL = sourceModelURL(resourceName: spec.resourceName)
//        
//        print("DEBUG: Model found at: \(modelURL.path)")
//        progressHandler?(0.5)
//        
//        
//        do {
//            let model = try MLModel(contentsOf: modelURL, configuration: config)
//            progressHandler?(1.0)
//            return model
//        } catch {
//            print("DEBUG: Failed to load model with .all compute units. Error: \(error.localizedDescription)")
//            
//            
//            if modelURL.pathExtension != "mlmodelc" {
//                do {
//                    let compiledURL = try await MLModel.compileModel(at: modelURL)
//                    print("DEBUG: Compiled model to temporary path: \(compiledURL.path)")
//                    let compiledModel = try MLModel(contentsOf: compiledURL, configuration: config)
//                    progressHandler?(1.0)
//                    return compiledModel
//                } catch {
//                    print("DEBUG: Compile + load retry failed: \(error.localizedDescription)")
//                }
//            }
//            
//            
//            if let src = sourceURL {
//                do {
//                    let compiledURL = try await MLModel.compileModel(at: src)
//                    print("DEBUG: Compiled source model to temporary path: \(compiledURL.path)")
//                    let compiledModel = try MLModel(contentsOf: compiledURL, configuration: config)
//                    progressHandler?(1.0)
//                    return compiledModel
//                } catch {
//                    print("DEBUG: Compile from source retry failed: \(error.localizedDescription)")
//                }
//            }
//            
//            
//            
//            config = MLModelConfiguration()
//            config.computeUnits = .cpuOnly
//            config.allowLowPrecisionAccumulationOnGPU = false
//            
//            
//            if let model = try? MLModel(contentsOf: modelURL, configuration: config) {
//                print("DEBUG: Model loaded successfully with CPU fallback.")
//                progressHandler?(1.0)
//                return model
//            }
//            
//            
//            if let src = sourceURL ?? (modelURL.pathExtension != "mlmodelc" ? modelURL : nil) {
//                let compiledURL = try await MLModel.compileModel(at: src)
//                print("DEBUG: Compiled model to temporary path (CPU fallback): \(compiledURL.path)")
//                let model = try MLModel(contentsOf: compiledURL, configuration: config)
//                progressHandler?(1.0)
//                return model
//            }
//            
//            throw ModelError.invalidModel
//        }
//    }
//}
//
//// MARK: - 
//
//class CoreMLEngine: EngineProtocol {
//    static let shared = CoreMLEngine()
//    
//    private var logHandler: ((String) -> Void)?
//    private var isCancelled = false
//    private let driftGuard = DriftGuard()
//    var regionContext: RegionMaskContext?
//    // DISABLED: Drift Guard kept off globally
//    var driftGuardEnabled: Bool = false
//    
//    func setLogHandler(_ handler: @escaping (String) -> Void) {
//        self.logHandler = handler
//    }
//    
//    private func log(_ message: String) {
//        logHandler?(message)
//    }
//    
//    func cancel() {
//        isCancelled = true
//    }
//    
//    private func logEffectiveKnobs(settings: UpscaleSettings, useHEVC: Bool) {
//        let shaderStages = [
//            settings.enableColorLinearize ? "linearize" : nil,
//            settings.enableToneMap ? "tone-map" : nil,
//            (!settings.noDenoise && settings.denoiseStrength != "0") ? "denoise" : nil,
//            (!settings.noDeband && settings.debandStrength != "0") ? "deband" : nil,
//            (!settings.noSharpen && settings.sharpenStrength != "0") ? (settings.sharpenMethod == "unsharp" ? "USM" : "CAS") : nil,
//            settings.useLaplacianSharpen ? "laplacian" : nil,
//            settings.useDehalo ? "dehalo" : nil,
//            settings.useMoireSuppress ? "moire" : nil,
//            settings.useTemporalSmoothing ? "temporal" : nil
//        ].compactMap { $0 }.joined(separator: ", ")
//        
//        let feather = settings.tileFeatherMarginValue > 0
//        let featherNote = feather ? "\(settings.tileFeatherMarginValue)px \(settings.useCosineFeather ? "cosine" : "linear")" : "off"
//        
//        log("CoreML honors: model=\(settings.coremlModelId.rawValue), scale=\(settings.scaleFactor)x, codec=\(useHEVC ? "hevc" : "h264"), crf=\(Int(settings.crf)), tile feather=\(featherNote).\n")
//        
//        let shaderNote = shaderStages.isEmpty ? "none (default pass-through)" : shaderStages
//        log("CoreML shader stages active: \(shaderNote).\n")
//        
//        log("CoreML ignores FFmpeg-only toggles (deblock/dering/interpolate/decimate/eq/grain/dnn/backend presets), so changing those sliders will not affect CoreML output.\n")
//    }
//    
//    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
//        isCancelled = false
//        log("CoreML Engine: Starting processing...\n")
//        let codecDecision = CodecSupport.resolve(requestHEVC: settings.useHEVC)
//        if let message = codecDecision.message {
//            log(message)
//        }
//        let regionContext = self.regionContext
//        self.regionContext = nil
//        // DISABLED: Drift Guard is force-disabled regardless of settings
//        let driftGuardEnabled = false
//        log("CoreML Notice: Drift Guard disabled and region masks cleared; CoreML will run without stabilization/region weighting.\n")
//        
//        if settings.coremlModelId.rawValue.contains("RealESRGAN") {
//            settings.enableColorLinearize = false
//            settings.enableToneMap = false
//            settings.encodeToSRGB = false
//        }
//        // --------------------------------
//        
//        logEffectiveKnobs(settings: settings, useHEVC: codecDecision.useHEVC)
//        let modelSpec = CoreMLModelRegistry.model(for: settings.coremlModelId)
//        
//        
//        let inputURL = URL(fileURLWithPath: inputPath)
//        let asset = AVURLAsset(url: inputURL)
//        
//        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
//            log("Error: No video track found.\n")
//            throw Up60PEngineError.io
//        }
//        
//        
//        log("Checking AI Model (\(modelSpec.displayName))...\n")
//        let mlModel: MLModel
//        do {
//            mlModel = try await ModelManager.shared.prepareModel(spec: modelSpec) { [weak self] progress in
//                self?.log("Model Setup Progress: \(Int(progress * 100))%\n")
//            }
//        } catch ModelError.modelNotFound {
//            log("Error: AI model not found in app bundle.\n")
//            log("Please ensure \(modelSpec.resourceName).mlpackage is included in the Xcode target.\n")
//            log("Location: myUpscaler/upscaler/models/\(modelSpec.resourceName).mlpackage\n")
//            log("Debug: Bundle resource path: \(Bundle.main.resourcePath ?? "nil")\n")
//            log("Debug: Checking bundle contents...\n")
//            if let resourcePath = Bundle.main.resourcePath {
//                let modelsPath = "\(resourcePath)/upscaler/models"
//                if FileManager.default.fileExists(atPath: modelsPath) {
//                    log("Debug: Models directory exists at: \(modelsPath)\n")
//                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsPath) {
//                        log("Debug: Contents: \(contents.joined(separator: ", "))\n")
//                    }
//                } else {
//                    log("Debug: Models directory NOT found at: \(modelsPath)\n")
//                }
//            }
//            throw Up60PEngineError.invalidOptions
//        } catch {
//            log("Error loading model: \(error.localizedDescription)\n")
//            throw Up60PEngineError.internalError
//        }
//        
//        
//        let modelDescription = mlModel.modelDescription
//        log("Model inputs: \(modelDescription.inputDescriptionsByName.keys.joined(separator: ", "))\n")
//        log("Model outputs: \(modelDescription.outputDescriptionsByName.keys.joined(separator: ", "))\n")
//        
//        
//        guard let inputName = modelDescription.inputDescriptionsByName.keys.first,
//              let outputName = modelDescription.outputDescriptionsByName.keys.first else {
//            log("Error: Could not determine model input/output names.\n")
//            throw Up60PEngineError.internalError
//        }
//        
//        
//        guard let inputDescription = modelDescription.inputDescriptionsByName[inputName],
//              let multiArrayConstraint = inputDescription.multiArrayConstraint else {
//            log("Error: Could not get model input constraints.\n")
//            throw Up60PEngineError.internalError
//        }
//        
//        let modelInputShape = multiArrayConstraint.shape
//        guard modelInputShape.count >= 4 else {
//            log("Error: Unexpected model input shape.\n")
//            throw Up60PEngineError.internalError
//        }
//        
//        let modelInputChannels = modelInputShape[1].intValue
//        let tileHeight = modelInputShape[2].intValue
//        let tileWidth = modelInputShape[3].intValue
//        log("Model expects input tiles of size: \(tileWidth)x\(tileHeight) with \(modelInputChannels) channels\n")
//        
//        
//        let reader = try AVAssetReader(asset: asset)
//        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
//            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
//        ])
//        reader.add(readerOutput)
//        
//        if !reader.startReading() {
//            log("Failed to start reading input: \(reader.error?.localizedDescription ?? "Unknown error")\n")
//            throw Up60PEngineError.io
//        }
//        
//        
//        
//        let inputFilename = inputURL.deletingPathExtension().lastPathComponent
//        let outputFilename = inputFilename + "_[restored].mp4"
//        let outputURL = URL(fileURLWithPath: outputDirectory).appendingPathComponent(outputFilename)
//        
//        
//        if FileManager.default.fileExists(atPath: outputURL.path) {
//            try? FileManager.default.removeItem(at: outputURL)
//        }
//        
//        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
//        
//        
//        let userScaleFactor = CGFloat(settings.scaleFactor)
//        let modelScaleFactor: CGFloat = CGFloat(modelSpec.nativeScale)
//        
//        
//        let inputSize = try await videoTrack.load(.naturalSize)
//        let outputWidth = inputSize.width * userScaleFactor
//        let outputHeight = inputSize.height * userScaleFactor
//        
//        
//        
//        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
//        log("Preserving original frame rate: \(originalFrameRate) fps (interpolation handled by FFmpeg)\n")
//        log("User scale factor: \(userScaleFactor)x (Model native: \(Int(modelScaleFactor))x)\n")
//        
//        
//        let videoCodec: AVVideoCodecType = codecDecision.useHEVC ? .hevc : .h264
//        
//        
//        
//        let crfFactor = (51.0 - settings.crf) / 51.0
//        let baseBitrate = Double(outputWidth * outputHeight) * 0.15
//        let targetBitrate = Int(baseBitrate * (0.5 + crfFactor))
//        
//        
//        var compressionProperties: [String: Any] = [
//            AVVideoAverageBitRateKey: targetBitrate
//        ]
//        
//        
//        if codecDecision.useHEVC {
//            
//            compressionProperties[AVVideoQualityKey] = crfFactor
//        }
//        
//        
//        let videoSettings: [String: Any] = [
//            AVVideoCodecKey: videoCodec,
//            AVVideoWidthKey: outputWidth,
//            AVVideoHeightKey: outputHeight,
//            AVVideoCompressionPropertiesKey: compressionProperties
//        ]
//        
//        log("Output codec: \(codecDecision.useHEVC ? "HEVC" : "H.264"), Bitrate: \(targetBitrate / 1_000_000) Mbps, CRF: \(Int(settings.crf))\n")
//        
//        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
//        writerInput.expectsMediaDataInRealTime = false
//        
//        
//        writerInput.mediaTimeScale = CMTimeScale(originalFrameRate * 1000)
//        
//        
//        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
//            assetWriterInput: writerInput,
//            sourcePixelBufferAttributes: [
//                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
//                kCVPixelBufferWidthKey as String: outputWidth,
//                kCVPixelBufferHeightKey as String: outputHeight,
//                kCVPixelBufferMetalCompatibilityKey as String: true,
//                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
//            ]
//        )
//        
//        if writer.canAdd(writerInput) {
//            writer.add(writerInput)
//        } else {
//            log("Cannot add video input to writer.\n")
//            throw Up60PEngineError.internalError
//        }
//        
//        
//        var audioReader: AVAssetReader?
//        var audioReaderOutput: AVAssetReaderTrackOutput?
//        var audioWriterInput: AVAssetWriterInput?
//        var hasAudio = false
//        
//        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
//            
//            if let formatDesc = try? await audioTrack.load(.formatDescriptions).first {
//                log("Audio track found: \(String(describing: formatDesc))\n")
//            } else {
//                log("Audio track found (no format description loaded)\n")
//            }
//            
//            
//            
//            
//            if let reader = try? AVAssetReader(asset: asset) {
//                
//                
//                
//                let audioSettings: [String: Any] = [
//                    AVFormatIDKey: kAudioFormatMPEG4AAC,
//                    AVNumberOfChannelsKey: 2,
//                    AVSampleRateKey: 48000.0,
//                    AVEncoderBitRateKey: 320000
//                ]
//                
//                
//                let decompressedSettings: [String: Any] = [
//                    AVFormatIDKey: kAudioFormatLinearPCM
//                ]
//                
//                let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: decompressedSettings)
//                output.alwaysCopiesSampleData = false
//                
//                if reader.canAdd(output) {
//                    reader.add(output)
//                    
//                    
//                    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
//                    input.expectsMediaDataInRealTime = false
//                    
//                    if writer.canAdd(input) {
//                        writer.add(input)
//                        
//                        audioReader = reader
//                        audioReaderOutput = output
//                        audioWriterInput = input
//                        hasAudio = true
//                        log("Audio track configured for AAC re-encoding (Safe Mode).\n")
//                    } else {
//                        log("Error: Writer cannot add audio input.\n")
//                    }
//                } else {
//                    log("Error: Reader cannot add audio output.\n")
//                }
//            } else {
//                log("Error: Could not create AVAssetReader for audio.\n")
//            }
//        } else {
//            log("No audio track found in input.\n")
//        }
//        
//        
//        if !writer.startWriting() {
//            log("Error starting writer: \(writer.error?.localizedDescription ?? "Unknown")\n")
//            throw Up60PEngineError.io
//        }
//        writer.startSession(atSourceTime: .zero)
//        
//        
//        
//        let audioTask = Task {
//            if !hasAudio { return }
//            guard let reader = audioReader,
//                  let output = audioReaderOutput,
//                  let input = audioWriterInput else { return }
//            
//            log("Starting audio processing...\n")
//            
//            if reader.startReading() {
//                var audioSampleCount = 0
//                
//                
//                while reader.status == .reading {
//                    if isCancelled {
//                        input.markAsFinished()
//                        reader.cancelReading()
//                        log("Audio processing cancelled.\n")
//                        break
//                    }
//                    
//                    if input.isReadyForMoreMediaData {
//                        if let sampleBuffer = output.copyNextSampleBuffer() {
//                            if input.append(sampleBuffer) {
//                                audioSampleCount += 1
//                            } else {
//                                log("Audio writer append failed: \(writer.error?.localizedDescription ?? "Unknown")\n")
//                                break
//                            }
//                        } else {
//                            
//                            log("Audio stream finished. Samples: \(audioSampleCount)\n")
//                            input.markAsFinished()
//                            break
//                        }
//                    } else {
//                        
//                        try? await Task.sleep(nanoseconds: 10_000_000)
//                    }
//                }
//                
//                if reader.status == .completed {
//                    
//                } else if reader.status == .failed {
//                    log("Audio reader failed: \(reader.error?.localizedDescription ?? "Unknown")\n")
//                    input.markAsFinished()
//                }
//            } else {
//                log("Failed to start audio reader: \(reader.error?.localizedDescription ?? "Unknown")\n")
//            }
//        }
//        
//        
//        var frameCount = 0
//        let duration = try await asset.load(.duration).seconds
//        
//        log("Processing video frames (Upscaling with Real-ESRGAN)...\n")
//        log("Input: \(Int(inputSize.width))x\(Int(inputSize.height))\n")
//        log("Output: \(Int(outputWidth))x\(Int(outputHeight))\n")
//        log("Tile size: \(tileWidth)x\(tileHeight)\n")
//        
//        
//        
//        let tileOverlap = 16
//        let effectiveTileSize = tileWidth - tileOverlap
//        
//        
//        let tilesX = max(1, Int(ceil(Double(Int(inputSize.width) - tileOverlap) / Double(effectiveTileSize))))
//        let tilesY = max(1, Int(ceil(Double(Int(inputSize.height) - tileOverlap) / Double(effectiveTileSize))))
//        log("Tiles per frame: \(tilesX)x\(tilesY) = \(tilesX * tilesY) tiles (with \(tileOverlap)px overlap)\n")
//        
//        
//        let predictionOptions = MLPredictionOptions()
//        predictionOptions.usesCPUOnly = false
//        
//        
//        var totalInferenceTime: Double = 0
//        var totalConversionTime: Double = 0
//        let startTime = Date()
//        var previousFrameBuffer: CVPixelBuffer? = nil
//        
//        
//        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
//            if isCancelled {
//                reader.cancelReading()
//                writer.cancelWriting()
//                log("Cancelled.\n")
//                return
//            }
//            
//            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
//            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
//            
//            
//            guard let outputBuffer = try? createPixelBuffer(width: Int(outputWidth), height: Int(outputHeight)) else {
//                log("Failed to create output buffer for frame \(frameCount)\n")
//                continue
//            }
//            
//            
//            var tilesFailed = 0
//            var guardedTiles = 0
//            var guardNotes: [String] = []
//            let frameStartTime = Date()
//            
//            guard let weightBuffer = try? createWeightBuffer(width: Int(outputWidth), height: Int(outputHeight)) else {
//                log("Failed to create weight buffer for frame \(frameCount)\n")
//                continue
//            }
//            
//            for tileY in 0..<tilesY {
//                for tileX in 0..<tilesX {
//                    if isCancelled { break }
//                    
//                    
//                    
//                    let x = min(tileX * effectiveTileSize, max(0, Int(inputSize.width) - tileWidth))
//                    let y = min(tileY * effectiveTileSize, max(0, Int(inputSize.height) - tileHeight))
//                    let w = min(tileWidth, Int(inputSize.width) - x)
//                    let h = min(tileHeight, Int(inputSize.height) - y)
//                    
//                    let convStart = Date()
//                    
//                    
//                    guard let tileBuffer = try? extractTile(from: pixelBuffer, x: x, y: y, width: w, height: h, targetWidth: tileWidth, targetHeight: tileHeight) else {
//                        tilesFailed += 1
//                        continue
//                    }
//                    
//                    
//                    preprocessTileBuffer(tileBuffer, settings: settings)
//                    
//                    
//                    guard let inputTensor = try? pixelBufferToTensor(pixelBuffer: tileBuffer, inputName: inputName, expectedChannels: modelInputChannels) else {
//                        tilesFailed += 1
//                        continue
//                    }
//                    
//                    totalConversionTime += Date().timeIntervalSince(convStart)
//                    
//                    
//                    let inferStart = Date()
//                    let inputFeatures: [String: Any] = [inputName: inputTensor]
//                    let inputProvider = try MLDictionaryFeatureProvider(dictionary: inputFeatures)
//                    
//                    guard let prediction = try? await mlModel.prediction(from: inputProvider, options: predictionOptions),
//                          let outputFeature = prediction.featureValue(for: outputName),
//                          let outputTensor = outputFeature.multiArrayValue else {
//                        tilesFailed += 1
//                        continue
//                    }
//                    
//                    totalInferenceTime += Date().timeIntervalSince(inferStart)
//                    //                    MARK
//                    //
//                    //                    let scaleRatio = Double(userScaleFactor) / Double(modelScaleFactor)
//                    //                    let outX = Int(Double(x) * Double(userScaleFactor))
//                    //                    let outY = Int(Double(y) * Double(userScaleFactor))
//                    //                    let outW = Int(Double(w) * Double(userScaleFactor))
//                    //                    let outH = Int(Double(h) * Double(userScaleFactor))
//                    //
//                    //
//                    //                    let configuredMargin = settings.tileFeatherMarginValue > 0 ? settings.tileFeatherMarginValue : Int(Double(tileOverlap) * Double(userScaleFactor))
//                    //                    let blendMargin = max(1, configuredMargin)
//                    //                    let isLeftEdge = tileX == 0
//                    //                    let isRightEdge = tileX == tilesX - 1
//                    //                    let isTopEdge = tileY == 0
//                    //                    let isBottomEdge = tileY == tilesY - 1
//                    //
//                    //                    do {
//                    //
//                    //                        let baseline = driftGuardEnabled ? try? upscaleTileBicubic(tileBuffer, width: outW, height: outH) : nil
//                    //                        let guardDecision: DriftGuardDecision
//                    //                        if driftGuardEnabled {
//                    //                            guardDecision = driftGuard.evaluate(
//                    //                                tensor: outputTensor,
//                    //                                baseline: baseline,
//                    //                                targetWidth: outW,
//                    //                                targetHeight: outH,
//                    //                                scaleRatio: scaleRatio
//                    //                            )
//                    //                        } else {
//                    //                            guardDecision = .passThrough
//                    //                        }
//                    //
//                    //                        var combinedWeight = guardDecision.blendWeight
//                    //                        if let ctx = regionContext {
//                    //                            let normX = (Double(x) + Double(w) * 0.5) / Double(inputSize.width)
//                    //                            let normY = (Double(y) + Double(h) * 0.5) / Double(inputSize.height)
//                    //                            let sample = ctx.sample(normX: normX, normY: normY)
//                    //                            let regionWeight = max(0.55, min(1.0,
//                    //                                1.0
//                    //                                - 0.22 * sample.noise
//                    //                                - 0.20 * sample.block
//                    //                                - 0.15 * sample.band
//                    //                                - 0.12 * sample.text
//                    //                                + 0.12 * sample.edge
//                    //                            ))
//                    //                            combinedWeight = min(combinedWeight, regionWeight)
//                    //                        }
//                    //
//                    //                        if driftGuardEnabled {
//                    //                            if combinedWeight < 0.98 { guardedTiles += 1 }
//                    //                            if let note = guardDecision.note {
//                    //                                guardNotes.append(note)
//                    //                            }
//                    //                        }
//                    //
//                    //                        try placeTileWithGuardedBlending(
//                    //                            tensor: outputTensor,
//                    //                            baseline: baseline,
//                    //                            srWeight: combinedWeight,
//                    //                            into: outputBuffer,
//                    //                            weightBuffer: weightBuffer,
//                    //                            x: outX,
//                    //                            y: outY,
//                    //                            targetWidth: outW,
//                    //                            targetHeight: outH,
//                    //                            scaleRatio: scaleRatio,
//                    //                            blendMargin: blendMargin,
//                    //                            useCosineFeather: settings.useCosineFeather,
//                    //                            isLeftEdge: isLeftEdge,
//                    //                            isRightEdge: isRightEdge,
//                    //                            isTopEdge: isTopEdge,
//                    //                            isBottomEdge: isBottomEdge
//                    //                        )
//                    //                    } catch {
//                    //                        tilesFailed += 1
//                    //                    }
//                    //                }
//                    //            }
//                    
//                    // 1. Convert Tensor to Full-Res PixelBuffer (Native Model Scale)
//                    // This ensures we get the full 4x detail from the model before resizing
//                    let nativeTileW = tileWidth * Int(modelScaleFactor)
//                    let nativeTileH = tileHeight * Int(modelScaleFactor)
//                    
//                    guard let nativeBuffer = try? tensorToPixelBuffer(tensor: outputTensor, width: nativeTileW, height: nativeTileH) else {
//                        tilesFailed += 1
//                        continue
//                    }
//                    
//                    // 2. Calculate Target Dimensions
//                    let outX = Int(Double(x) * Double(userScaleFactor))
//                    let outY = Int(Double(y) * Double(userScaleFactor))
//                    let outW = Int(Double(w) * Double(userScaleFactor))
//                    let outH = Int(Double(h) * Double(userScaleFactor))
//                    
//                    // 3. High-Quality Resize if User Scale != Model Scale
//                    var finalTileBuffer = nativeBuffer
//                    if abs(Double(userScaleFactor) - Double(modelScaleFactor)) > 0.001 {
//                        // Resample native buffer (e.g. 4x) down to target buffer (e.g. 2x)
//                        // using Lanczos or Bicubic via vImage to prevent jagged edges
//                        if let scaled = try? resizePixelBuffer(nativeBuffer, width: outW, height: outH) {
//                            finalTileBuffer = scaled
//                        }
//                    }
//                    
//                    // 4. Blend into Main Canvas
//                    let blendMargin = max(1, settings.tileFeatherMarginValue > 0 ? settings.tileFeatherMarginValue : Int(Double(tileOverlap) * Double(userScaleFactor)))
//                    
//                    let isLeft = tileX == 0
//                    let isRight = tileX == tilesX - 1
//                    let isTop = tileY == 0
//                    let isBottom = tileY == tilesY - 1
//                    
//                    do {
//                        // Optional: Drift Guard Baseline (Only if enabled)
//                        // Note: Ensure driftGuardEnabled is defined in your class or method scope
//                        let baseline = driftGuardEnabled ? try? upscaleTileBicubic(tileBuffer, width: outW, height: outH) : nil
//                        
//                        try blendTileIntoCanvas(
//                            source: finalTileBuffer,
//                            target: outputBuffer,
//                            weightMap: weightBuffer,
//                            destX: outX, destY: outY,
//                            width: outW, height: outH,
//                            margin: blendMargin,
//                            useCosine: settings.useCosineFeather,
//                            isLeft: isLeft, isRight: isRight, isTop: isTop, isBottom: isBottom
//                        )
//                    } catch {
//                        tilesFailed += 1
//                    }
//                    
//                    try? normalizeByWeights(buffer: outputBuffer, weightBuffer: weightBuffer)
//                    
//                    
//                    postprocessFrameBuffer(outputBuffer, previous: previousFrameBuffer, settings: settings)
//                    
//                    let frameTime = Date().timeIntervalSince(frameStartTime)
//                    
//                    if tilesFailed > 0 {
//                        log("Frame \(frameCount): \(tilesFailed) tiles failed\n")
//                    }
//                    if driftGuardEnabled && guardedTiles > 0 {
//                        log("DriftGuard: \(guardedTiles) tiles blended for stability\n")
//                    }
//                    if driftGuardEnabled && !guardNotes.isEmpty {
//                        for note in guardNotes.prefix(2) {
//                            log(note + "\n")
//                        }
//                    }
//                    
//                    
//                    while !writerInput.isReadyForMoreMediaData {
//                        try await Task.sleep(nanoseconds: 1_000_000)
//                    }
//                    
//                    if !pixelBufferAdaptor.append(outputBuffer, withPresentationTime: pts) {
//                        log("Failed to append frame at \(pts.seconds)s\n")
//                    }
//                    
//                    
//                    previousFrameBuffer = outputBuffer
//                    
//                    frameCount += 1
//                    if frameCount % 3 == 0 {
//                        let progress = pts.seconds / duration
//                        let elapsed = Date().timeIntervalSince(startTime)
//                        let fps = Double(frameCount) / elapsed
//                        log("Frame \(frameCount): \(String(format: "%.2f", frameTime * 1000))ms | \(String(format: "%.2f", fps)) fps | progress=\(String(format: "%.0f", progress * 100))%\n")
//                    }
//                }
//                
//                
//                let totalTime = Date().timeIntervalSince(startTime)
//                log("\n--- Performance Summary ---\n")
//                log("Total frames: \(frameCount)\n")
//                log("Total time: \(String(format: "%.1f", totalTime))s\n")
//                log("Avg FPS: \(String(format: "%.2f", Double(frameCount) / totalTime))\n")
//                log("Inference time: \(String(format: "%.1f", totalInferenceTime))s (\(String(format: "%.0f", totalInferenceTime / totalTime * 100))%)\n")
//                log("Conversion time: \(String(format: "%.1f", totalConversionTime))s (\(String(format: "%.0f", totalConversionTime / totalTime * 100))%)\n")
//                
//                
//                _ = await audioTask.result
//                
//                writerInput.markAsFinished()
//                await writer.finishWriting()
//                
//                if writer.status == .failed {
//                    log("Writer failed: \(writer.error?.localizedDescription ?? "Unknown")\n")
//                    throw Up60PEngineError.io
//                }
//                
//                log("Done. Output saved to: \(outputURL.path)\n")
//            }
//        }
//    }
//    
//    // MARK: - Helper Methods
//    
//    private func createPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
//        var pixelBuffer: CVPixelBuffer?
//        let options: [String: Any] = [
//            kCVPixelBufferCGImageCompatibilityKey as String: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
//            kCVPixelBufferMetalCompatibilityKey as String: true,
//            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
//        ]
//        
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32BGRA,
//            options as CFDictionary,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
//            throw Up60PEngineError.internalError
//        }
//        
//        CVPixelBufferLockBaseAddress(buffer, [])
//        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
//            let bufferSize = CVPixelBufferGetBytesPerRow(buffer) * height
//            memset(baseAddress, 0, bufferSize)
//        }
//        CVPixelBufferUnlockBaseAddress(buffer, [])
//        
//        return buffer
//    }
//    
//    private func createWeightBuffer(width: Int, height: Int) throws -> UnsafeMutablePointer<Float> {
//        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: width * height)
//        buffer.initialize(repeating: 0, count: width * height)
//        return buffer
//    }
//    
//    private func extractTile(from sourceBuffer: CVPixelBuffer, x: Int, y: Int, width: Int, height: Int, targetWidth: Int, targetHeight: Int) throws -> CVPixelBuffer {
//        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
//        defer { CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly) }
//        
//        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)
//        guard let sourceBase = CVPixelBufferGetBaseAddress(sourceBuffer) else {
//            throw Up60PEngineError.internalError
//        }
//        let sourceData = sourceBase.assumingMemoryBound(to: UInt8.self)
//        
//        let tileBuffer = try createPixelBuffer(width: targetWidth, height: targetHeight)
//        CVPixelBufferLockBaseAddress(tileBuffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(tileBuffer, []) }
//        
//        let tileBytesPerRow = CVPixelBufferGetBytesPerRow(tileBuffer)
//        guard let tileBase = CVPixelBufferGetBaseAddress(tileBuffer) else {
//            throw Up60PEngineError.internalError
//        }
//        let tileData = tileBase.assumingMemoryBound(to: UInt8.self)
//        
//        for row in 0..<height {
//            let sourceOffset = (y + row) * sourceBytesPerRow + x * 4
//            let tileOffset = row * tileBytesPerRow
//            let bytesToCopy = width * 4
//            memcpy(tileData + tileOffset, sourceData + sourceOffset, bytesToCopy)
//        }
//        
//        return tileBuffer
//    }
//    
//    private func upscaleTileBicubic(_ source: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
//        let dest = try createPixelBuffer(width: width, height: height)
//        
//        CVPixelBufferLockBaseAddress(source, .readOnly)
//        CVPixelBufferLockBaseAddress(dest, [])
//        defer {
//            CVPixelBufferUnlockBaseAddress(source, .readOnly)
//            CVPixelBufferUnlockBaseAddress(dest, [])
//        }
//        
//        guard let srcBase = CVPixelBufferGetBaseAddress(source),
//              let dstBase = CVPixelBufferGetBaseAddress(dest) else {
//            throw Up60PEngineError.internalError
//        }
//        
//        var srcBuffer = vImage_Buffer(
//            data: srcBase,
//            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
//            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
//            rowBytes: CVPixelBufferGetBytesPerRow(source)
//        )
//        var dstBuffer = vImage_Buffer(
//            data: dstBase,
//            height: vImagePixelCount(height),
//            width: vImagePixelCount(width),
//            rowBytes: CVPixelBufferGetBytesPerRow(dest)
//        )
//        
//        let error = vImageScale_ARGB8888(&srcBuffer, &dstBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
//        if error != kvImageNoError {
//            throw Up60PEngineError.internalError
//        }
//        
//        return dest
//    }
//    
//    private func pixelBufferToTensor(pixelBuffer: CVPixelBuffer, inputName: String, expectedChannels: Int) throws -> MLMultiArray {
//        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
//        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
//        
//        let width = CVPixelBufferGetWidth(pixelBuffer)
//        let height = CVPixelBufferGetHeight(pixelBuffer)
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
//        let pixelCount = width * height
//        
//        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
//            throw Up60PEngineError.internalError
//        }
//        
//        let channels = max(3, expectedChannels)
//        let shape = [1, channels, height, width] as [NSNumber]
//        let tensor = try MLMultiArray(shape: shape, dataType: .float32)
//        
//        let tensorPtr = UnsafeMutablePointer<Float>(OpaquePointer(tensor.dataPointer))
//        let planes = (0..<channels).map { tensorPtr + pixelCount * $0 }
//        let sourceData = baseAddress.assumingMemoryBound(to: UInt8.self)
//        
//        var rgbChannels = [
//            [Float](repeating: 0, count: pixelCount),
//            [Float](repeating: 0, count: pixelCount),
//            [Float](repeating: 0, count: pixelCount)
//        ]
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let srcIndex = y * bytesPerRow + x * 4
//                let dstIndex = y * width + x
//                rgbChannels[2][dstIndex] = Float(sourceData[srcIndex + 2])
//                rgbChannels[1][dstIndex] = Float(sourceData[srcIndex + 1])
//                rgbChannels[0][dstIndex] = Float(sourceData[srcIndex + 0])
//            }
//        }
//        
//        var scale: Float = 1.0 / 255.0
//        vDSP_vsmul(rgbChannels[2], 1, &scale, planes[0], 1, vDSP_Length(pixelCount))
//        vDSP_vsmul(rgbChannels[1], 1, &scale, planes[1], 1, vDSP_Length(pixelCount))
//        vDSP_vsmul(rgbChannels[0], 1, &scale, planes[2], 1, vDSP_Length(pixelCount))
//        
//        if channels > 3 {
//            for channel in 3..<channels {
//                let sourceIndex = channel % 3
//                memcpy(planes[channel], planes[sourceIndex], pixelCount * MemoryLayout<Float>.size)
//            }
//        }
//        
//        return tensor
//    }
//    
//    private func tensorToPixelBuffer(tensor: MLMultiArray, width: Int, height: Int) throws -> CVPixelBuffer {
//        var pixelBuffer: CVPixelBuffer?
//        let options: [String: Any] = [
//            kCVPixelBufferCGImageCompatibilityKey as String: true,
//            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
//            kCVPixelBufferMetalCompatibilityKey as String: true
//        ]
//        
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            width,
//            height,
//            kCVPixelFormatType_32BGRA,
//            options as CFDictionary,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
//            throw Up60PEngineError.internalError
//        }
//        
//        CVPixelBufferLockBaseAddress(buffer, [])
//        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
//        
//        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
//            throw Up60PEngineError.internalError
//        }
//        
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
//        let pixelData = baseAddress.assumingMemoryBound(to: UInt8.self)
//        
//        for y in 0..<height {
//            for x in 0..<width {
//                let rIndex = [0, 0, y, x] as [NSNumber]
//                let gIndex = [0, 1, y, x] as [NSNumber]
//                let bIndex = [0, 2, y, x] as [NSNumber]
//                
//                let r = tensor[rIndex].floatValue
//                let g = tensor[gIndex].floatValue
//                let b = tensor[bIndex].floatValue
//                
//                let rByte = UInt8(max(0, min(255, r * 255.0)))
//                let gByte = UInt8(max(0, min(255, g * 255.0)))
//                let bByte = UInt8(max(0, min(255, b * 255.0)))
//                
//                let pixelIndex = y * bytesPerRow + x * 4
//                pixelData[pixelIndex + 0] = bByte
//                pixelData[pixelIndex + 1] = gByte
//                pixelData[pixelIndex + 2] = rByte
//                pixelData[pixelIndex + 3] = 255
//            }
//        }
//        return buffer
//    }
//    
//    private func normalizeByWeights(buffer: CVPixelBuffer, weightBuffer: UnsafeMutablePointer<Float>) throws {
//        // Just deallocate weight buffer
//        weightBuffer.deallocate()
//    }
//    
//    /// Resize a CVPixelBuffer using vImage (High Quality Lanczos/Bicubic)
//    private func resizePixelBuffer(_ source: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
//        let dest = try createPixelBuffer(width: width, height: height)
//        
//        CVPixelBufferLockBaseAddress(source, .readOnly)
//        CVPixelBufferLockBaseAddress(dest, [])
//        defer {
//            CVPixelBufferUnlockBaseAddress(source, .readOnly)
//            CVPixelBufferUnlockBaseAddress(dest, [])
//        }
//        
//        var srcVImage = vImage_Buffer(
//            data: CVPixelBufferGetBaseAddress(source),
//            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
//            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
//            rowBytes: CVPixelBufferGetBytesPerRow(source)
//        )
//        
//        var destVImage = vImage_Buffer(
//            data: CVPixelBufferGetBaseAddress(dest),
//            height: vImagePixelCount(height),
//            width: vImagePixelCount(width),
//            rowBytes: CVPixelBufferGetBytesPerRow(dest)
//        )
//        
//        // kvImageHighQualityResampling uses Lanczos-like filter
//        let error = vImageScale_ARGB8888(&srcVImage, &destVImage, nil, vImage_Flags(kvImageHighQualityResampling))
//        if error != kvImageNoError {
//            throw Up60PEngineError.internalError
//        }
//        
//        return dest
//    }
//    
//    /// Blend the prepared tile into the final canvas with feathering
//    private func blendTileIntoCanvas(
//        source: CVPixelBuffer,
//        target: CVPixelBuffer,
//        weightMap: UnsafeMutablePointer<Float>,
//        destX: Int, destY: Int,
//        width: Int, height: Int,
//        margin: Int,
//        useCosine: Bool,
//        isLeft: Bool, isRight: Bool, isTop: Bool, isBottom: Bool
//    ) throws {
//        CVPixelBufferLockBaseAddress(source, .readOnly)
//        CVPixelBufferLockBaseAddress(target, [])
//        defer {
//            CVPixelBufferUnlockBaseAddress(source, .readOnly)
//            CVPixelBufferUnlockBaseAddress(target, [])
//        }
//        
//        guard let srcBase = CVPixelBufferGetBaseAddress(source),
//              let dstBase = CVPixelBufferGetBaseAddress(target) else { return }
//        
//        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(source)
//        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(target)
//        let dstFullWidth = CVPixelBufferGetWidth(target)
//        
//        let srcPtr = srcBase.assumingMemoryBound(to: UInt8.self)
//        let dstPtr = dstBase.assumingMemoryBound(to: UInt8.self)
//        
//        let pi = Float.pi
//        
//        for r in 0..<height {
//            let rowY = destY + r
//            if rowY >= CVPixelBufferGetHeight(target) { break }
//            
//            var wY: Float = 1.0
//            if !isTop && r < margin {
//                let t = Float(r) / Float(margin)
//                wY = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
//            } else if !isBottom && r >= height - margin {
//                let t = Float(height - r) / Float(margin)
//                wY = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
//            }
//            
//            for c in 0..<width {
//                let colX = destX + c
//                if colX >= dstFullWidth { break }
//                
//                var wX: Float = 1.0
//                if !isLeft && c < margin {
//                    let t = Float(c) / Float(margin)
//                    wX = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
//                } else if !isRight && c >= width - margin {
//                    let t = Float(width - c) / Float(margin)
//                    wX = useCosine ? 0.5 * (1.0 - cos(t * pi)) : t
//                }
//                
//                let weight = wX * wY
//                
//                let srcOffset = r * srcBytesPerRow + c * 4
//                let dstOffset = rowY * dstBytesPerRow + colX * 4
//                let weightOffset = rowY * dstFullWidth + colX
//                
//                let sB = Float(srcPtr[srcOffset + 0])
//                let sG = Float(srcPtr[srcOffset + 1])
//                let sR = Float(srcPtr[srcOffset + 2])
//                
//                let dB = Float(dstPtr[dstOffset + 0])
//                let dG = Float(dstPtr[dstOffset + 1])
//                let dR = Float(dstPtr[dstOffset + 2])
//                let currentW = weightMap[weightOffset]
//                
//                let newW = currentW + weight
//                
//                if newW > 0 {
//                    let blendedB = (dB * currentW + sB * weight) / newW
//                    let blendedG = (dG * currentW + sG * weight) / newW
//                    let blendedR = (dR * currentW + sR * weight) / newW
//                    
//                    dstPtr[dstOffset + 0] = UInt8(clamp(blendedB))
//                    dstPtr[dstOffset + 1] = UInt8(clamp(blendedG))
//                    dstPtr[dstOffset + 2] = UInt8(clamp(blendedR))
//                    dstPtr[dstOffset + 3] = 255
//                }
//                
//                weightMap[weightOffset] = newW
//            }
//        }
//    }
//    
//    private func clamp(_ v: Float) -> Float {
//        return max(0, min(255, v))
//    }
//    
//} // End of CoreMLEngine class
//
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
        predictionOptions.usesCPUOnly = false
        
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
