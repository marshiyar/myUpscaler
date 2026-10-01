import Foundation

enum CoreMLModelID: String, CaseIterable, Codable, Hashable {
    case realESRGANx2 = "RealESRGAN_x2"
    case realESRGANx4 = "RealESRGAN_x4"
}
struct CoreMLModelSpec: Identifiable, Hashable {
    let id: CoreMLModelID
    let displayName: String
    let resourceName: String
    let nativeScale: Double
}
enum CoreMLModelRegistry {
    static let models: [CoreMLModelSpec] = [
        CoreMLModelSpec(id: .realESRGANx2, displayName: "Real-ESRGAN x2", resourceName: "RealESRGAN_x2", nativeScale: 2.0),
        CoreMLModelSpec(id: .realESRGANx4, displayName: "Real-ESRGAN x4", resourceName: "RealESRGAN_x4", nativeScale: 4.0),
    ]
    
    static var defaultModel: CoreMLModelSpec { models.first(where: { $0.id == .realESRGANx4 }) ?? models[0] }

    static var bundledModels: [CoreMLModelSpec] {
        models.filter { bundledURL(for: $0) != nil }
    }

    static func bundledURL(for spec: CoreMLModelSpec, bundle: Bundle = .main) -> URL? {
        for ext in ["mlmodelc", "mlpackage", "mlmodel"] {
            if let url = bundle.url(forResource: spec.resourceName, withExtension: ext),
               FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        return nil
    }
    
    static func model(for id: CoreMLModelID) -> CoreMLModelSpec {
        models.first(where: { $0.id == id }) ?? defaultModel
    }
}

