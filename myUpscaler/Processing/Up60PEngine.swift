import Foundation
import CoreMedia
import Darwin
import Synchronization

enum Up60PEngineError: Error, Equatable {
    case invalidOptions
    case ffmpegNotFound
    case io
    case internalError
    case unknownStatus(Int32)
    case notInitialized
    case unsupportedScaler
}

struct Up60PBridge {
    typealias InitFunc = (_ appSupportDir: UnsafePointer<CChar>?, _ cb: (@convention(c) (UnsafePointer<CChar>?) -> Void)?) -> up60p_error
    typealias DefaultOptionsFunc = (_ opts: UnsafeMutablePointer<up60p_options>?) -> Void
    typealias ProcessFunc = @Sendable (_ input: UnsafePointer<CChar>?, _ opts: UnsafePointer<up60p_options>?) -> up60p_error
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
        processPathFunc: { input, options in up60p_process_path(input, options) },
        setDryRunFunc: up60p_set_dry_run,
        shutdownFunc: up60p_shutdown,
        cancelFunc: up60p_request_cancel
    )
}

// MARK: -

final class Up60PEngine {
    private static var _shared: Up60PEngine?
    private var isInitialized = false
    private static var bridgeOverride: Up60PBridge?
    private static var bridge: Up60PBridge { bridgeOverride ?? .live }
    nonisolated private static let logHandlerState = Mutex<(@Sendable (String) -> Void)?>(nil)
    nonisolated private static var currentLogHandler: (@Sendable (String) -> Void)? {
        logHandlerState.withLock { $0 }
    }

    static var shared: Up60PEngine {
        if let existing = _shared {
            return existing
        }
        let instance = Up60PEngine()
        _shared = instance
        return instance
    }

    static func setLogHandler(_ handler: @escaping @Sendable (String) -> Void) {
        logHandlerState.withLock { $0 = handler }
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

            // Snapshot the callback under the lock; invoke it after releasing it.
            Up60PEngine.currentLogHandler?(cleaned)
        }

        // Snapshot callbacks before dispatch; never invoke user code under a lock.
        log("Initializing C engine...\n")

        // The C engine owns bundle resolution and validates the same path at
        // initialization and before processing. Do not set or honor overrides.
        let result = Self.bridge.initFunc(nil, callback)

        if result != UP60P_OK {
            log("ERROR: C engine initialization failed (code: \(result.rawValue))\n")
            throw mapError(result) ?? .unknownStatus(Int32(result.rawValue))
        }

        log("C engine initialized successfully.\n")

