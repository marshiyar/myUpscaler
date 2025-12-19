import Foundation
import Darwin

enum Up60PEngineError: Error, Equatable {
    case invalidOptions
    case ffmpegNotFound
    case io
    case internalError
    case unknownStatus(Int32)
    case notInitialized
}

struct Up60PBridge {
    typealias InitFunc = (_ appSupportDir: UnsafePointer<CChar>?, _ cb: (@convention(c) (UnsafePointer<CChar>?) -> Void)?) -> up60p_error
    typealias DefaultOptionsFunc = (_ opts: UnsafeMutablePointer<up60p_options>?) -> Void
    typealias ProcessFunc = (_ input: UnsafePointer<CChar>?, _ opts: UnsafePointer<up60p_options>?) -> up60p_error
    typealias SetDryRunFunc = (_ enable: Int32) -> Void
    typealias ShutdownFunc = () -> Void
    typealias CancelFunc = () -> Void
    
    let initFunc: InitFunc
    let defaultOptionsFunc: DefaultOptionsFunc
    let processPathFunc: ProcessFunc
    let setDryRunFunc: SetDryRunFunc
    let shutdownFunc: ShutdownFunc
    let cancelFunc: CancelFunc
    
    static let live = Up60PBridge(
        initFunc: up60p_init,
        defaultOptionsFunc: up60p_default_options,
        processPathFunc: up60p_process_path,
        setDryRunFunc: up60p_set_dry_run,
        shutdownFunc: up60p_shutdown,
        cancelFunc: up60p_request_cancel
    )
}

final class Up60PEngine {
    private static var _shared: Up60PEngine?
    private var isInitialized = false
    private static var bridgeOverride: Up60PBridge?
    private static var bridge: Up60PBridge { bridgeOverride ?? .live }
    nonisolated(unsafe) private static var currentLogHandler: ((String) -> Void)?
    nonisolated private static let logHandlerQueue = DispatchQueue(label: "com.myupscaler.loghandler")
    
    static var shared: Up60PEngine {
        if let existing = _shared {
            return existing
        }
        let instance = Up60PEngine()
        _shared = instance
        return instance
    }
    
    static func setLogHandler(_ handler: @escaping (String) -> Void) {
        logHandlerQueue.sync {
            currentLogHandler = handler
        }
    }
    
    private init() {
        // Don't initialize here - do it lazily on first use
    }
    
    private func ensureInitialized() throws {
        guard !isInitialized else { return }
        
        // Set up the log callback that will forward to the current handler
        let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { message in
            guard let message = message else { return }
            let string = String(cString: message)
            
            // Filter out Metal/AIR shader dumps and binary garbage
            // Only filter if it looks like a large dump or IR code
            if string.count > 500 && (string.contains("air.") || string.contains("metal")) {
                return
            }
            // Filter specific noisy Metal compiler lines even if short
            if string.contains("air.compile") || string.contains("air.read") || string.contains("air.write") {
                return
            }
            
            // Clean up control characters if any (simple scan)
            let cleaned = string.filter { $0.isASCII || $0.isWhitespace || $0.isPunctuation }
            
            Up60PEngine.logHandlerQueue.sync {
                if let handler = Up60PEngine.currentLogHandler {
                    // Dispatch to main thread for UI updates
                    DispatchQueue.main.async {
                        handler(cleaned)
                    }
                }
            }
        }
        
        // Log initialization start
        Up60PEngine.logHandlerQueue.sync {
            if let handler = Up60PEngine.currentLogHandler {
                DispatchQueue.main.async {
                    handler("Initializing C engine...\n")
                    if let envPath = getenv("UP60P_FFMPEG") {
                        let pathStr = String(cString: envPath)
                        handler("UP60P_FFMPEG env var set to: \(pathStr)\n")
                    }
                }
            }
        }
        
        // Resolve bundled ffmpeg relative to the app executable (Contents/MacOS/ffmpeg)
        if getenv("UP60P_FFMPEG") == nil {
            if let exeURL = Bundle.main.executableURL {
                let ffmpegURL = exeURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("ffmpeg")
                
                if FileManager.default.isExecutableFile(atPath: ffmpegURL.path) {
                    ffmpegURL.path.withCString { cStr in
                        setenv("UP60P_FFMPEG", cStr, 1)
                    }
                    
                    Up60PEngine.logHandlerQueue.sync {
                        if let handler = Up60PEngine.currentLogHandler {
                            DispatchQueue.main.async {
                                handler("Using bundled ffmpeg at: \(ffmpegURL.path)\n")
                            }
                        }
                    }
                } else {
                    Up60PEngine.logHandlerQueue.sync {
                        if let handler = Up60PEngine.currentLogHandler {
                            DispatchQueue.main.async {
                                handler("ERROR: Bundled ffmpeg not found or not executable at expected path.\n")
                            }
                        }
                    }
                }
            }
        }
        
        // We could pass an app support dir if the C side ever uses it.
        // C functions don't throw, but we can still check the return value
        let result = Self.bridge.initFunc(nil, callback)
        
        if result != UP60P_OK {
            // Log error before throwing
            Up60PEngine.logHandlerQueue.sync {
                if let handler = Up60PEngine.currentLogHandler {
                    DispatchQueue.main.async {
                        handler("ERROR: C engine initialization failed (code: \(result.rawValue))\n")
                    }
                }
            }
            throw mapError(result) ?? .unknownStatus(Int32(result.rawValue))
        }
        
        // Log successful initialization
        Up60PEngine.logHandlerQueue.sync {
            if let handler = Up60PEngine.currentLogHandler {
                DispatchQueue.main.async {
                    handler("C engine initialized successfully.\n")
                }
            }
        }
        
        isInitialized = true
    }

