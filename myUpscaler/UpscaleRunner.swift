import Foundation
import Combine
import SwiftUI
import AVFoundation

class UpscaleRunner: ObservableObject {
    
    enum OutputMode { case same, custom }
    
    private static let isAppleSilicon: Bool = {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }()
    
    // MARK: - Dependencies
    private let fileSystem: FileSystemProtocol
    private let engine: EngineProtocol
    private let assetLoader: AssetLoaderProtocol
    // DISABLED: Quality Analyzer feature (kept commented for reference)
    // private let qualityAnalyzer = QualityAnalyzer()
    // DISABLED: Region Masker feature (kept commented for reference)
    // private let regionMasker = RegionMasker()
    
    // MARK: - Input/Output Configuration
    @Published var inputPath = ""
    @Published var outputMode: OutputMode = .custom
    @Published var customOutputFolder = ""
    
    private var activeOutputFolder: String? = nil
    
    private var expectedOutputPath: String? = nil
    private var activeEngine: EngineProtocol?
    
    var securityScopedOutputURL: URL? = nil
    
    // MARK: - Settings Source of Truth
    @Published var settings = UpscaleSettings()
    
    // MARK: - Execution State
    @Published var isRunning = false
    @Published var log = ""
    @Published var completedOutputPath: String? = nil
    
    // MARK: - Progress Stats
    @Published var progress: Double = 0.0
    @Published var fpsString = "0"
    @Published var timeString = "0:00"
    @Published var etaString = "--:--"

    var videoDuration: Double = 0.0
    
    private var currentTask: Task<Void, Never>?
    private var completionCheckTask: Task<Void, Never>?
    private var lastFileSize: Int64 = 0
    private var fileSizeCheckCount: Int = 0

    private var logBuffer: String = ""
    private var lastLogFlushTime: TimeInterval = 0
    private let logFlushInterval: TimeInterval = 0.1
    private var lastErrorLogLine: String?
    
    // MARK: - Initialization
    
