import Foundation

enum CoreMLModelID: String, CaseIterable, Codable, Hashable {
    case realESRGANx2 = "RealESRGAN_x2"
    case realESRGANx4 = "RealESRGAN_x4"
    case realESRGANx8 = "RealESRGAN_x8"
}
struct CoreMLModelSpec: Identifiable, Hashable {
    let id: CoreMLModelID
    let displayName: String
    let resourceName: String
    let nativeScale: Double

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
enum CoreMLModelRegistry {
    static let models: [CoreMLModelSpec] = [
        CoreMLModelSpec(id: .realESRGANx2, displayName: "Real-ESRGAN x2", resourceName: "RealESRGAN_x2", nativeScale: 2.0),
        CoreMLModelSpec(id: .realESRGANx4, displayName: "Real-ESRGAN x4", resourceName: "RealESRGAN_x4", nativeScale: 4.0),
        CoreMLModelSpec(id: .realESRGANx8, displayName: "Real-ESRGAN x8", resourceName: "RealESRGAN_x8", nativeScale: 8.0),
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