    private func log(_ message: String) {
        Up60PEngine.logHandlerQueue.sync {
            if let handler = Up60PEngine.currentLogHandler {
                DispatchQueue.main.async {
                    handler(message)
                }
            }
        }
    }
    
    deinit {
        Up60PEngine.bridge.shutdownFunc()
    }
    
    private func mapError(_ code: up60p_error) -> Up60PEngineError? {
        switch code {
        case UP60P_ERR_INVALID_OPTIONS:   return .invalidOptions
        case UP60P_ERR_FFMPEG_NOT_FOUND:  return .ffmpegNotFound
        case UP60P_ERR_IO:                return .io
        case UP60P_ERR_INTERNAL:          return .internalError
        case UP60P_ERR_CANCELLED:         return .internalError
        case UP60P_OK:                    return nil
        default:
            return .unknownStatus(Int32(code.rawValue))
        }
    }
    
    // Helper to write a Swift String into a fixed-size C char[] field
    private func setString<T>(_ field: inout T, _ capacity: Int, _ value: String) {
        withUnsafeMutableBytes(of: &field) { bytes in
            let buffer = bytes.bindMemory(to: CChar.self)
            // Clear the buffer
            memset(buffer.baseAddress, 0, capacity)
            value.withCString { src in
                let copyLen = min(strlen(src), capacity - 1)
                memcpy(buffer.baseAddress, src, copyLen)
                buffer[copyLen] = 0
            }
        }
    }
    
