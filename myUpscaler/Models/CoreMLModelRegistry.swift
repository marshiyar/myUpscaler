import Foundation

nonisolated enum CoreMLModelID: String, CaseIterable, Codable, Hashable, Sendable {
    case realESRGANx2 = "RealESRGAN_x2"
    case realESRGANx4 = "RealESRGAN_x4"
    case realESRGANx8 = "RealESRGAN_x8"
}
nonisolated struct CoreMLModelSpec: Identifiable, Hashable, Sendable {
    let id: CoreMLModelID

    // This closed catalog retains the resource names and IDs stored in presets.
    var resourceName: String { id.rawValue }
    var displayName: String { "Real-ESRGAN x\(Int(nativeScale))" }
    var nativeScale: Double {
        switch id {
        case .realESRGANx2: return 2
        case .realESRGANx4: return 4
        case .realESRGANx8: return 8
        }
    }

    // The engine converts BGRA pixels to a single Float32 NCHW RGB tensor.
    func supportsTensorShapes(input: [Int], output: [Int]) -> Bool {
        guard input.count == 4, output.count == 4,
              input[0] == 1, output[0] == 1,
              input[1] == 3, output[1] == 3,
              input[2] > 16, input[2] == input[3] else { return false }
        return Double(output[2]) == Double(input[2]) * nativeScale
            && Double(output[3]) == Double(input[3]) * nativeScale
    }
}
nonisolated enum CoreMLModelRegistry {
    static let models: [CoreMLModelSpec] = CoreMLModelID.allCases.map { model(for: $0) }

    static var defaultModel: CoreMLModelSpec { model(for: .realESRGANx4) }

    static var bundledModels: [CoreMLModelSpec] { bundledModels(in: .main) }

    // Resource discovery is separate from CoreML's tensor/prediction validation.
    static func bundledModels(in bundle: Bundle) -> [CoreMLModelSpec] {
        models.filter { bundledURL(for: $0, bundle: bundle) != nil }
    }

    static func bundledURL(for spec: CoreMLModelSpec, bundle: Bundle = .main) -> URL? {
        for ext in ["mlmodelc", "mlpackage", "mlmodel"] {
            if let url = bundle.url(forResource: spec.resourceName, withExtension: ext),
               FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func model(for id: CoreMLModelID) -> CoreMLModelSpec {
        CoreMLModelSpec(id: id)
    }
}

/// One UI choice maps to the preserved backend and exact model identity.
nonisolated enum UpscalingChoice: Hashable, Sendable, Identifiable {
    case lanczos
    case model(CoreMLModelID)

    var id: String {
        switch self {
        case .lanczos: return "lanczos"
        case .model(let id): return id.rawValue
        }
    }
    var displayName: String {
        switch self {
        case .lanczos: return "Lanczos"
        case .model(let id): return CoreMLModelRegistry.model(for: id).displayName
        }
    }
}