        isInitialized = true
    }

    private func log(_ message: String) {
        guard let handler = Self.currentLogHandler else { return }
        DispatchQueue.main.async { handler(message) }
    }

    private func mapError(_ code: up60p_error) -> Up60PEngineError? {
        switch code {
        case UP60P_ERR_INVALID_OPTIONS:   return .invalidOptions
        case UP60P_ERR_FFMPEG_NOT_FOUND:  return .ffmpegNotFound
        case UP60P_ERR_IO:                return .io
        case UP60P_ERR_INTERNAL:          return .internalError
        case UP60P_ERR_CANCELLED:         return .internalError
        case UP60P_ERR_UNSUPPORTED_SCALER: return .unsupportedScaler
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

    // MARK: -

    private func makeOptions(from settings: UpscaleSettings,
                             outputDir: String) throws -> up60p_options
    {
        guard settings.upscaling.scaler == "lanczos" else {
            throw Up60PEngineError.unsupportedScaler
        }
        guard CodecSupport.isValidCRF(settings.codec.crf) else { throw Up60PEngineError.invalidOptions }
        guard (!settings.primary.useDeblock || DeblockThresholds.isValid(settings.primary.deblockThresh.text)),
              (!settings.secondary.useDeblock || DeblockThresholds.isValid(settings.secondary.deblockThresh.text)) else {
            log("Invalid deblock thresholds: use named alpha/beta/gamma/delta values from 0 to 1, or blank defaults; maximum 63 bytes.\n")
            throw Up60PEngineError.invalidOptions
        }
        try ensureInitialized()

        var opts = up60p_options()
        Up60PEngine.bridge.defaultOptionsFunc(&opts)

        // MARK: Core
        setString(&opts.codec, MemoryLayout.size(ofValue: opts.codec), settings.codec.useHEVC ? "hevc" : "h264")
        setString(&opts.crf, MemoryLayout.size(ofValue: opts.crf), String(Int(settings.codec.crf)))
        setString(&opts.preset, MemoryLayout.size(ofValue: opts.preset), settings.codec.preset)
        setString(&opts.fps, MemoryLayout.size(ofValue: opts.fps), settings.video.fps.text)
        setString(&opts.scale_factor, MemoryLayout.size(ofValue: opts.scale_factor), String(format: "%.2f", settings.video.scaleFactor))

        // MARK: Scaler / AI
        setString(&opts.scaler, MemoryLayout.size(ofValue: opts.scaler), settings.upscaling.scaler)
        setString(&opts.ai_backend, MemoryLayout.size(ofValue: opts.ai_backend), settings.upscaling.aiBackend)
        setString(&opts.ai_model, MemoryLayout.size(ofValue: opts.ai_model), settings.upscaling.aiModelPath)
        setString(&opts.ai_model_type, MemoryLayout.size(ofValue: opts.ai_model_type), settings.upscaling.aiModelType)
        setString(&opts.dnn_backend, MemoryLayout.size(ofValue: opts.dnn_backend), settings.upscaling.dnnBackend)

        // MARK: Filters – first set
        setString(&opts.denoiser, MemoryLayout.size(ofValue: opts.denoiser), settings.primary.denoiser)
        setString(&opts.denoise_strength, MemoryLayout.size(ofValue: opts.denoise_strength), settings.primary.denoiseStrength.text)
        setString(&opts.deblock_mode, MemoryLayout.size(ofValue: opts.deblock_mode), settings.primary.deblockMode)
        setString(&opts.deblock_thresh, MemoryLayout.size(ofValue: opts.deblock_thresh), settings.primary.deblockThresh.text)
        opts.dering_active = settings.primary.useDering ? 1 : 0
        setString(&opts.dering_strength, MemoryLayout.size(ofValue: opts.dering_strength), settings.primary.deringStrength.text)

        setString(&opts.sharpen_method, MemoryLayout.size(ofValue: opts.sharpen_method), settings.primary.sharpenMethod)
        setString(&opts.sharpen_strength, MemoryLayout.size(ofValue: opts.sharpen_strength), settings.primary.sharpenStrength.text)
        setString(&opts.usm_radius, MemoryLayout.size(ofValue: opts.usm_radius), String(Int(UpscaleSettings.unsharpMatrixSize(settings.primary.usmRadius.text))))
        setString(&opts.usm_amount, MemoryLayout.size(ofValue: opts.usm_amount), settings.primary.usmAmount.text)
        setString(&opts.usm_threshold, MemoryLayout.size(ofValue: opts.usm_threshold), settings.primary.usmThreshold.text)

        setString(&opts.deband_method, MemoryLayout.size(ofValue: opts.deband_method), settings.primary.debandMethod)
        setString(&opts.deband_strength, MemoryLayout.size(ofValue: opts.deband_strength), settings.primary.debandStrength.text)
        setString(&opts.f3kdb_range, MemoryLayout.size(ofValue: opts.f3kdb_range), settings.primary.f3kdbRange.text)
        setString(&opts.f3kdb_y, MemoryLayout.size(ofValue: opts.f3kdb_y), settings.primary.f3kdbY.text)
        setString(&opts.f3kdb_cbcr, MemoryLayout.size(ofValue: opts.f3kdb_cbcr), settings.primary.f3kdbCbCr.text)

        setString(&opts.grain_strength, MemoryLayout.size(ofValue: opts.grain_strength), settings.primary.grainStrength.text)

        // MARK: Second set (using EFFECTIVE values for intelligent attenuation when stacking)
        setString(&opts.denoiser_2, MemoryLayout.size(ofValue: opts.denoiser_2), settings.secondary.denoiser)
        // Use EFFECTIVE (attenuated) denoise strength for second set
        setString(&opts.denoise_strength_2, MemoryLayout.size(ofValue: opts.denoise_strength_2), settings.effectiveDenoiseStrength2)
        setString(&opts.deblock_mode_2, MemoryLayout.size(ofValue: opts.deblock_mode_2), settings.secondary.deblockMode)
        setString(&opts.deblock_thresh_2, MemoryLayout.size(ofValue: opts.deblock_thresh_2), settings.secondary.deblockThresh.text)
        opts.dering_active_2 = settings.secondary.useDering ? 1 : 0
        setString(&opts.dering_strength_2, MemoryLayout.size(ofValue: opts.dering_strength_2), settings.secondary.deringStrength.text)

        setString(&opts.sharpen_method_2, MemoryLayout.size(ofValue: opts.sharpen_method_2), settings.secondary.sharpenMethod)
        // Use EFFECTIVE (attenuated) values for second set to prevent over-processing when stacking
        setString(&opts.sharpen_strength_2, MemoryLayout.size(ofValue: opts.sharpen_strength_2), settings.effectiveSharpenStrength2)
        setString(&opts.usm_radius_2, MemoryLayout.size(ofValue: opts.usm_radius_2), settings.effectiveUsmRadius2)
        setString(&opts.usm_amount_2, MemoryLayout.size(ofValue: opts.usm_amount_2), settings.effectiveUsmAmount2)
        setString(&opts.usm_threshold_2, MemoryLayout.size(ofValue: opts.usm_threshold_2), settings.secondary.usmThreshold.text)

        setString(&opts.deband_method_2, MemoryLayout.size(ofValue: opts.deband_method_2), settings.secondary.debandMethod)
        // Use EFFECTIVE (attenuated) deband values for second set
        setString(&opts.deband_strength_2, MemoryLayout.size(ofValue: opts.deband_strength_2), settings.effectiveDebandStrength2)
        setString(&opts.f3kdb_range_2, MemoryLayout.size(ofValue: opts.f3kdb_range_2), settings.secondary.f3kdbRange.text)
        setString(&opts.f3kdb_y_2, MemoryLayout.size(ofValue: opts.f3kdb_y_2), settings.effectiveF3kdbY2)
        setString(&opts.f3kdb_cbcr_2, MemoryLayout.size(ofValue: opts.f3kdb_cbcr_2), settings.effectiveF3kdbCbCr2)

        setString(&opts.grain_strength_2, MemoryLayout.size(ofValue: opts.grain_strength_2), settings.secondary.grainStrength.text)

        opts.use_denoise_2 = settings.secondary.useDenoise ? 1 : 0
        opts.use_deblock_2 = settings.secondary.useDeblock ? 1 : 0
        opts.use_dering_2  = settings.secondary.useDering  ? 1 : 0
        opts.use_sharpen_2 = settings.secondary.useSharpen ? 1 : 0
        opts.use_deband_2  = settings.secondary.useDeband  ? 1 : 0
        opts.use_grain_2   = settings.secondary.useGrain   ? 1 : 0

        // MARK: Other
        setString(&opts.mi_mode, MemoryLayout.size(ofValue: opts.mi_mode), settings.video.interpolation)
        setString(&opts.eq_contrast, MemoryLayout.size(ofValue: opts.eq_contrast), settings.color.eqContrast.text)
        setString(&opts.eq_brightness, MemoryLayout.size(ofValue: opts.eq_brightness), settings.color.eqBrightness.text)
        setString(&opts.eq_saturation, MemoryLayout.size(ofValue: opts.eq_saturation), settings.color.eqSaturation.text)
        setString(&opts.x265_params, MemoryLayout.size(ofValue: opts.x265_params), settings.x265Params)

        setString(&opts.outdir, MemoryLayout.size(ofValue: opts.outdir), outputDir)
        setString(&opts.audio_bitrate, MemoryLayout.size(ofValue: opts.audio_bitrate), settings.output.audioBitrate)
        setString(&opts.threads, MemoryLayout.size(ofValue: opts.threads), settings.hardware.threads.text)
        setString(&opts.movflags, MemoryLayout.size(ofValue: opts.movflags), settings.output.movflags)

        opts.use10        = settings.codec.use10Bit ? 1 : 0
        opts.preview      = settings.modes.preview  ? 1 : 0
        opts.no_deblock   = !settings.primary.useDeblock ? 1 : 0
        opts.no_denoise   = !settings.primary.useDenoise ? 1 : 0
        opts.no_decimate  = settings.modes.noDecimate ? 1 : 0
        opts.no_interpolate = settings.modes.noInterpolate ? 1 : 0
        opts.no_sharpen   = !settings.primary.useSharpen ? 1 : 0
        opts.no_deband    = !settings.primary.useDeband ? 1 : 0
        opts.no_eq        = settings.color.noEq ? 1 : 0
        opts.no_grain     = !settings.primary.useGrain ? 1 : 0
        opts.pci_safe_mode = settings.modes.pciSafe ? 1 : 0

        setString(&opts.hwaccel, MemoryLayout.size(ofValue: opts.hwaccel), settings.hardware.hwAccel)
        setString(&opts.encoder, MemoryLayout.size(ofValue: opts.encoder), settings.hardware.encoder)

        return opts
    }

    private var currentProcessTask: Task<Void, Never>?
    private var currentProcessID: UUID?

    func process(inputPath: String,
                 settings: UpscaleSettings,
                 outputDirectory: String) async throws {
        let previousTask = currentProcessTask
        cancel()
        if let previousTask { await previousTask.value }
        try Task.checkCancellation()

        let codecDecision = CodecSupport.resolve(requestHEVC: settings.codec.useHEVC)
        if let message = codecDecision.message { log(message) }
        settings.codec.useHEVC = codecDecision.useHEVC

        struct StackingSnapshot {
            let has: Bool
            let sharpen: Bool
            let denoise: Bool
            let deband: Bool
            let sharpenPct: Int
            let denoisePct: Int
            let debandPct: Int
        }

        let stackingSnapshot = await MainActor.run { () -> StackingSnapshot in
            let has = settings.hasFilterStacking
            let sharpen = settings.isSharpenStacked
            let denoise = settings.isDenoiseStacked
            let deband = settings.isDebandStacked
            let sharpenPct = Int((1.0 - settings.sharpen2AttenuationFactor) * 100)
            let denoisePct = Int((1.0 - settings.denoise2AttenuationFactor) * 100)
            let debandPct = Int((1.0 - settings.deband2AttenuationFactor) * 100)
            return StackingSnapshot(has: has, sharpen: sharpen, denoise: denoise, deband: deband,
                                    sharpenPct: sharpenPct, denoisePct: denoisePct, debandPct: debandPct)
        }

        // Freeze UI-owned settings before the detached native worker starts.
        let options = try makeOptions(from: settings, outputDir: outputDirectory)
        let inspectSourceTiming = !settings.modes.noInterpolate && settings.video.interpolation != "dup" &&
            settings.video.fps.text != "source" && settings.video.fps.text != "lock"
        let processPath = Self.bridge.processPathFunc

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let processID = UUID()
            currentProcessID = processID
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: Up60PEngineError.internalError)
                    return
                }

                do {
                    await Task.yield()

                    var mutableOpts = options
                    // Per-input metadata only; source/lock and frame selection avoid this scan.
                    if inspectSourceTiming {
                        do {
                            let timing = try await SourceVideoTiming.inspect(url: URL(fileURLWithPath: inputPath))
                            mutableOpts.source_video_duration = timing.duration.seconds.isFinite ? timing.duration.seconds : 0
                            mutableOpts.source_frame_count = timing.frameCount ?? 0
                            mutableOpts.source_rate_num = timing.rateNumerator ?? 0
                            mutableOpts.source_rate_den = timing.rateDenominator ?? 0
                            mutableOpts.source_cfr_verified = timing.isVerifiedCFR ? 1 : 0
                        } catch is CancellationError { throw CancellationError() }
                        catch { await MainActor.run { self.log("Source timing could not be verified; using conservative FPS conversion.\n") } }
                    }
                    try Task.checkCancellation()

                    // Logging (safe)
                    let handler = Up60PEngine.currentLogHandler
                    if handler != nil {
                        await MainActor.run {
                            Up60PEngine.currentLogHandler?("Starting Video Processing...\n")
                        }
                    }

                    if stackingSnapshot.has {
                        await MainActor.run {
                            Up60PEngine.currentLogHandler?("\nFixed finishing-filter strength reduction:\n")

                            if stackingSnapshot.sharpen {
                                Up60PEngine.currentLogHandler?("  • Sharpen 2nd set: reduced by \(stackingSnapshot.sharpenPct)%\n")
                            }
                            if stackingSnapshot.denoise {
                                Up60PEngine.currentLogHandler?("  • Denoise 2nd set: reduced by \(stackingSnapshot.denoisePct)%\n")
                            }
                            if stackingSnapshot.deband {
                                Up60PEngine.currentLogHandler?("  • Deband 2nd set: reduced by \(stackingSnapshot.debandPct)%\n")
                            }

                            Up60PEngine.currentLogHandler?("\n")
                        }
                    }

                    try Task.checkCancellation()
                    let result = processPath(inputPath, &mutableOpts)

                    await MainActor.run {
                        if result == UP60P_ERR_CANCELLED || Task.isCancelled {
                            Up60PEngine.currentLogHandler?("Processing cancelled.\n")
                        } else if result == UP60P_OK {
                            Up60PEngine.currentLogHandler?("Processing completed.\n")
                        } else {
                            Up60PEngine.currentLogHandler?("Processing returned error code: \(result.rawValue)\n")
                        }
                    }

                    if Task.isCancelled || result == UP60P_ERR_CANCELLED {
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
                    continuation.resume(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }

            currentProcessTask = task
            Task { [weak self] in
                await task.value
                guard let self, self.currentProcessID == processID else { return }
                self.currentProcessTask = nil
                self.currentProcessID = nil
            }
        }
    }

    func cancel() {
        guard let task = currentProcessTask else { return }
        Up60PEngine.bridge.cancelFunc()
        task.cancel()
    }
}