    private func makeOptions(from settings: UpscaleSettings,
                             outputDir: String) throws -> up60p_options
    {
        try ensureInitialized()
        
        var opts = up60p_options()
        Up60PEngine.bridge.defaultOptionsFunc(&opts)    // start from engine defaults / active preset
        
        // MARK: Core
        setString(&opts.codec, MemoryLayout.size(ofValue: opts.codec), settings.useHEVC ? "hevc" : "h264")
        setString(&opts.crf, MemoryLayout.size(ofValue: opts.crf), String(Int(settings.crf)))
        setString(&opts.preset, MemoryLayout.size(ofValue: opts.preset), settings.preset)
        setString(&opts.fps, MemoryLayout.size(ofValue: opts.fps), settings.fps)
        setString(&opts.scale_factor, MemoryLayout.size(ofValue: opts.scale_factor), String(format: "%.2f", settings.scaleFactor))
        
        // MARK: Scaler / AI
        setString(&opts.scaler, MemoryLayout.size(ofValue: opts.scaler), settings.scaler)
        setString(&opts.ai_backend, MemoryLayout.size(ofValue: opts.ai_backend), settings.aiBackend)
        setString(&opts.ai_model, MemoryLayout.size(ofValue: opts.ai_model), settings.aiModelPath)
        setString(&opts.ai_model_type, MemoryLayout.size(ofValue: opts.ai_model_type), settings.aiModelType)
        setString(&opts.dnn_backend, MemoryLayout.size(ofValue: opts.dnn_backend), settings.dnnBackend)
        
        // MARK: Filters – first set
        setString(&opts.denoiser, MemoryLayout.size(ofValue: opts.denoiser), settings.denoiser)
        setString(&opts.denoise_strength, MemoryLayout.size(ofValue: opts.denoise_strength), settings.denoiseStrength)
        setString(&opts.deblock_mode, MemoryLayout.size(ofValue: opts.deblock_mode), settings.deblockMode)
        setString(&opts.deblock_thresh, MemoryLayout.size(ofValue: opts.deblock_thresh), settings.deblockThresh)
        opts.dering_active = settings.deringActive ? 1 : 0
        setString(&opts.dering_strength, MemoryLayout.size(ofValue: opts.dering_strength), settings.deringStrength)
        
        setString(&opts.sharpen_method, MemoryLayout.size(ofValue: opts.sharpen_method), settings.sharpenMethod)
        setString(&opts.sharpen_strength, MemoryLayout.size(ofValue: opts.sharpen_strength), settings.sharpenStrength)
        setString(&opts.usm_radius, MemoryLayout.size(ofValue: opts.usm_radius), settings.usmRadius)
        setString(&opts.usm_amount, MemoryLayout.size(ofValue: opts.usm_amount), settings.usmAmount)
        setString(&opts.usm_threshold, MemoryLayout.size(ofValue: opts.usm_threshold), settings.usmThreshold)
        
        setString(&opts.deband_method, MemoryLayout.size(ofValue: opts.deband_method), settings.debandMethod)
        setString(&opts.deband_strength, MemoryLayout.size(ofValue: opts.deband_strength), settings.debandStrength)
        setString(&opts.f3kdb_range, MemoryLayout.size(ofValue: opts.f3kdb_range), settings.f3kdbRange)
        setString(&opts.f3kdb_y, MemoryLayout.size(ofValue: opts.f3kdb_y), settings.f3kdbY)
        setString(&opts.f3kdb_cbcr, MemoryLayout.size(ofValue: opts.f3kdb_cbcr), settings.f3kdbCbCr)
        
        setString(&opts.grain_strength, MemoryLayout.size(ofValue: opts.grain_strength), settings.grainStrength)
        
        // MARK: Second set (using EFFECTIVE values for intelligent attenuation when stacking)
        setString(&opts.denoiser_2, MemoryLayout.size(ofValue: opts.denoiser_2), settings.denoiser2)
        // Use EFFECTIVE (attenuated) denoise strength for second set
        setString(&opts.denoise_strength_2, MemoryLayout.size(ofValue: opts.denoise_strength_2), settings.effectiveDenoiseStrength2)
        setString(&opts.deblock_mode_2, MemoryLayout.size(ofValue: opts.deblock_mode_2), settings.deblockMode2)
        setString(&opts.deblock_thresh_2, MemoryLayout.size(ofValue: opts.deblock_thresh_2), settings.deblockThresh2)
        opts.dering_active_2 = settings.deringActive2 ? 1 : 0
        setString(&opts.dering_strength_2, MemoryLayout.size(ofValue: opts.dering_strength_2), settings.deringStrength2)
        
        setString(&opts.sharpen_method_2, MemoryLayout.size(ofValue: opts.sharpen_method_2), settings.sharpenMethod2)
        // Use EFFECTIVE (attenuated) values for second set to prevent over-processing when stacking
        setString(&opts.sharpen_strength_2, MemoryLayout.size(ofValue: opts.sharpen_strength_2), settings.effectiveSharpenStrength2)
        setString(&opts.usm_radius_2, MemoryLayout.size(ofValue: opts.usm_radius_2), settings.effectiveUsmRadius2)
        setString(&opts.usm_amount_2, MemoryLayout.size(ofValue: opts.usm_amount_2), settings.effectiveUsmAmount2)
        setString(&opts.usm_threshold_2, MemoryLayout.size(ofValue: opts.usm_threshold_2), settings.usmThreshold2)
        
        setString(&opts.deband_method_2, MemoryLayout.size(ofValue: opts.deband_method_2), settings.debandMethod2)
        // Use EFFECTIVE (attenuated) deband values for second set
        setString(&opts.deband_strength_2, MemoryLayout.size(ofValue: opts.deband_strength_2), settings.effectiveDebandStrength2)
        setString(&opts.f3kdb_range_2, MemoryLayout.size(ofValue: opts.f3kdb_range_2), settings.f3kdbRange2)
        setString(&opts.f3kdb_y_2, MemoryLayout.size(ofValue: opts.f3kdb_y_2), settings.effectiveF3kdbY2)
        setString(&opts.f3kdb_cbcr_2, MemoryLayout.size(ofValue: opts.f3kdb_cbcr_2), settings.effectiveF3kdbCbCr2)
        
        setString(&opts.grain_strength_2, MemoryLayout.size(ofValue: opts.grain_strength_2), settings.grainStrength2)
        
        opts.use_denoise_2 = settings.useDenoise2 ? 1 : 0
        opts.use_deblock_2 = settings.useDeblock2 ? 1 : 0
        opts.use_dering_2  = settings.useDering2  ? 1 : 0
        opts.use_sharpen_2 = settings.useSharpen2 ? 1 : 0
        opts.use_deband_2  = settings.useDeband2  ? 1 : 0
        opts.use_grain_2   = settings.useGrain2   ? 1 : 0
        
        // MARK: Other
        setString(&opts.mi_mode, MemoryLayout.size(ofValue: opts.mi_mode), settings.interpolation)
        setString(&opts.eq_contrast, MemoryLayout.size(ofValue: opts.eq_contrast), settings.eqContrast)
        setString(&opts.eq_brightness, MemoryLayout.size(ofValue: opts.eq_brightness), settings.eqBrightness)
        setString(&opts.eq_saturation, MemoryLayout.size(ofValue: opts.eq_saturation), settings.eqSaturation)
        setString(&opts.lut3d_file, MemoryLayout.size(ofValue: opts.lut3d_file), settings.lutPath)
        setString(&opts.x265_params, MemoryLayout.size(ofValue: opts.x265_params), settings.x265Params)
        
        setString(&opts.outdir, MemoryLayout.size(ofValue: opts.outdir), outputDir)
        setString(&opts.audio_bitrate, MemoryLayout.size(ofValue: opts.audio_bitrate), settings.audioBitrate)
        setString(&opts.threads, MemoryLayout.size(ofValue: opts.threads), settings.threads)
        setString(&opts.movflags, MemoryLayout.size(ofValue: opts.movflags), settings.movflags)
        
        opts.use10        = settings.use10Bit ? 1 : 0
        opts.preview      = settings.preview  ? 1 : 0
        opts.no_deblock   = settings.noDeblock ? 1 : 0
        opts.no_denoise   = settings.noDenoise ? 1 : 0
        opts.no_decimate  = settings.noDecimate ? 1 : 0
        opts.no_interpolate = settings.noInterpolate ? 1 : 0
        opts.no_sharpen   = settings.noSharpen ? 1 : 0
        opts.no_deband    = settings.noDeband ? 1 : 0
        opts.no_eq        = settings.noEq ? 1 : 0
        opts.no_grain     = settings.noGrain ? 1 : 0
        opts.pci_safe_mode = settings.pciSafe ? 1 : 0
        
        setString(&opts.hwaccel, MemoryLayout.size(ofValue: opts.hwaccel), settings.hwAccel)
        setString(&opts.encoder, MemoryLayout.size(ofValue: opts.encoder), settings.encoder)
        
        return opts
    }
    
