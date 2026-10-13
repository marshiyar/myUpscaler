import Foundation
import Combine

struct Preset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var snapshot: UpscaleSettingsSnapshot
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         snapshot: UpscaleSettingsSnapshot,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct UpscaleSettingsSnapshot: Codable, Equatable, Sendable {
    var useHEVC: Bool
    var crf: Double
    var preset: String
    var use10Bit: Bool

    var x265AqMode: String
    var x265PsyRd: String
    var x265Deblock1: String
    var x265Deblock2: String

    var hwAccel: String
    var encoder: String
    var threads: String

    var fps: String
    var scaleFactor: Double
    var interpolation: String

    var scaler: String
    var coremlModelId: CoreMLModelID
    var aiModelPath: String
    var aiBackend: String
    var aiModelType: String
    var dnnBackend: String

    var denoiser: String
    var denoiseStrength: String
    var deblockMode: String
    var deblockThresh: String
    var deringActive: Bool
    var deringStrength: String
    var sharpenMethod: String
    var sharpenStrength: String
    var usmRadius: String
    var usmAmount: String
    var usmThreshold: String
    var debandMethod: String
    var debandStrength: String
    var f3kdbRange: String
    var f3kdbY: String
    var f3kdbCbCr: String
    var grainStrength: String

    var denoiser2: String
    var denoiseStrength2: String
    var useDenoise2: Bool

    var deblockMode2: String
    var deblockThresh2: String
    var useDeblock2: Bool

    var deringActive2: Bool
    var deringStrength2: String
    var useDering2: Bool

    var sharpenMethod2: String
    var sharpenStrength2: String
    var useSharpen2: Bool

    var usmRadius2: String
    var usmAmount2: String
    var usmThreshold2: String

    var debandMethod2: String
    var debandStrength2: String
    var useDeband2: Bool

    var f3kdbRange2: String
    var f3kdbY2: String
    var f3kdbCbCr2: String
    var grainStrength2: String
    var useGrain2: Bool

    var eqContrast: String
    var eqBrightness: String
    var eqSaturation: String

    var enableColorLinearize: Bool = true
    var colorExposure: String = "1.0"
    var enableToneMap: Bool = false
    var toneMapExposure: String = "1.0"
    var encodeToSRGB: Bool = true
    var encodeExposure: String = "1.0"
    var gammaBlendWeight: String = "0.0"
    var useMedianPrefilter: Bool = false
    var useBlueNoiseDeband: Bool = true
    var useLaplacianSharpen: Bool = false
    var laplacianStrength: String = "0.15"
    var useDehalo: Bool = false
    var dehaloStrength: String = "0.25"
    var useMoireSuppress: Bool = false
    var moireStrength: String = "0.2"
    var alphaSafeProcessing: Bool = true
    var useCosineFeather: Bool = true
    var tileFeatherMargin: String = "0"
    var useTemporalSmoothing: Bool = false
    var temporalStrength: String = "0.15"
    var maskFeatherRadius: String = "0"
    var maskDilateRadius: String = "0"
    var maskErodeRadius: String = "0"

    var audioBitrate: String
    var movflags: String

    var noDeblock: Bool
    var noDenoise: Bool
    var noDecimate: Bool
    var noInterpolate: Bool
    var noSharpen: Bool
    var noDeband: Bool
    var noEq: Bool
    var noGrain: Bool
    var pciSafe: Bool
    var dryRun: Bool
    var preview: Bool

    @MainActor init(settings: UpscaleSettings) {
        self.init(configuration: settings.configuration)
    }

    init(configuration settings: SettingsConfiguration) {
        useHEVC = settings.codec.useHEVC
        crf = settings.codec.crf
        preset = settings.codec.preset
        use10Bit = settings.codec.use10Bit

        x265AqMode = settings.codec.x265AqMode.text
        x265PsyRd = settings.codec.x265PsyRd.text
        x265Deblock1 = settings.codec.x265Deblock1.text
        x265Deblock2 = settings.codec.x265Deblock2.text

        hwAccel = settings.hardware.hwAccel
        encoder = settings.hardware.encoder
        threads = settings.hardware.threads.text

        fps = settings.video.fps.text
        scaleFactor = settings.video.scaleFactor
        interpolation = settings.video.interpolation

        scaler = settings.upscaling.scaler
        coremlModelId = settings.upscaling.coremlModelId
        aiModelPath = settings.upscaling.aiModelPath
        aiBackend = settings.upscaling.aiBackend
        aiModelType = settings.upscaling.aiModelType
        dnnBackend = settings.upscaling.dnnBackend

        denoiser = settings.primary.denoiser
        denoiseStrength = settings.primary.denoiseStrength.text
        deblockMode = settings.primary.deblockMode
        deblockThresh = settings.primary.deblockThresh.text
        deringActive = settings.primary.useDering
        deringStrength = settings.primary.deringStrength.text
        sharpenMethod = settings.primary.sharpenMethod
        sharpenStrength = settings.primary.sharpenStrength.text
        usmRadius = settings.primary.usmRadius.text
        usmAmount = settings.primary.usmAmount.text
        usmThreshold = settings.primary.usmThreshold.text
        debandMethod = settings.primary.debandMethod
        debandStrength = settings.primary.debandStrength.text
        f3kdbRange = settings.primary.f3kdbRange.text
        f3kdbY = settings.primary.f3kdbY.text
        f3kdbCbCr = settings.primary.f3kdbCbCr.text
        grainStrength = settings.primary.grainStrength.text

        denoiser2 = settings.secondary.denoiser
        denoiseStrength2 = settings.secondary.denoiseStrength.text
        useDenoise2 = settings.secondary.useDenoise

        deblockMode2 = settings.secondary.deblockMode
        deblockThresh2 = settings.secondary.deblockThresh.text
        useDeblock2 = settings.secondary.useDeblock

        deringActive2 = settings.secondary.useDering
        deringStrength2 = settings.secondary.deringStrength.text
        useDering2 = settings.secondary.useDering

        sharpenMethod2 = settings.secondary.sharpenMethod
        sharpenStrength2 = settings.secondary.sharpenStrength.text
        useSharpen2 = settings.secondary.useSharpen

        usmRadius2 = settings.secondary.usmRadius.text
        usmAmount2 = settings.secondary.usmAmount.text
        usmThreshold2 = settings.secondary.usmThreshold.text

        debandMethod2 = settings.secondary.debandMethod
        debandStrength2 = settings.secondary.debandStrength.text
        useDeband2 = settings.secondary.useDeband

        f3kdbRange2 = settings.secondary.f3kdbRange.text
        f3kdbY2 = settings.secondary.f3kdbY.text
        f3kdbCbCr2 = settings.secondary.f3kdbCbCr.text
        grainStrength2 = settings.secondary.grainStrength.text
        useGrain2 = settings.secondary.useGrain

        eqContrast = settings.color.eqContrast.text
        eqBrightness = settings.color.eqBrightness.text
        eqSaturation = settings.color.eqSaturation.text

        enableColorLinearize = settings.metal.enableColorLinearize
        colorExposure = settings.metal.colorExposure.text
        enableToneMap = settings.metal.enableToneMap
        toneMapExposure = settings.metal.toneMapExposure.text
        encodeToSRGB = settings.metal.encodeToSRGB
        encodeExposure = settings.metal.encodeExposure.text
        gammaBlendWeight = settings.metal.gammaBlendWeight.text
        useMedianPrefilter = settings.metal.useMedianPrefilter
        useBlueNoiseDeband = settings.metal.useBlueNoiseDeband
        useLaplacianSharpen = settings.metal.useLaplacianSharpen
        laplacianStrength = settings.metal.laplacianStrength.text
        useDehalo = settings.metal.useDehalo
        dehaloStrength = settings.metal.dehaloStrength.text
        useMoireSuppress = settings.metal.useMoireSuppress
        moireStrength = settings.metal.moireStrength.text
        alphaSafeProcessing = settings.metal.alphaSafeProcessing
        useCosineFeather = settings.metal.useCosineFeather
        tileFeatherMargin = settings.metal.tileFeatherMargin.text
        useTemporalSmoothing = settings.metal.useTemporalSmoothing
        temporalStrength = settings.metal.temporalStrength.text
        maskFeatherRadius = settings.metal.maskFeatherRadius.text
        maskDilateRadius = settings.metal.maskDilateRadius.text
        maskErodeRadius = settings.metal.maskErodeRadius.text

        audioBitrate = settings.output.audioBitrate
        movflags = settings.output.movflags

        noDeblock = !settings.primary.useDeblock
        noDenoise = !settings.primary.useDenoise
        noDecimate = settings.modes.noDecimate
        noInterpolate = settings.modes.noInterpolate
        noSharpen = !settings.primary.useSharpen
        noDeband = !settings.primary.useDeband
        noEq = settings.color.noEq
        noGrain = !settings.primary.useGrain
        pciSafe = settings.modes.pciSafe
        dryRun = settings.modes.dryRun
        preview = settings.modes.preview
    }

    @MainActor func apply(to settings: UpscaleSettings) {
        var candidate = settings.configuration
        candidate.codec.useHEVC = useHEVC
        candidate.codec.crf = crf
        candidate.codec.preset = preset
        candidate.codec.use10Bit = use10Bit

        candidate.codec.x265AqMode.text = x265AqMode
        candidate.codec.x265PsyRd.text = x265PsyRd
        candidate.codec.x265Deblock1.text = x265Deblock1
        candidate.codec.x265Deblock2.text = x265Deblock2

        candidate.hardware.hwAccel = hwAccel
        candidate.hardware.encoder = encoder
        candidate.hardware.threads.text = threads

        candidate.video.fps.text = fps
        candidate.video.scaleFactor = scaleFactor
        candidate.video.interpolation = interpolation

        candidate.upscaling.scaler = scaler
        candidate.upscaling.coremlModelId = coremlModelId
        candidate.upscaling.aiModelPath = aiModelPath
        candidate.upscaling.aiBackend = aiBackend
        candidate.upscaling.aiModelType = aiModelType
        candidate.upscaling.dnnBackend = dnnBackend

        candidate.primary.denoiser = denoiser
        candidate.primary.denoiseStrength.text = denoiseStrength
        candidate.primary.deblockMode = deblockMode
        candidate.primary.deblockThresh.text = deblockThresh
        candidate.primary.useDering = deringActive
        candidate.primary.deringStrength.text = deringStrength
        candidate.primary.sharpenMethod = sharpenMethod
        candidate.primary.sharpenStrength.text = sharpenStrength
        candidate.primary.usmRadius.text = usmRadius
        candidate.primary.usmAmount.text = usmAmount
        candidate.primary.usmThreshold.text = usmThreshold
        candidate.primary.debandMethod = debandMethod
        candidate.primary.debandStrength.text = debandStrength
        candidate.primary.f3kdbRange.text = f3kdbRange
        candidate.primary.f3kdbY.text = f3kdbY
        candidate.primary.f3kdbCbCr.text = f3kdbCbCr
        candidate.primary.grainStrength.text = grainStrength

        candidate.secondary.denoiser = denoiser2
        candidate.secondary.denoiseStrength.text = denoiseStrength2
        candidate.secondary.useDenoise = useDenoise2

        candidate.secondary.deblockMode = deblockMode2
        candidate.secondary.deblockThresh.text = deblockThresh2
        candidate.secondary.useDeblock = useDeblock2

        candidate.secondary.deringStrength.text = deringStrength2
        // Preserve the effective enabled state of presets saved with two switches.
        candidate.secondary.useDering = useDering2 && deringActive2

        candidate.secondary.sharpenMethod = sharpenMethod2
        candidate.secondary.sharpenStrength.text = sharpenStrength2
        candidate.secondary.useSharpen = useSharpen2

        candidate.secondary.usmRadius.text = usmRadius2
        candidate.secondary.usmAmount.text = usmAmount2
        candidate.secondary.usmThreshold.text = usmThreshold2

        candidate.secondary.debandMethod = debandMethod2
        candidate.secondary.debandStrength.text = debandStrength2
        candidate.secondary.useDeband = useDeband2

        candidate.secondary.f3kdbRange.text = f3kdbRange2
        candidate.secondary.f3kdbY.text = f3kdbY2
        candidate.secondary.f3kdbCbCr.text = f3kdbCbCr2
        candidate.secondary.grainStrength.text = grainStrength2
        candidate.secondary.useGrain = useGrain2

        candidate.color.eqContrast.text = eqContrast
        candidate.color.eqBrightness.text = eqBrightness
        candidate.color.eqSaturation.text = eqSaturation

        candidate.metal.enableColorLinearize = enableColorLinearize
        candidate.metal.colorExposure.text = colorExposure
        candidate.metal.enableToneMap = enableToneMap
        candidate.metal.toneMapExposure.text = toneMapExposure
        candidate.metal.encodeToSRGB = encodeToSRGB
        candidate.metal.encodeExposure.text = encodeExposure
        candidate.metal.gammaBlendWeight.text = gammaBlendWeight
        candidate.metal.useMedianPrefilter = useMedianPrefilter
        candidate.metal.useBlueNoiseDeband = useBlueNoiseDeband
        candidate.metal.useLaplacianSharpen = useLaplacianSharpen
        candidate.metal.laplacianStrength.text = laplacianStrength
        candidate.metal.useDehalo = useDehalo
        candidate.metal.dehaloStrength.text = dehaloStrength
        candidate.metal.useMoireSuppress = useMoireSuppress
        candidate.metal.moireStrength.text = moireStrength
        candidate.metal.alphaSafeProcessing = alphaSafeProcessing
        candidate.metal.useCosineFeather = useCosineFeather
        candidate.metal.tileFeatherMargin.text = tileFeatherMargin
        candidate.metal.useTemporalSmoothing = useTemporalSmoothing
        candidate.metal.temporalStrength.text = temporalStrength
        candidate.metal.maskFeatherRadius.text = maskFeatherRadius
        candidate.metal.maskDilateRadius.text = maskDilateRadius
        candidate.metal.maskErodeRadius.text = maskErodeRadius

        candidate.output.audioBitrate = audioBitrate
        candidate.output.movflags = movflags

        candidate.primary.useDeblock = !(noDeblock)
        candidate.primary.useDenoise = !(noDenoise)
        candidate.modes.noDecimate = noDecimate
        candidate.modes.noInterpolate = noInterpolate
        candidate.primary.useSharpen = !(noSharpen)
        candidate.primary.useDeband = !(noDeband)
        candidate.color.noEq = noEq
        candidate.primary.useGrain = !(noGrain)
        candidate.modes.pciSafe = pciSafe
        candidate.modes.dryRun = dryRun
        candidate.modes.preview = preview
        settings.replaceConfiguration(candidate)
    }

    init(from decoder: Decoder) throws {
        let defaults = UpscaleSettingsSnapshot(configuration: SettingsConfiguration())
        let container = try decoder.container(keyedBy: CodingKeys.self)

        useHEVC = try container.decodeIfPresent(Bool.self, forKey: .useHEVC) ?? defaults.useHEVC
        crf = try container.decodeIfPresent(Double.self, forKey: .crf) ?? defaults.crf
        preset = try container.decodeIfPresent(String.self, forKey: .preset) ?? defaults.preset
        use10Bit = try container.decodeIfPresent(Bool.self, forKey: .use10Bit) ?? defaults.use10Bit

        x265AqMode = try container.decodeIfPresent(String.self, forKey: .x265AqMode) ?? defaults.x265AqMode
        x265PsyRd = try container.decodeIfPresent(String.self, forKey: .x265PsyRd) ?? defaults.x265PsyRd
        x265Deblock1 = try container.decodeIfPresent(String.self, forKey: .x265Deblock1) ?? defaults.x265Deblock1
        x265Deblock2 = try container.decodeIfPresent(String.self, forKey: .x265Deblock2) ?? defaults.x265Deblock2

        hwAccel = try container.decodeIfPresent(String.self, forKey: .hwAccel) ?? defaults.hwAccel
        encoder = try container.decodeIfPresent(String.self, forKey: .encoder) ?? defaults.encoder
        threads = try container.decodeIfPresent(String.self, forKey: .threads) ?? defaults.threads

        fps = try container.decodeIfPresent(String.self, forKey: .fps) ?? defaults.fps
        scaleFactor = try container.decodeIfPresent(Double.self, forKey: .scaleFactor) ?? defaults.scaleFactor
        interpolation = try container.decodeIfPresent(String.self, forKey: .interpolation) ?? defaults.interpolation

        scaler = try container.decodeIfPresent(String.self, forKey: .scaler) ?? defaults.scaler
        coremlModelId = try container.decodeIfPresent(CoreMLModelID.self, forKey: .coremlModelId) ?? defaults.coremlModelId
        aiModelPath = try container.decodeIfPresent(String.self, forKey: .aiModelPath) ?? defaults.aiModelPath
        aiBackend = try container.decodeIfPresent(String.self, forKey: .aiBackend) ?? defaults.aiBackend
        aiModelType = try container.decodeIfPresent(String.self, forKey: .aiModelType) ?? defaults.aiModelType
        dnnBackend = try container.decodeIfPresent(String.self, forKey: .dnnBackend) ?? defaults.dnnBackend

        denoiser = try container.decodeIfPresent(String.self, forKey: .denoiser) ?? defaults.denoiser
        denoiseStrength = try container.decodeIfPresent(String.self, forKey: .denoiseStrength) ?? defaults.denoiseStrength
        deblockMode = try container.decodeIfPresent(String.self, forKey: .deblockMode) ?? defaults.deblockMode
        deblockThresh = try container.decodeIfPresent(String.self, forKey: .deblockThresh) ?? defaults.deblockThresh
        deringActive = try container.decodeIfPresent(Bool.self, forKey: .deringActive) ?? defaults.deringActive
        deringStrength = try container.decodeIfPresent(String.self, forKey: .deringStrength) ?? defaults.deringStrength
        sharpenMethod = try container.decodeIfPresent(String.self, forKey: .sharpenMethod) ?? defaults.sharpenMethod
        sharpenStrength = try container.decodeIfPresent(String.self, forKey: .sharpenStrength) ?? defaults.sharpenStrength
        usmRadius = try container.decodeIfPresent(String.self, forKey: .usmRadius) ?? defaults.usmRadius
        usmAmount = try container.decodeIfPresent(String.self, forKey: .usmAmount) ?? defaults.usmAmount
        usmThreshold = try container.decodeIfPresent(String.self, forKey: .usmThreshold) ?? defaults.usmThreshold
        debandMethod = try container.decodeIfPresent(String.self, forKey: .debandMethod) ?? defaults.debandMethod
        debandStrength = try container.decodeIfPresent(String.self, forKey: .debandStrength) ?? defaults.debandStrength
        f3kdbRange = try container.decodeIfPresent(String.self, forKey: .f3kdbRange) ?? defaults.f3kdbRange
        f3kdbY = try container.decodeIfPresent(String.self, forKey: .f3kdbY) ?? defaults.f3kdbY
        f3kdbCbCr = try container.decodeIfPresent(String.self, forKey: .f3kdbCbCr) ?? defaults.f3kdbCbCr
        grainStrength = try container.decodeIfPresent(String.self, forKey: .grainStrength) ?? defaults.grainStrength

        denoiser2 = try container.decodeIfPresent(String.self, forKey: .denoiser2) ?? defaults.denoiser2
        denoiseStrength2 = try container.decodeIfPresent(String.self, forKey: .denoiseStrength2) ?? defaults.denoiseStrength2
        useDenoise2 = try container.decodeIfPresent(Bool.self, forKey: .useDenoise2) ?? defaults.useDenoise2

        deblockMode2 = try container.decodeIfPresent(String.self, forKey: .deblockMode2) ?? defaults.deblockMode2
        deblockThresh2 = try container.decodeIfPresent(String.self, forKey: .deblockThresh2) ?? defaults.deblockThresh2
        useDeblock2 = try container.decodeIfPresent(Bool.self, forKey: .useDeblock2) ?? defaults.useDeblock2

        deringActive2 = try container.decodeIfPresent(Bool.self, forKey: .deringActive2) ?? defaults.deringActive2
        deringStrength2 = try container.decodeIfPresent(String.self, forKey: .deringStrength2) ?? defaults.deringStrength2
        useDering2 = try container.decodeIfPresent(Bool.self, forKey: .useDering2) ?? defaults.useDering2

        sharpenMethod2 = try container.decodeIfPresent(String.self, forKey: .sharpenMethod2) ?? defaults.sharpenMethod2
        sharpenStrength2 = try container.decodeIfPresent(String.self, forKey: .sharpenStrength2) ?? defaults.sharpenStrength2
        useSharpen2 = try container.decodeIfPresent(Bool.self, forKey: .useSharpen2) ?? defaults.useSharpen2

        usmRadius2 = try container.decodeIfPresent(String.self, forKey: .usmRadius2) ?? defaults.usmRadius2
        usmAmount2 = try container.decodeIfPresent(String.self, forKey: .usmAmount2) ?? defaults.usmAmount2
        usmThreshold2 = try container.decodeIfPresent(String.self, forKey: .usmThreshold2) ?? defaults.usmThreshold2

        debandMethod2 = try container.decodeIfPresent(String.self, forKey: .debandMethod2) ?? defaults.debandMethod2
        debandStrength2 = try container.decodeIfPresent(String.self, forKey: .debandStrength2) ?? defaults.debandStrength2
        useDeband2 = try container.decodeIfPresent(Bool.self, forKey: .useDeband2) ?? defaults.useDeband2

        f3kdbRange2 = try container.decodeIfPresent(String.self, forKey: .f3kdbRange2) ?? defaults.f3kdbRange2
        f3kdbY2 = try container.decodeIfPresent(String.self, forKey: .f3kdbY2) ?? defaults.f3kdbY2
        f3kdbCbCr2 = try container.decodeIfPresent(String.self, forKey: .f3kdbCbCr2) ?? defaults.f3kdbCbCr2
        grainStrength2 = try container.decodeIfPresent(String.self, forKey: .grainStrength2) ?? defaults.grainStrength2
        useGrain2 = try container.decodeIfPresent(Bool.self, forKey: .useGrain2) ?? defaults.useGrain2

        eqContrast = try container.decodeIfPresent(String.self, forKey: .eqContrast) ?? defaults.eqContrast
        eqBrightness = try container.decodeIfPresent(String.self, forKey: .eqBrightness) ?? defaults.eqBrightness
        eqSaturation = try container.decodeIfPresent(String.self, forKey: .eqSaturation) ?? defaults.eqSaturation

        audioBitrate = try container.decodeIfPresent(String.self, forKey: .audioBitrate) ?? defaults.audioBitrate
        movflags = try container.decodeIfPresent(String.self, forKey: .movflags) ?? defaults.movflags

        noDeblock = try container.decodeIfPresent(Bool.self, forKey: .noDeblock) ?? defaults.noDeblock
        noDenoise = try container.decodeIfPresent(Bool.self, forKey: .noDenoise) ?? defaults.noDenoise
        noDecimate = try container.decodeIfPresent(Bool.self, forKey: .noDecimate) ?? defaults.noDecimate
        noInterpolate = try container.decodeIfPresent(Bool.self, forKey: .noInterpolate) ?? false
        noSharpen = try container.decodeIfPresent(Bool.self, forKey: .noSharpen) ?? defaults.noSharpen
        noDeband = try container.decodeIfPresent(Bool.self, forKey: .noDeband) ?? defaults.noDeband
        noEq = try container.decodeIfPresent(Bool.self, forKey: .noEq) ?? defaults.noEq
        noGrain = try container.decodeIfPresent(Bool.self, forKey: .noGrain) ?? defaults.noGrain
        pciSafe = try container.decodeIfPresent(Bool.self, forKey: .pciSafe) ?? defaults.pciSafe
        dryRun = try container.decodeIfPresent(Bool.self, forKey: .dryRun) ?? defaults.dryRun
        preview = try container.decodeIfPresent(Bool.self, forKey: .preview) ?? defaults.preview
    }
}

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []

    private let storageURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.homeDirectoryForCurrentUser
        let folder = base.appendingPathComponent("myUpscaler", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        storageURL = folder.appendingPathComponent("presets.json")

        load()
    }

    func add(name: String, settings: UpscaleSettings) {
        let cleaned = cleanedName(name)
        guard !cleaned.isEmpty else { return }

        let unique = uniqueName(for: cleaned)
        let preset = Preset(name: unique, snapshot: UpscaleSettingsSnapshot(settings: settings))
        presets.insert(preset, at: 0)
        persist()
    }

    func update(_ preset: Preset, newName: String? = nil, settings: UpscaleSettings? = nil) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }

        var updated = preset
        if let newName = newName {
            let cleaned = cleanedName(newName)
            if !cleaned.isEmpty {
                updated.name = uniqueName(for: cleaned, ignoring: preset.id)
            }
        }
        if let settings = settings {
            updated.snapshot = UpscaleSettingsSnapshot(settings: settings)
        }
        updated.updatedAt = Date()

        presets[index] = updated
        // Keep most recently touched presets at the top
        presets.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func duplicate(_ preset: Preset) {
        let copyName = uniqueName(for: "\(preset.name) Copy")
        let copy = Preset(name: copyName, snapshot: preset.snapshot)
        presets.insert(copy, at: 0)
        persist()
    }

    func apply(_ preset: Preset, to settings: UpscaleSettings) {
        preset.snapshot.apply(to: settings)
    }

    // TODO: REVIEW THIS PIECE
    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([Preset].self, from: data)
            presets = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            // If decoding fails, start clean rather than crashing the UI
            presets = []
        }
    }

    // TODO: REVIEW THIS PIECE
    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // Intentionally ignore persistence errors to avoid disrupting the UI
        }
    }

    private func cleanedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueName(for proposed: String, ignoring presetID: UUID? = nil) -> String {
        let lowerExisting = presets
            .filter { $0.id != presetID }
            .map { $0.name.lowercased() }

        if !lowerExisting.contains(proposed.lowercased()) {
            return proposed
        }

        var counter = 2
        var candidate = "\(proposed) \(counter)"
        while lowerExisting.contains(candidate.lowercased()) {
            counter += 1
            candidate = "\(proposed) \(counter)"
        }
        return candidate
    }
}