    init(fileSystem: FileSystemProtocol = FileManager.default,
         engine: EngineProtocol = Up60PEngine.shared,
         assetLoader: AssetLoaderProtocol = AVAssetLoader()) {
        self.fileSystem = fileSystem
        self.engine = engine
        self.assetLoader = assetLoader
        if let downloads = fileSystem.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            self.customOutputFolder = downloads.path
        }
    }
    
    // MARK: - Computed Properties
    
    var predictedOutputName: String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let base = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            return base + "_[restored].png"
        }
        return base + "_[restored].mp4"
    }
    
    var outputVideoPath: String {
        let folder = outputFolder()
        let fileName = predictedOutputName
        return (folder as NSString).appendingPathComponent(fileName)
    }
    
    func outputFolder() -> String {
        if let active = activeOutputFolder { return active }
        switch outputMode {
        case .same:
            return (inputPath as NSString).deletingLastPathComponent
        case .custom:
            return customOutputFolder
        }
    }
    
    // MARK: - Preset Management
    
    private func getPresetDirectory() -> String {
        let home = fileSystem.homeDirectoryForCurrentUser.path
        let configDir = "\(home)/.config/gptPro/presets"
        return configDir
    }
    
    private func getActivePresetFile() -> String {
        let home = fileSystem.homeDirectoryForCurrentUser.path
        return "\(home)/.config/gptPro/active_preset"
    }
    
    private func ensurePresetDirectories() {
        let presetDir = getPresetDirectory()
        try? fileSystem.createDirectory(atPath: presetDir, withIntermediateDirectories: true, attributes: nil)
    }
    private func cloneSettings(_ settings: UpscaleSettings) -> UpscaleSettings {
        let snapshot = UpscaleSettingsSnapshot(settings: settings)
        let cloned = UpscaleSettings()
        snapshot.apply(to: cloned)
        return cloned
    }
    
    private func savePresetToFile(_ presetName: String) {
        ensurePresetDirectories()
        let presetFile = "\(getPresetDirectory())/\(presetName).preset"
        let s = settings
        
        var content = ""
        content += "codec=\"\(s.useHEVC ? "hevc" : "h264")\"\n"
        content += "crf=\"\(Int(s.crf))\"\n"
        content += "preset=\"\(s.preset)\"\n"
        content += "fps=\"\(s.fps)\"\n"
        content += "scale_factor=\"\(s.scaleFactor)\"\n"
        content += "scaler=\"\(s.scaler)\"\n"
        content += "coreml_model=\"\(s.coremlModelId.rawValue)\"\n"
        content += "ai_backend=\"\(s.aiBackend)\"\n"
        content += "ai_model=\"\(s.aiModelPath)\"\n"
        content += "ai_model_type=\"\(s.aiModelType)\"\n"
        content += "dnn_backend=\"\(s.dnnBackend)\"\n"
        
        // First set of filters
        content += "denoiser=\"\(s.denoiser)\"\n"
        content += "denoise_strength=\"\(s.denoiseStrength)\"\n"
        content += "deblock_mode=\"\(s.deblockMode)\"\n"
        content += "deblock_thresh=\"\(s.deblockThresh)\"\n"
        content += "dering_active=\"\(s.deringActive ? 1 : 0)\"\n"
        content += "dering_strength=\"\(s.deringStrength)\"\n"
        content += "sharpen_method=\"\(s.sharpenMethod)\"\n"
        content += "sharpen_strength=\"\(s.sharpenStrength)\"\n"
        content += "usm_radius=\"\(s.usmRadius)\"\n"
        content += "usm_amount=\"\(s.usmAmount)\"\n"
        content += "usm_threshold=\"\(s.usmThreshold)\"\n"
        content += "deband_method=\"\(s.debandMethod)\"\n"
        content += "deband_strength=\"\(s.debandStrength)\"\n"
        content += "f3kdb_range=\"\(s.f3kdbRange)\"\n"
        content += "f3kdb_y=\"\(s.f3kdbY)\"\n"
        content += "f3kdb_cbcr=\"\(s.f3kdbCbCr)\"\n"
        content += "grain_strength=\"\(s.grainStrength)\"\n"
        
        // Second set of filters
        content += "denoiser_2=\"\(s.denoiser2)\"\n"
        content += "denoise_strength_2=\"\(s.denoiseStrength2)\"\n"
        content += "deblock_mode_2=\"\(s.deblockMode2)\"\n"
        content += "deblock_thresh_2=\"\(s.deblockThresh2)\"\n"
        content += "dering_active_2=\"\(s.deringActive2 ? 1 : 0)\"\n"
        content += "dering_strength_2=\"\(s.deringStrength2)\"\n"
        content += "sharpen_method_2=\"\(s.sharpenMethod2)\"\n"
        content += "sharpen_strength_2=\"\(s.sharpenStrength2)\"\n"
        content += "usm_radius_2=\"\(s.usmRadius2)\"\n"
        content += "usm_amount_2=\"\(s.usmAmount2)\"\n"
        content += "usm_threshold_2=\"\(s.usmThreshold2)\"\n"
        content += "deband_method_2=\"\(s.debandMethod2)\"\n"
        content += "deband_strength_2=\"\(s.debandStrength2)\"\n"
        content += "f3kdb_range_2=\"\(s.f3kdbRange2)\"\n"
        content += "f3kdb_y_2=\"\(s.f3kdbY2)\"\n"
        content += "f3kdb_cbcr_2=\"\(s.f3kdbCbCr2)\"\n"
        content += "grain_strength_2=\"\(s.grainStrength2)\"\n"
        content += "use_denoise_2=\"\(s.useDenoise2 ? 1 : 0)\"\n"
        content += "use_deblock_2=\"\(s.useDeblock2 ? 1 : 0)\"\n"
        content += "use_dering_2=\"\(s.useDering2 ? 1 : 0)\"\n"
        content += "use_sharpen_2=\"\(s.useSharpen2 ? 1 : 0)\"\n"
        content += "use_deband_2=\"\(s.useDeband2 ? 1 : 0)\"\n"
        content += "use_grain_2=\"\(s.useGrain2 ? 1 : 0)\"\n"
        
        content += "mi_mode=\"\(s.interpolation)\"\n"
        content += "eq_contrast=\"\(s.eqContrast)\"\n"
        content += "eq_brightness=\"\(s.eqBrightness)\"\n"
        content += "eq_saturation=\"\(s.eqSaturation)\"\n"
//        content += "lut3d_file=\"\(s.lutPath)\"\n" // LUT DEACTIVATED
        content += "x265_params=\"\(s.x265Params)\"\n"
        content += "outdir=\"\(outputFolder())\"\n"
        content += "audio_bitrate=\"\(s.audioBitrate)\"\n"
        content += "movflags=\"\(s.movflags)\"\n"
        content += "threads=\"\(s.threads)\"\n"
        content += "use10=\"\(s.use10Bit ? 1 : 0)\"\n"
        content += "hwaccel=\"\(s.hwAccel)\"\n"
        content += "encoder=\"\(s.encoder)\"\n"
        content += "preview=\"\(s.preview ? 1 : 0)\"\n"
        content += "no_deblock=\"\(s.noDeblock ? 1 : 0)\"\n"
        content += "no_denoise=\"\(s.noDenoise ? 1 : 0)\"\n"
        content += "no_decimate=\"\(s.noDecimate ? 1 : 0)\"\n"
        content += "no_interpolate=\"\(s.noInterpolate ? 1 : 0)\"\n"
        content += "no_sharpen=\"\(s.noSharpen ? 1 : 0)\"\n"
        content += "no_deband=\"\(s.noDeband ? 1 : 0)\"\n"
        content += "no_eq=\"\(s.noEq ? 1 : 0)\"\n"
        content += "no_grain=\"\(s.noGrain ? 1 : 0)\"\n"

        content += "region_masks=\"0\"\n"
        content += "quality_analyzer=\"0\"\n"
        content += "drift_guard=\"0\"\n"
        content += "pci_safe_mode=\"\(s.pciSafe ? 1 : 0)\"\n"

        _ = URL(fileURLWithPath: presetFile)
        try? content.write(toFile: presetFile, atomically: true, encoding: .utf8)
        
        let activeFile = getActivePresetFile()
        let activeDir = (activeFile as NSString).deletingLastPathComponent
        try? fileSystem.createDirectory(atPath: activeDir, withIntermediateDirectories: true, attributes: nil)
        try? (presetName + "\n").write(toFile: activeFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Execution Logic
    

    private class SafeDuration {
        private var _duration: Double = 0.0
        private let lock = NSLock()
        
        var duration: Double {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _duration
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _duration = newValue
            }
        }
        
        init(duration: Double) {
            self._duration = duration
        }
    }
    
    func run() {
        guard !inputPath.isEmpty else {
            log.append("ERROR: No input file selected.\n")
            return
        }
        
        log = ""
        progress = 0.0
        fpsString = "0"
        timeString = "0:00"
        etaString = "--:--"
        completedOutputPath = nil
        expectedOutputPath = nil
        lastFileSize = 0
        fileSizeCheckCount = 0
        completionCheckTask?.cancel()
        completionCheckTask = nil
        isRunning = true
        lastErrorLogLine = nil
        
        logBuffer = ""
        lastLogFlushTime = Date().timeIntervalSince1970
        
        if !UpscaleRunner.isAppleSilicon && settings.hwAccel == "videotoolbox" {
            settings.hwAccel = "none"
            log.append("Note: VideoToolbox decode not available on this Mac. Falling back to CPU decode.\n\n")
        }
        
        let selectedEngine: EngineProtocol
        if settings.scaler == "coreml" {
            selectedEngine = CoreMLEngine.shared
            log.append("--- Starting CoreML Engine ---\n")
        } else {
            selectedEngine = self.engine
        log.append("--- Starting C Engine ---\n")
        }
        self.activeEngine = selectedEngine
        if settings.hasFilterStacking {
            log.append("\n⚡ SMART FILTER ⚡\n")
            log.append("Multi filter detected. Values auto-adjusted:\n")
            if settings.isSharpenStacked {
                let factor = Int((1.0 - settings.sharpen2AttenuationFactor) * 100)
                log.append("  • Sharpen 2nd set: −\(factor)%")
                if settings.sharpenMethod2 == "cas" {
                    log.append(" (CAS \(settings.sharpenStrength2) → \(settings.effectiveSharpenStrength2))\n")
                } else {
                    log.append(" (Unsharp amount \(settings.usmAmount2) → \(settings.effectiveUsmAmount2))\n")
                }
            }
            if settings.isDenoiseStacked {
                let factor = Int((1.0 - settings.denoise2AttenuationFactor) * 100)
                log.append("  • Denoise 2nd set: −\(factor)% (\(settings.denoiseStrength2) → \(settings.effectiveDenoiseStrength2))\n")
            }
            if settings.isDebandStacked {
                let factor = Int((1.0 - settings.deband2AttenuationFactor) * 100)
                log.append("  • Deband 2nd set: −\(factor)% (\(settings.debandStrength2) → \(settings.effectiveDebandStrength2))\n")
            }
            log.append("This prevents over-processing while.\n\n")
        }
        
        log.append("Input: \(inputPath)\n")
        log.append("Output: \(outputFolder())\n\n")
        log.append("Expected output file: \(outputVideoPath)\n\n")
        
        // Capture safe state for the background callback
        let safeState = SafeDuration(duration: self.videoDuration)
        
        // Set up log handler for the ACTIVE engine
        selectedEngine.setLogHandler { [weak self] message in
            guard let self = self else { return }
            
            // 1. Parse on background thread immediately using safe state
            let currentDur = safeState.duration
            let parseState = FFmpegParser.parse(line: message, currentDuration: currentDur)
            
            // Update safe state if we found a new duration
            if let newDur = parseState.newDuration {
                safeState.duration = newDur
            }
            
            Task { @MainActor in
                // Append to local buffer
                self.logBuffer.append(message)
                
                let lower = message.lowercased()
                if lower.contains("error") || lower.contains("fail") {
                    self.lastErrorLogLine = message
                }
                
                // Apply parsed state
                if let newDur = parseState.newDuration {
                    self.videoDuration = newDur
                }
                if let fps = parseState.fps { self.fpsString = fps }
                if let time = parseState.timeString { self.timeString = time }
                if let prog = parseState.progress { 

                    if prog > self.progress {
                        self.progress = prog
                    }
                }
                if let eta = parseState.eta { self.etaString = eta }
                
                let now = Date().timeIntervalSince1970
                if now - self.lastLogFlushTime >= self.logFlushInterval {
                    self.flushLogBuffer()
                    self.lastLogFlushTime = now
                }
                
                let lowerMessage = message.lowercased()
                let hasElapsed = lowerMessage.contains("elapsed=")
                let isDoneMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) == "Done."
                
                if hasElapsed || isDoneMessage {
                    self.flushLogBuffer()
                    
                    if self.videoDuration > 0 {
                        self.progress = 1.0
                    }
                    if hasElapsed && self.isRunning {
                        self.startCompletionCheck()
                    }
                }
            }
        }
        
        loadVideoDuration()
        
        currentTask?.cancel()
        
        let capturedInputPath = inputPath
        let capturedSettings = cloneSettings(settings)
        let capturedOutputDirectory = outputFolder()
        expectedOutputPath = (capturedOutputDirectory as NSString).appendingPathComponent(predictedOutputName)
        log.append("Writing output to folder:\n\(capturedOutputDirectory)\n\n")
        let accessStopper: (() -> Void)?
        if let scopedURL = securityScopedOutputURL, scopedURL.startAccessingSecurityScopedResource() {
            accessStopper = { scopedURL.stopAccessingSecurityScopedResource() }
            log.append("Using security-scoped output folder: \(scopedURL.path)\n")
        } else {
            accessStopper = nil
        }
        do {
            if !fileSystem.fileExists(atPath: capturedOutputDirectory) {
                try fileSystem.createDirectory(atPath: capturedOutputDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            log.append("\n--- ERROR: Could not create output directory ---\n")
            log.append("Path: \(capturedOutputDirectory)\n")
            log.append("Error: \(error.localizedDescription)\n")
            isRunning = false
            accessStopper?()
            activeOutputFolder = nil
            return
        }
        
        // Verify input file exists before starting
        if !fileSystem.fileExists(atPath: capturedInputPath) {
            log.append("\n--- ERROR: Input file does not exist ---\n")
            log.append("Path: \(capturedInputPath)\n")
            isRunning = false
            activeOutputFolder = nil
            return
        }

        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            defer { accessStopper?() }
            
            do {
                await Task.yield()
                try Task.checkCancellation()
                
                var tunedSettings = capturedSettings
                tunedSettings.useQualityAnalyzer = false
                tunedSettings.regionMasksEnabled = false
                tunedSettings.useDriftGuard = false

                // DISABLED: Quality Analyzer pipeline (kept off to avoid impacting other pipelines)
                await MainActor.run {
                    self.log.append("Quality Analyzer disabled globally.\n\n")
                }

                // DISABLED: Region Masker pipeline (kept off to avoid impacting other pipelines)
                if let core = selectedEngine as? CoreMLEngine {
                    core.regionContext = nil
                }
                await MainActor.run {
                    self.log.append("Region Masker disabled globally.\n\n")
                }
                try await selectedEngine.process(
                    inputPath: capturedInputPath,
                    settings: tunedSettings,
                    outputDirectory: capturedOutputDirectory
                )
                try Task.checkCancellation()
                
                await MainActor.run {
                    if self.isRunning {
                        self.startCompletionCheck()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.log.append("\n--- Process Cancelled ---\n")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isRunning = false
                        self.currentTask = nil
                    }
                }
            } catch let error as Up60PEngineError {
                await MainActor.run {
                    var errorMessage = "\n--- ERROR: "
                    switch error {
                    case .ffmpegNotFound:
                        errorMessage += "FFmpeg executable not found.\n"
                        errorMessage += "Please install FFmpeg via Homebrew:\n"
                        errorMessage += "  brew install ffmpeg\n"
                        errorMessage += "Or set UP60P_FFMPEG environment variable to point to FFmpeg executable.\n"
                    case .invalidOptions:
                        errorMessage += "Invalid options provided.\n"
                    case .io:
                        errorMessage += "I/O error occurred. Please check file paths and permissions.\n"
                    case .internalError:
                        errorMessage += "Internal error occurred.\n"
                    case .notInitialized:
                        errorMessage += "Engine not initialized.\n"
                    case .unknownStatus(let code):
                        errorMessage += "Unknown error (code: \(code)).\n"
                    }
                    if let errorLine = self.lastErrorLogLine {
                        errorMessage += "Context: \(errorLine)\n"
                    }
                    errorMessage += "Input: \(capturedInputPath)\n"
                    errorMessage += "---\n"
                    self.log.append(errorMessage)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isRunning = false
                        self.currentTask = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.log.append("\n--- ERROR: \(error.localizedDescription) ---\n")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isRunning = false
                        self.currentTask = nil
                        self.activeOutputFolder = nil
                    }
                }
            }
        }
    }
    
    func cancel() {
        guard isRunning else { return }
        
        if let engine = activeEngine {
            engine.cancel()
        } else {
        engine.cancel()
        }

        currentTask?.cancel()
        currentTask = nil
        completionCheckTask?.cancel()
        completionCheckTask = nil
        
        isRunning = false
        completedOutputPath = nil
        expectedOutputPath = nil
        activeOutputFolder = nil

        log.append("\n--- User Canceled Process ---\n")
        
        objectWillChange.send()
    }
    
    // MARK: - Video Duration Loading
    
    private func loadVideoDuration() {
        guard !inputPath.isEmpty else {
            videoDuration = 0.0
            return
        }
        
        Task {
            do {
                let duration = try await assetLoader.loadDuration(from: inputPath)
                await MainActor.run {
                    self.videoDuration = duration
                    self.log.append("Video Duration: \(FFmpegParser.formatTime(self.videoDuration))\n")
                }
            } catch {
                await MainActor.run {
                    self.videoDuration = 0.0
                    print("Failed to load video duration: \(error)")
                }
            }
        }
    }
    
    // MARK: - Output File Checking
    
    func checkForCompletedOutput() {
        guard let outputPath = expectedOutputPath ?? Optional(outputVideoPath) else { return }
        if fileSystem.fileExists(atPath: outputPath) {
            if let attributes = try? fileSystem.attributesOfItem(atPath: outputPath),
               let fileSize = attributes[.size] as? Int64,
               fileSize > 0 {
                completedOutputPath = outputPath

                return
            }
        }
        
        if !isRunning && completedOutputPath == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkForCompletedOutputDelayed()
            }
        }
    }
    
    private func checkForCompletedOutputDelayed() {
        guard let outputPath = expectedOutputPath ?? Optional(outputVideoPath) else { return }
        
        if fileSystem.fileExists(atPath: outputPath) {
            if let attributes = try? fileSystem.attributesOfItem(atPath: outputPath),
               let fileSize = attributes[.size] as? Int64,
               fileSize > 0 {
                completedOutputPath = outputPath
            }
        }
    }
    
    // MARK: - Completion Detection
    
    private func startCompletionCheck() {
        completionCheckTask?.cancel()
        
        completionCheckTask = Task { [weak self] in
            guard let self = self else { return }
            
            let outputPath = self.expectedOutputPath ?? self.outputVideoPath
            var stableCount = 0
            var lastSize: Int64 = 0
            let requiredStableChecks = 3
            
            for i in 0..<20 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                let stillRunning = await MainActor.run { self.isRunning }
                guard stillRunning else { return }
                
                if fileSystem.fileExists(atPath: outputPath) {
                    if let attributes = try? fileSystem.attributesOfItem(atPath: outputPath),
                       let fileSize = attributes[.size] as? Int64,
                       fileSize > 0 {
                        
                        if fileSize == lastSize {
                            stableCount += 1
                            if stableCount >= requiredStableChecks {
                                await MainActor.run {
                                    self.markAsComplete(outputPath: outputPath)
                                }
                                return
                            }
                        } else {
                            stableCount = 0
                            lastSize = fileSize
                        }
                    }
                }
            
                if i > 10 {
                    await MainActor.run {
                        if self.fileSystem.fileExists(atPath: outputPath) {
                            self.markAsComplete(outputPath: outputPath)
                            return
                        }
                    }
                }
            }
            
            await MainActor.run {
                if self.fileSystem.fileExists(atPath: outputPath),
                   let attributes = try? self.fileSystem.attributesOfItem(atPath: outputPath),
                   let fileSize = attributes[.size] as? Int64,
                   fileSize > 0 {
                    self.markAsComplete(outputPath: outputPath)
                } else {
                    self.markAsComplete(outputPath: nil)
                }
            }
        }
    }
    
    private func markAsComplete(outputPath: String?) {
        guard isRunning else { return }
        progress = 1.0
        if videoDuration > 0 {
            timeString = FFmpegParser.formatTime(videoDuration)
        }
        activeOutputFolder = nil
        etaString = "0:00"
        
        if let path = outputPath {
            completedOutputPath = path
            log.append("\n--- Process Finished Successfully ---\n")
        } else {
            log.append("\n--- Process Finished (waiting for output file) ---\n")
        }
        
        flushLogBuffer()
        
        isRunning = false
        currentTask?.cancel()
        currentTask = nil
        completionCheckTask?.cancel()
        completionCheckTask = nil
    }
    
    private func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }
        
        log.append(logBuffer)
        logBuffer = ""
        if log.count > 10000 {
            log = String(log.suffix(10000))
        }
    }
}

