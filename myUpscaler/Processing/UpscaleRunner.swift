import Foundation
import Combine
import SwiftUI
import AVFoundation

class UpscaleRunner: ObservableObject {

    enum OutputMode { case same, custom }
    enum ProcessingPhase { case idle, preparing, processing, finalizing }
    @Published var phase: ProcessingPhase = .idle
    @Published var progressKnown = false

     static let isAppleSilicon: Bool = {
#if arch(arm64)
        return true
#else
        return false
#endif
    }()

    // MARK: - Dependencies
     let fileSystem: FileSystemProtocol
     let engine: EngineProtocol
     let assetLoader: AssetLoaderProtocol
    // MARK: - Input/Output Configuration
    @Published var inputPath = ""
    @Published var outputMode: OutputMode = .custom
    @Published var customOutputFolder = ""

     var activeOutputFolder: String? = nil

     var expectedOutputPath: String? = nil
     var activeEngine: EngineProtocol?

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

     var currentTask: Task<Void, Never>?
    private var currentRunID = UUID()
    @Published private(set) var isCancelling = false

     var logBuffer: String = ""
     var lastLogFlushTime: TimeInterval = 0
     let logFlushInterval: TimeInterval = 1.0
     var lastLogBufferTime: TimeInterval = 0
     let logBufferInterval: TimeInterval = 0.1
     var lastErrorLogLine: String?

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

     func cloneSettings(_ settings: UpscaleSettings) -> UpscaleSettings {
        let snapshot = UpscaleSettingsSnapshot(settings: settings)
        let cloned = UpscaleSettings()
        snapshot.apply(to: cloned)
        return cloned
    }

    // MARK: - Execution Logic
    nonisolated class SafeDuration {
         var _duration: Double = 0.0
         let lock = NSLock()

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
        guard !isRunning else { return }
        if let reason = settings.upscalingUnavailableReason {
            log.append("ERROR: \(reason)\n")
            return
        }
        guard !inputPath.isEmpty else {
            log.append("ERROR: No input file selected.\n")
            return
        }
        let runID = UUID()
        currentRunID = runID

        log = ""
        progress = 0.0
        videoDuration = 0.0
        fpsString = "0"
        timeString = "0:00"
        etaString = "--:--"
        completedOutputPath = nil
        expectedOutputPath = nil
        isCancelling = false
        isRunning = true
        phase = .preparing
        progressKnown = false
        lastErrorLogLine = nil

        logBuffer = ""
        lastLogFlushTime = Date().timeIntervalSince1970
        lastLogBufferTime = Date().timeIntervalSince1970

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
        let updateGate = ProgressUpdateGate()

        // Set up log handler for the ACTIVE engine
        selectedEngine.setLogHandler { [weak self] message in
            guard let self = self else { return }

            guard updateGate.shouldEmit(message) else { return }
            // 1. Parse on background thread immediately using safe state
            let currentDur = safeState.duration
            let parseState = FFmpegParser.parse(line: message, currentDuration: currentDur)

            // Update safe state if we found a new duration
            if let newDur = parseState.newDuration {
                safeState.duration = newDur
            }

            Task { @MainActor in
                guard self.currentRunID == runID, !self.isCancelling else { return }
                let now = Date().timeIntervalSince1970
                let lower = message.lowercased()
                let isError = lower.contains("error") || lower.contains("fail")

                // Always track errors immediately
                if isError {
                    self.lastErrorLogLine = message
                }

                let isProgressMessage = lower.contains("time=") || lower.contains("fps=")
                let shouldBuffer = !isProgressMessage || isError || (now - self.lastLogBufferTime >= self.logBufferInterval)

                if shouldBuffer {
                    self.logBuffer.append(message)
                    if !isError {
                        self.lastLogBufferTime = now
                    }
                }

                // Apply parsed state - update UI stats
                if let newDur = parseState.newDuration {
                    self.videoDuration = newDur
                }
                if let fps = parseState.fps, fps != self.fpsString { self.fpsString = fps }
                if let time = parseState.timeString, time != self.timeString { self.timeString = time }
                if let eta = parseState.eta, eta != self.etaString { self.etaString = eta }
                if let prog = parseState.progress {
                    if prog >= 1 {
                        self.phase = .finalizing
                        self.progressKnown = false
                    } else if self.phase != .finalizing {
                        self.phase = .processing
                        self.progressKnown = true
                        if prog > self.progress { self.progress = prog }
                    }
                }

                // Flush buffer periodically
                if now - self.lastLogFlushTime >= self.logFlushInterval {
                    self.flushLogBuffer()
                    self.lastLogFlushTime = now
                }

                let lowerMessage = message.lowercased()
                let hasElapsed = lowerMessage.contains("elapsed=")
                let isDoneMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) == "Done."

                if hasElapsed || isDoneMessage || lowerMessage.contains("stage=finalizing") {
                    self.flushLogBuffer()

                    self.phase = .finalizing
                    self.progressKnown = false

                }
            }
        }

