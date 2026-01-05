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

struct UpscaleSettingsSnapshot: Codable, Equatable {
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
    var lutPath: String
    
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
    
    init(settings: UpscaleSettings) {
        useHEVC = settings.useHEVC
        crf = settings.crf
        preset = settings.preset
        use10Bit = settings.use10Bit
        
        x265AqMode = settings.x265AqMode
        x265PsyRd = settings.x265PsyRd
        x265Deblock1 = settings.x265Deblock1
        x265Deblock2 = settings.x265Deblock2
        
        hwAccel = settings.hwAccel
        encoder = settings.encoder
        threads = settings.threads
        
        fps = settings.fps
        scaleFactor = settings.scaleFactor
        interpolation = settings.interpolation
        
        scaler = settings.scaler
        aiModelPath = settings.aiModelPath
        aiBackend = settings.aiBackend
        aiModelType = settings.aiModelType
        dnnBackend = settings.dnnBackend
        
        denoiser = settings.denoiser
        denoiseStrength = settings.denoiseStrength
        deblockMode = settings.deblockMode
        deblockThresh = settings.deblockThresh
        deringActive = settings.deringActive
        deringStrength = settings.deringStrength
        sharpenMethod = settings.sharpenMethod
        sharpenStrength = settings.sharpenStrength
        usmRadius = settings.usmRadius
        usmAmount = settings.usmAmount
        usmThreshold = settings.usmThreshold
        debandMethod = settings.debandMethod
        debandStrength = settings.debandStrength
        f3kdbRange = settings.f3kdbRange
        f3kdbY = settings.f3kdbY
        f3kdbCbCr = settings.f3kdbCbCr
        grainStrength = settings.grainStrength
        
        denoiser2 = settings.denoiser2
        denoiseStrength2 = settings.denoiseStrength2
        useDenoise2 = settings.useDenoise2
        
        deblockMode2 = settings.deblockMode2
        deblockThresh2 = settings.deblockThresh2
        useDeblock2 = settings.useDeblock2
        
        deringActive2 = settings.deringActive2
        deringStrength2 = settings.deringStrength2
        useDering2 = settings.useDering2
        
        sharpenMethod2 = settings.sharpenMethod2
        sharpenStrength2 = settings.sharpenStrength2
        useSharpen2 = settings.useSharpen2
        
        usmRadius2 = settings.usmRadius2
        usmAmount2 = settings.usmAmount2
        usmThreshold2 = settings.usmThreshold2
        
        debandMethod2 = settings.debandMethod2
        debandStrength2 = settings.debandStrength2
        useDeband2 = settings.useDeband2
        
        f3kdbRange2 = settings.f3kdbRange2
        f3kdbY2 = settings.f3kdbY2
        f3kdbCbCr2 = settings.f3kdbCbCr2
        grainStrength2 = settings.grainStrength2
        useGrain2 = settings.useGrain2
        
        eqContrast = settings.eqContrast
        eqBrightness = settings.eqBrightness
        eqSaturation = settings.eqSaturation
        lutPath = settings.lutPath
        
        enableColorLinearize = settings.enableColorLinearize
        colorExposure = settings.colorExposure
        enableToneMap = settings.enableToneMap
        toneMapExposure = settings.toneMapExposure
        encodeToSRGB = settings.encodeToSRGB
        encodeExposure = settings.encodeExposure
        gammaBlendWeight = settings.gammaBlendWeight
        useMedianPrefilter = settings.useMedianPrefilter
        useBlueNoiseDeband = settings.useBlueNoiseDeband
        useLaplacianSharpen = settings.useLaplacianSharpen
        laplacianStrength = settings.laplacianStrength
        useDehalo = settings.useDehalo
        dehaloStrength = settings.dehaloStrength
        useMoireSuppress = settings.useMoireSuppress
        moireStrength = settings.moireStrength
        alphaSafeProcessing = settings.alphaSafeProcessing
        useCosineFeather = settings.useCosineFeather
        tileFeatherMargin = settings.tileFeatherMargin
        useTemporalSmoothing = settings.useTemporalSmoothing
        temporalStrength = settings.temporalStrength
        maskFeatherRadius = settings.maskFeatherRadius
        maskDilateRadius = settings.maskDilateRadius
        maskErodeRadius = settings.maskErodeRadius
        
        audioBitrate = settings.audioBitrate
        movflags = settings.movflags
        
        noDeblock = settings.noDeblock
        noDenoise = settings.noDenoise
        noDecimate = settings.noDecimate
        noInterpolate = settings.noInterpolate
        noSharpen = settings.noSharpen
        noDeband = settings.noDeband
        noEq = settings.noEq
        noGrain = settings.noGrain
        pciSafe = settings.pciSafe
        dryRun = settings.dryRun
        preview = settings.preview
    }
    
