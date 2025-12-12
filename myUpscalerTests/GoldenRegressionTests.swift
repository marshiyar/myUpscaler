import Foundation
import Testing
@testable import myUpscaler

private struct OptionsSnapshot: Codable, Equatable {
    let ai_backend: String
    let ai_model: String
    let audio_bitrate: String
    let codec: String
    let crf: String
    let deband_method: String
    let denoiser: String
    let encoder: String
    let fps: String
    let hwaccel: String
    let movflags: String
    let no_deband: Int32
    let no_deblock: Int32
    let no_denoise: Int32
    let no_eq: Int32
    let no_grain: Int32
    let no_interpolate: Int32
    let no_sharpen: Int32
    let outdir: String
    let pci_safe_mode: Int32
    let preset: String
    let preview: Int32
    let scale_factor: String
    let scaler: String
    let threads: String
    let use10: Int32
    
    init(options: up60p_options) {
        ai_backend = OptionsSnapshot.decodeString(field: options.ai_backend)
        ai_model = OptionsSnapshot.decodeString(field: options.ai_model)
        audio_bitrate = OptionsSnapshot.decodeString(field: options.audio_bitrate)
        codec = OptionsSnapshot.decodeString(field: options.codec)
        crf = OptionsSnapshot.decodeString(field: options.crf)
        deband_method = OptionsSnapshot.decodeString(field: options.deband_method)
        denoiser = OptionsSnapshot.decodeString(field: options.denoiser)
        encoder = OptionsSnapshot.decodeString(field: options.encoder)
        fps = OptionsSnapshot.decodeString(field: options.fps)
        hwaccel = OptionsSnapshot.decodeString(field: options.hwaccel)
        movflags = OptionsSnapshot.decodeString(field: options.movflags)
        no_deband = Int32(options.no_deband)
        no_deblock = Int32(options.no_deblock)
        no_denoise = Int32(options.no_denoise)
        no_eq = Int32(options.no_eq)
        no_grain = Int32(options.no_grain)
        no_interpolate = Int32(options.no_interpolate)
        no_sharpen = Int32(options.no_sharpen)
        outdir = OptionsSnapshot.decodeString(field: options.outdir)
        pci_safe_mode = Int32(options.pci_safe_mode)
        preset = OptionsSnapshot.decodeString(field: options.preset)
        preview = Int32(options.preview)
        scale_factor = OptionsSnapshot.decodeString(field: options.scale_factor)
        scaler = OptionsSnapshot.decodeString(field: options.scaler)
        threads = OptionsSnapshot.decodeString(field: options.threads)
        use10 = Int32(options.use10)
    }
    
    private static func decodeString<T>(field: T) -> String {
        var mutableField = field
        let size = MemoryLayout.size(ofValue: mutableField)
        return withUnsafePointer(to: &mutableField) {
            $0.withMemoryRebound(to: CChar.self, capacity: size) { ptr in
                String(cString: ptr).trimmingCharacters(in: .controlCharacters.union(.init(charactersIn: "\0")))
            }
        }
    }
}

private final class SnapshotRecorder {
    var capturedOptions: up60p_options?
    var processCalls = 0
}

private func makeSnapshotBridge(recorder: SnapshotRecorder) -> Up60PBridge {
    Up60PBridge(
        initFunc: { _, _ in UP60P_OK },
        defaultOptionsFunc: { opts in
            if let opts = opts {
                opts.pointee = up60p_options()
            }
        },
        processPathFunc: { _, opts in
            recorder.processCalls += 1
            if let opts = opts {
                recorder.capturedOptions = opts.pointee
            }
            return UP60P_OK
        },
        setDryRunFunc: { _ in },
        shutdownFunc: {},
        cancelFunc: {}
    )
}

private func loadFixture(named name: String) throws -> String {
    let currentFile = URL(fileURLWithPath: #filePath)
    let fixturesDir = currentFile.deletingLastPathComponent().appendingPathComponent("Fixtures")
    let fixtureURL = fixturesDir.appendingPathComponent(name)
    return try String(contentsOf: fixtureURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func encodeSnapshot(_ snapshot: OptionsSnapshot) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    guard let string = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "encodeSnapshot", code: -1, userInfo: nil)
    }
    return string.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor struct GoldenRegressionTests {
    
    @Test("Baseline video options should match golden fixture")
    func testVideoOptionsSnapshot() async throws {
        let recorder = SnapshotRecorder()
        Up60PEngine.useBridgeForTesting(makeSnapshotBridge(recorder: recorder))
        defer { Up60PEngine.resetBridgeForTesting() }
        
        let engine = Up60PEngine.shared
        let settings = UpscaleSettings()
        settings.useHEVC = true
        settings.crf = 21.0
        settings.preset = "slow"
        settings.fps = "30"
        settings.scaleFactor = 1.75
        settings.scaler = "ai"
        settings.aiBackend = "sr"
        settings.aiModelPath = "/models/demo.pb"
        settings.dnnBackend = "tensorflow"
        settings.denoiser = "nlmeans"
        settings.debandMethod = "f3kdb"
        settings.audioBitrate = "160k"
        settings.threads = "4"
        settings.movflags = "+faststart"
        settings.hwAccel = "videotoolbox"
        settings.encoder = "h264_videotoolbox"
        settings.use10Bit = true
        
        try await engine.process(
            inputPath: "/tmp/input.mp4",
            settings: settings,
            outputDirectory: "/tmp/output"
        )
        
        #expect(recorder.processCalls == 1)
        guard let opts = recorder.capturedOptions else {
            #expect(Bool(false), "No options captured")
            return
        }
        let snapshot = OptionsSnapshot(options: opts)
        let json = try encodeSnapshot(snapshot)
        let fixture = try loadFixture(named: "video_options.json")
        #expect(json == fixture)
    }
    
    @Test("Image options should match golden fixture")
    func testImageOptionsSnapshot() async throws {
        let recorder = SnapshotRecorder()
        Up60PEngine.useBridgeForTesting(makeSnapshotBridge(recorder: recorder))
        defer { Up60PEngine.resetBridgeForTesting() }
        
        let engine = Up60PEngine.shared
        let settings = UpscaleSettings()
        settings.useHEVC = false
        settings.crf = 18.0
        settings.preset = "fast"
        settings.fps = "source"
        settings.scaleFactor = 3.0
        settings.scaler = "zscale"
        settings.aiBackend = "sr"
        settings.aiModelPath = "/models/unused.pb"
        settings.dnnBackend = "tensorflow"
        settings.denoiser = "bm3d"
        settings.debandMethod = "deband"
        settings.audioBitrate = "192k"
        settings.threads = "2"
        settings.movflags = ""
        settings.hwAccel = "none"
        settings.encoder = "auto"
        settings.noDenoise = true
        settings.noDeband = false
        settings.noDeblock = true
        settings.noInterpolate = true
        settings.noSharpen = false
        settings.noEq = true
        settings.noGrain = true
        settings.pciSafe = false
        
        try await engine.process(
            inputPath: "/tmp/input.png",
            settings: settings,
            outputDirectory: "/tmp/images"
        )
        
        #expect(recorder.processCalls == 1)
        guard let opts = recorder.capturedOptions else {
            #expect(Bool(false), "No options captured")
            return
        }
        let snapshot = OptionsSnapshot(options: opts)
        let json = try encodeSnapshot(snapshot)
        let fixture = try loadFixture(named: "image_options.json")
        #expect(json == fixture)
    }
}