    private var currentProcessTask: Task<Void, Never>?
    
    func process(inputPath: String,
                 settings: UpscaleSettings,
                 outputDirectory: String) async throws {
        // Cancel any existing process
        cancel()

        let codecDecision = CodecSupport.resolve(requestHEVC: settings.useHEVC)
        if let message = codecDecision.message {
            log(message)
        }
        settings.useHEVC = codecDecision.useHEVC


        struct StackingSnapshot {
            let has: Bool
            let sharpen: Bool
            let denoise: Bool
            let deband: Bool
            let sharpenPct: Int
            let denoisePct: Int
            let debandPct: Int
        }
        
        // Capture stacking info on the MainActor to avoid isolation issues later
        let stackingSnapshot = await MainActor.run { () -> StackingSnapshot in
            let has = settings.hasFilterStacking
            let sharpen = settings.isSharpenStacked
            let denoise = settings.isDenoiseStacked
            let deband = settings.isDebandStacked
            let sharpenPct = Int((1.0 - settings.sharpen2AttenuationFactor) * 100)
            let denoisePct = Int((1.0 - settings.denoise2AttenuationFactor) * 100)
            let debandPct = Int((1.0 - settings.deband2AttenuationFactor) * 100)
            return StackingSnapshot(has: has, sharpen: sharpen, denoise: denoise, deband: deband, sharpenPct: sharpenPct, denoisePct: denoisePct, debandPct: debandPct)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: Up60PEngineError.internalError)
                    return
                }
                