        loadVideoDuration()

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
            phase = .idle
            accessStopper?()
            activeOutputFolder = nil
            return
        }

        // Verify input file exists before starting
        if !fileSystem.fileExists(atPath: capturedInputPath) {
            log.append("\n--- ERROR: Input file does not exist ---\n")
            log.append("Path: \(capturedInputPath)\n")
            isRunning = false
            phase = .idle
            activeOutputFolder = nil
            accessStopper?()
            return
        }

        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            defer { accessStopper?() }

            do {
                await Task.yield()
                try Task.checkCancellation()

                let tunedSettings = capturedSettings
                try await selectedEngine.process(
                    inputPath: capturedInputPath,
                    settings: tunedSettings,
                    outputDirectory: capturedOutputDirectory
                )
                try Task.checkCancellation()

                try await MainActor.run {
                    guard self.currentRunID == runID else { return }
                    guard let path = self.expectedOutputPath,
                          let attributes = try? self.fileSystem.attributesOfItem(atPath: path),
                          let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                        throw Up60PEngineError.io
                    }
                    self.markAsComplete(outputPath: path)
                }
            }
            catch {
                await MainActor.run {
                    guard self.currentRunID == runID else { return }
                    self.flushLogBuffer()
                    if !(error is CancellationError) && !self.isCancelling {
                        self.log.append("\n--- ERROR: \(error.localizedDescription) ---\n")
                        if let context = self.lastErrorLogLine {
                            self.log.append("Context: \(context)\n")
                        }
                    }
                    self.isRunning = false
                    self.phase = .idle
                    self.progressKnown = false
                    self.isCancelling = false
                    self.expectedOutputPath = nil
                    self.currentTask = nil
                    self.activeOutputFolder = nil
                }
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        guard !isCancelling else { return }
        isCancelling = true
        (activeEngine ?? engine).cancel()
        currentTask?.cancel()
        completedOutputPath = nil
        expectedOutputPath = nil
        log.append("\n--- User Canceled Process (stopping engine) ---\n")
        // Keep the run occupied until process() exits and releases its resources.
    }

    // MARK: - Video Duration Loading

    func loadVideoDuration() {
        guard !inputPath.isEmpty else {
            videoDuration = 0.0
            return
        }

        let path = inputPath
        let runID = currentRunID
        Task {
            do {
                let duration = try await assetLoader.loadDuration(from: path)
                await MainActor.run {
                    guard self.currentRunID == runID, self.inputPath == path else { return }
                    self.videoDuration = duration
                    self.log.append("Video Duration: \(FFmpegParser.formatTime(self.videoDuration))\n")
                }
            } catch {
                await MainActor.run {
                    guard self.currentRunID == runID, self.inputPath == path else { return }
                    self.videoDuration = 0.0
                    print("Failed to load video duration: \(error)")
                }
            }
        }
    }

    // MARK: - Engine-owned completion

    func markAsComplete(outputPath: String) {
        guard isRunning else { return }
        progress = 1.0
        progressKnown = true
        phase = .idle
        if videoDuration > 0 {
            timeString = FFmpegParser.formatTime(videoDuration)
        }
        activeOutputFolder = nil
        etaString = "0:00"

        completedOutputPath = outputPath
        log.append("\n--- Process Finished Successfully ---\n")

        flushLogBuffer()

        isRunning = false
        currentTask = nil
        isCancelling = false
    }

    func flushLogBuffer() {
        guard !logBuffer.isEmpty else { return }

        log.append(logBuffer)
        logBuffer = ""
        if log.count > 10000 {
            log = String(log.suffix(10000))
        }
    }
}