#if DEBUG
// MARK: - Preview Helpers (DEBUG only)
extension UpscaleRunner {
    static func makePreview() -> UpscaleRunner {
        let runner = UpscaleRunner(
            fileSystem: PreviewFileSystem(),
            engine: PreviewEngine(),
            assetLoader: PreviewAssetLoader()
        )
        runner.inputPath = "/Preview/input.mp4"
        runner.customOutputFolder = "/Preview/output"
        runner.settings.crf = 18
        runner.settings.scaleFactor = 2.0
        runner.settings.fps = "60"
        runner.log = "Preview mode — engine and file system are stubbed.\n"
        runner.progress = 0.3
        runner.fpsString = "60"
        runner.timeString = "0:00"
        runner.etaString = "--:--"
        return runner
    }
}

private final class PreviewFileSystem: FileSystemProtocol {
    var homeDirectoryForCurrentUser: URL { URL(fileURLWithPath: "/Preview/Home") }
    
    func fileExists(atPath path: String) -> Bool { true }
    
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        return [.size: Int64(1_024)]
    }
    
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
    }
    
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        return [URL(fileURLWithPath: "/Preview/Downloads")]
    }
}

private final class PreviewEngine: EngineProtocol {
    private var logHandler: ((String) -> Void)?
    
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        logHandler?("Preview engine: skipping real processing.\n")
        logHandler?("elapsed=00:00:01.00 fps=30.0 progress=1.00\n")
    }
    
    func cancel() {
    }
    
    func setLogHandler(_ handler: @escaping (String) -> Void) {
        logHandler = handler
    }
}

private final class PreviewAssetLoader: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double {
        return 1.0
    }
}
#endif