                do {
                    await Task.yield()
                    let opts = try await MainActor.run {
                        try self.makeOptions(from: settings, outputDir: outputDirectory)
                    }
                    var mutableOpts = opts
                    await Task.yield()
                    Up60PEngine.logHandlerQueue.sync {
                        if let handler = Up60PEngine.currentLogHandler {
                            DispatchQueue.main.async {
                                handler("Starting video processing...\n")
                            }
                        }
                    }
                    Up60PEngine.logHandlerQueue.sync {
                        if let handler = Up60PEngine.currentLogHandler {
                            DispatchQueue.main.async {
                                handler("NOTE: If this is the first run, AI initialization (Metal shader compilation) may take 1-2 minutes. Please wait...\n")
                            }
                        }
                    }
                    if stackingSnapshot.has {
                        Up60PEngine.logHandlerQueue.sync {
                            if let handler = Up60PEngine.currentLogHandler {
                                DispatchQueue.main.async {
                                    handler("\n⚡ Filter Stacking Detected - Applying Smart Attenuation:\n")
                                    if stackingSnapshot.sharpen {
                                        let factor = stackingSnapshot.sharpenPct
                                        handler("  • Sharpen 2nd set: reduced by \(factor)% to prevent over-sharpening\n")
                                    }
                                    if stackingSnapshot.denoise {
                                        let factor = stackingSnapshot.denoisePct
                                        handler("  • Denoise 2nd set: reduced by \(factor)% to prevent over-smoothing\n")
                                    }
                                    if stackingSnapshot.deband {
                                        let factor = stackingSnapshot.debandPct
                                        handler("  • Deband 2nd set: reduced by \(factor)% to prevent banding artifacts\n")
                                    }
                                    handler("\n")
                                }
                            }
                        }
                    }
                    
                    let result = await Up60PEngine.bridge.processPathFunc(inputPath, &mutableOpts)
                    
                    // Log result
                    Up60PEngine.logHandlerQueue.sync {
                        if let handler = Up60PEngine.currentLogHandler {
                            DispatchQueue.main.async {
                                if result == UP60P_ERR_CANCELLED || Task.isCancelled {
                                    handler("Processing cancelled.\n")
                                } else if result == UP60P_OK {
                                    handler("Processing completed.\n")
                                } else {
                                    handler("Processing returned error code: \(result.rawValue)\n")
                                }
                            }
                        }
                    }
                    
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if result == UP60P_OK {
                        continuation.resume()
                    } else {
                        let error = await MainActor.run {
                            self.mapError(result) ?? .unknownStatus(Int32(result.rawValue))
                        }
                        continuation.resume(throwing: error)
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
            currentProcessTask = task
        }
    }
    
    func cancel() {
        guard let task = currentProcessTask else { return }
        Up60PEngine.bridge.cancelFunc()
        task.cancel()
        
        let engine = self
        Task.detached {
            await task.value
            
            Up60PEngine.logHandlerQueue.sync {
                if let handler = Up60PEngine.currentLogHandler {
                    DispatchQueue.main.async {
                        handler("Cancellation acknowledged by native engine.\n")
                    }
                }
            }
            
            await MainActor.run {
                engine.currentProcessTask = nil
            }
        }
    }
    
    // MARK: - Testing Support
    
    func setDryRun(_ enabled: Bool) {
        Up60PEngine.bridge.setDryRunFunc(enabled ? 1 : 0)
    }
    
#if DEBUG
    /// Override the C bridge for deterministic testing
    static func useBridgeForTesting(_ bridge: Up60PBridge) {
        bridgeOverride = bridge
    }
    
    /// Reset to the live bridge after tests
    static func resetBridgeForTesting() {
        bridgeOverride = nil
    }
    
    /// Expose error mapping for tests
    func mapErrorForTesting(_ code: up60p_error) -> Up60PEngineError? {
        mapError(code)
    }
#endif
}
