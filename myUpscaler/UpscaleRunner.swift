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
    
    private func cloneSettings(_ settings: UpscaleSettings) -> UpscaleSettings {
        let snapshot = UpscaleSettingsSnapshot(settings: settings)
        let cloned = UpscaleSettings()
        snapshot.apply(to: cloned)
        return cloned
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


                // DISABLED: Quality Analyzer pipeline (kept off to avoid impacting other pipelines)
//                await MainActor.run {
//                    self.log.append("Quality Analyzer disabled globally.\n\n")
//                }

                // DISABLED: Region Masker pipeline (kept off to avoid impacting other pipelines)
//                if let core = selectedEngine as? CoreMLEngine {
//                    core.regionContext = nil
//                }
//                await MainActor.run {
//                    self.log.append("Region Masker disabled globally.\n\n")
//                }
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
            }
            
//            catch is CancellationError {
//                await MainActor.run {
//                    self.log.append("\n--- Process Cancelled ---\n")
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        self.isRunning = false
//                        self.currentTask = nil
//                    }
//                }
//            }
            catch let error as Up60PEngineError {
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
