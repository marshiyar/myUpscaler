import Foundation

nonisolated enum CoreMLModelID: String, CaseIterable, Codable, Hashable, Sendable {
    case realESRGANx2 = "RealESRGAN_x2"
    case realESRGANx4 = "RealESRGAN_x4"
    case realESRGANx8 = "RealESRGAN_x8"
    case realESRGANx2FP16 = "RealESRGAN_x2_FP16"
    case realESRGANx4FP16 = "RealESRGAN_x4_FP16"
    case realESRGANx8Author = "RealESRGAN_x8_Author"
    case coreAIlocX2FP32 = "RealESRGAN_CoreAI_Local_x2_FP32_128"
    case coreAIlocX2FP16 = "RealESRGAN_CoreAI_Local_x2_FP16_128"
    case coreAIlocX2W8 = "RealESRGAN_CoreAI_Local_x2_W8_128"
    case coreAIlocX2P6 = "RealESRGAN_CoreAI_Local_x2_P6_128"
    case coreAIproX2T128 = "RealESRGAN_CoreAI_Pro_x2_FP16_128"
    case coreAIproX2T256 = "RealESRGAN_CoreAI_Pro_x2_FP16_256"
    case coreAIproX2T512 = "RealESRGAN_CoreAI_Pro_x2_FP16_512"
    case coreAIlocX4FP32 = "RealESRGAN_CoreAI_Local_x4_FP32_128"
    case coreAIlocX4FP16 = "RealESRGAN_CoreAI_Local_x4_FP16_128"
    case coreAIlocX4W8 = "RealESRGAN_CoreAI_Local_x4_W8_128"
    case coreAIlocX4P6 = "RealESRGAN_CoreAI_Local_x4_P6_128"
    case coreAIproX4T128 = "RealESRGAN_CoreAI_Pro_x4_FP16_128"
    case coreAIproX4T256 = "RealESRGAN_CoreAI_Pro_x4_FP16_256"
    case coreAIx2FP32 = "RealESRGAN_CoreAI_x2_FP32"
    case coreAIx4FP32 = "RealESRGAN_CoreAI_x4_FP32"
    case coreAIx8FP32 = "RealESRGAN_CoreAI_x8_FP32"
    case coreAIx8W8 = "RealESRGAN_CoreAI_x8_W8"
}
nonisolated enum AIModelBackend: Sendable { case coreML, coreAI }

nonisolated struct CoreMLModelSpec: Identifiable, Hashable, Sendable {
    let id: CoreMLModelID

    // This closed catalog retains the resource names and IDs stored in presets.
    var resourceName: String { id.rawValue }
    var backend: AIModelBackend { id.rawValue.contains("CoreAI") ? .coreAI : .coreML }
    var isRuntimeAvailable: Bool {
        guard backend == .coreAI else { return true }
        #if canImport(CoreAI)
        if #available(macOS 27.0, *) { return true }
        #endif
        return false
    }
    var displayName: String {
        switch id {
        case .coreAIlocX2FP32: return "Core AI x2 FP32 · 128 Local"
        case .coreAIlocX2FP16: return "Core AI x2 FP16 · 128 Local"
        case .coreAIlocX2W8: return "Core AI x2 W8 · 128 Local"
        case .coreAIlocX2P6: return "Core AI x2 P6 · 128 Local"
        case .coreAIproX2T128: return "Core AI x2 FP16 · 128 Pro"
        case .coreAIproX2T256: return "Core AI x2 FP16 · 256 Pro"
        case .coreAIproX2T512: return "Core AI x2 FP16 · 512 Pro"
        case .coreAIlocX4FP32: return "Core AI x4 FP32 · 128 Local"
        case .coreAIlocX4FP16: return "Core AI x4 FP16 · 128 Local"
        case .coreAIlocX4W8: return "Core AI x4 W8 · 128 Local"
        case .coreAIlocX4P6: return "Core AI x4 P6 · 128 Local"
        case .coreAIproX4T128: return "Core AI x4 FP16 · 128 Pro"
        case .coreAIproX4T256: return "Core AI x4 FP16 · 256 Pro"
        case .coreAIx2FP32: return "Core AI x2 FP32 · 128"
        case .coreAIx4FP32: return "Core AI x4 FP32 · 128"
        case .coreAIx8FP32: return "Core AI x8 FP32 · 64"
        case .coreAIx8W8: return "Core AI x8 W8 · 64"
        case .realESRGANx8Author: return "Real-ESRGAN x8 (experimental)"
        case .realESRGANx2FP16, .realESRGANx4FP16: return "Real-ESRGAN x\(Int(nativeScale)) (FP16)"
        default: return "Real-ESRGAN x\(Int(nativeScale))"
        }
    }
    var nativeScale: Double {
        switch id {
        case .realESRGANx2, .realESRGANx2FP16, .coreAIlocX2FP32, .coreAIlocX2FP16, .coreAIlocX2W8, .coreAIlocX2P6, .coreAIproX2T128, .coreAIproX2T256, .coreAIproX2T512, .coreAIx2FP32: return 2
        case .realESRGANx4, .realESRGANx4FP16, .coreAIlocX4FP32, .coreAIlocX4FP16, .coreAIlocX4W8, .coreAIlocX4P6, .coreAIproX4T128, .coreAIproX4T256, .coreAIx4FP32: return 4
        case .realESRGANx8, .realESRGANx8Author, .coreAIx8FP32, .coreAIx8W8: return 8
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
        models.filter { $0.isRuntimeAvailable && bundledURL(for: $0, bundle: bundle) != nil }
    }

    static func bundledURL(for spec: CoreMLModelSpec, bundle: Bundle = .main) -> URL? {
        for ext in spec.backend == .coreAI ? ["aimodel"] : ["mlmodelc", "mlpackage", "mlmodel"] {
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