    func apply(to settings: UpscaleSettings) {
        settings.useHEVC = useHEVC
        settings.crf = crf
        settings.preset = preset
        settings.use10Bit = use10Bit
        
        settings.x265AqMode = x265AqMode
        settings.x265PsyRd = x265PsyRd
        settings.x265Deblock1 = x265Deblock1
        settings.x265Deblock2 = x265Deblock2
        
        settings.hwAccel = hwAccel
        settings.encoder = encoder
        settings.threads = threads
        
        settings.fps = fps
        settings.scaleFactor = scaleFactor
        settings.interpolation = interpolation
        
        settings.scaler = scaler
        settings.aiModelPath = aiModelPath
        settings.aiBackend = aiBackend
        settings.aiModelType = aiModelType
        settings.dnnBackend = dnnBackend
        
        settings.denoiser = denoiser
        settings.denoiseStrength = denoiseStrength
        settings.deblockMode = deblockMode
        settings.deblockThresh = deblockThresh
        settings.deringActive = deringActive
        settings.deringStrength = deringStrength
        settings.sharpenMethod = sharpenMethod
        settings.sharpenStrength = sharpenStrength
        settings.usmRadius = usmRadius
        settings.usmAmount = usmAmount
        settings.usmThreshold = usmThreshold
        settings.debandMethod = debandMethod
        settings.debandStrength = debandStrength
        settings.f3kdbRange = f3kdbRange
        settings.f3kdbY = f3kdbY
        settings.f3kdbCbCr = f3kdbCbCr
        settings.grainStrength = grainStrength
        
        settings.denoiser2 = denoiser2
        settings.denoiseStrength2 = denoiseStrength2
        settings.useDenoise2 = useDenoise2
        
        settings.deblockMode2 = deblockMode2
        settings.deblockThresh2 = deblockThresh2
        settings.useDeblock2 = useDeblock2
        
        settings.deringActive2 = deringActive2
        settings.deringStrength2 = deringStrength2
        settings.useDering2 = useDering2
        
        settings.sharpenMethod2 = sharpenMethod2
        settings.sharpenStrength2 = sharpenStrength2
        settings.useSharpen2 = useSharpen2
        
        settings.usmRadius2 = usmRadius2
        settings.usmAmount2 = usmAmount2
        settings.usmThreshold2 = usmThreshold2
        
        settings.debandMethod2 = debandMethod2
        settings.debandStrength2 = debandStrength2
        settings.useDeband2 = useDeband2
        
        settings.f3kdbRange2 = f3kdbRange2
        settings.f3kdbY2 = f3kdbY2
        settings.f3kdbCbCr2 = f3kdbCbCr2
        settings.grainStrength2 = grainStrength2
        settings.useGrain2 = useGrain2
        
        settings.eqContrast = eqContrast
        settings.eqBrightness = eqBrightness
        settings.eqSaturation = eqSaturation
        settings.lutPath = lutPath
        
        settings.enableColorLinearize = enableColorLinearize
        settings.colorExposure = colorExposure
        settings.enableToneMap = enableToneMap
        settings.toneMapExposure = toneMapExposure
        settings.encodeToSRGB = encodeToSRGB
        settings.encodeExposure = encodeExposure
        settings.gammaBlendWeight = gammaBlendWeight
        settings.useMedianPrefilter = useMedianPrefilter
        settings.useBlueNoiseDeband = useBlueNoiseDeband
        settings.useLaplacianSharpen = useLaplacianSharpen
        settings.laplacianStrength = laplacianStrength
        settings.useDehalo = useDehalo
        settings.dehaloStrength = dehaloStrength
        settings.useMoireSuppress = useMoireSuppress
        settings.moireStrength = moireStrength
        settings.alphaSafeProcessing = alphaSafeProcessing
        settings.useCosineFeather = useCosineFeather
        settings.tileFeatherMargin = tileFeatherMargin
        settings.useTemporalSmoothing = useTemporalSmoothing
        settings.temporalStrength = temporalStrength
        settings.maskFeatherRadius = maskFeatherRadius
        settings.maskDilateRadius = maskDilateRadius
        settings.maskErodeRadius = maskErodeRadius
        
        settings.audioBitrate = audioBitrate
        settings.movflags = movflags
        
        settings.noDeblock = noDeblock
        settings.noDenoise = noDenoise
        settings.noDecimate = noDecimate
        settings.noInterpolate = noInterpolate
        settings.noSharpen = noSharpen
        settings.noDeband = noDeband
        settings.noEq = noEq
        settings.noGrain = noGrain
        settings.pciSafe = pciSafe
        settings.dryRun = dryRun
        settings.preview = preview
    }
    
    init(from decoder: Decoder) throws {
        let defaults = UpscaleSettings()
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
        lutPath = try container.decodeIfPresent(String.self, forKey: .lutPath) ?? defaults.lutPath
        
        audioBitrate = try container.decodeIfPresent(String.self, forKey: .audioBitrate) ?? defaults.audioBitrate
        movflags = try container.decodeIfPresent(String.self, forKey: .movflags) ?? defaults.movflags
        
        noDeblock = try container.decodeIfPresent(Bool.self, forKey: .noDeblock) ?? defaults.noDeblock
        noDenoise = try container.decodeIfPresent(Bool.self, forKey: .noDenoise) ?? defaults.noDenoise
        noDecimate = try container.decodeIfPresent(Bool.self, forKey: .noDecimate) ?? defaults.noDecimate
        noInterpolate = try container.decodeIfPresent(Bool.self, forKey: .noInterpolate) ?? defaults.noInterpolate
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

