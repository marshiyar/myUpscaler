import Foundation
import CoreML

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "PackagedModels", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    guard CommandLine.arguments.count == 2,
          let bundle = Bundle(path: CommandLine.arguments[1]) else {
        throw NSError(domain: "PackagedModels", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Supply the built app path."])
    }
    let expected: [CoreMLModelID] = [.realESRGANx4, .realESRGANx8]
    let available = CoreMLModelRegistry.models.filter {
        CoreMLModelRegistry.bundledURL(for: $0, bundle: bundle) != nil
    }.map(\.id)
    try require(available == expected, "Unexpected bundled models: \(available)")
    for id in expected {
        let spec = CoreMLModelRegistry.model(for: id)
        let url = CoreMLModelRegistry.bundledURL(for: spec, bundle: bundle)!
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: url, configuration: config)
        let description = model.modelDescription
        try require(description.inputDescriptionsByName.count == 1
                    && description.outputDescriptionsByName.count == 1, "Expected one input/output")
        guard let inputName = description.inputDescriptionsByName.keys.first,
              let outputName = description.outputDescriptionsByName.keys.first,
              let input = description.inputDescriptionsByName[inputName]?.multiArrayConstraint,
              let output = description.outputDescriptionsByName[outputName]?.multiArrayConstraint else {
            throw NSError(domain: "PackagedModels", code: 1)
        }
        try require(input.dataType == .float32 && output.dataType == .float32,
                    "Expected Float32 input/output")
        try require(spec.supportsTensorShapes(input: input.shape.map { $0.intValue },
                                             output: output.shape.map { $0.intValue }),
                    "Incompatible tensor shapes for \(id)")
        let tensor = try MLMultiArray(shape: input.shape, dataType: .float32)
        // A nonzero RGB tile catches prediction failures that model loading alone misses.
        let source = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        for index in 0..<tensor.count { source[index] = Float(index % 256) / 255 }
        let features = try MLDictionaryFeatureProvider(dictionary: [inputName: tensor])
        let prediction = try model.prediction(from: features)
        guard let result = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw NSError(domain: "PackagedModels", code: 1)
        }
        try require(result.shape == output.shape && result.dataType == .float32,
                    "Unexpected prediction shape or data type")
        // The engine reads planar contiguous output memory; verify that assumption too.
        let height = result.shape[2].intValue, width = result.shape[3].intValue
        try require(result.strides[1].intValue == height * width
                    && result.strides[2].intValue == width && result.strides[3].intValue == 1,
                    "Prediction output is not contiguous RGB")
        let values = result.dataPointer.assumingMemoryBound(to: Float.self)
        var minimum = Float.infinity, maximum = -Float.infinity
        for index in 0..<result.count {
            try require(values[index].isFinite, "Prediction contains a nonfinite value")
            minimum = min(minimum, values[index]); maximum = max(maximum, values[index])
        }
        try require(maximum > minimum, "Prediction unexpectedly produced a constant image")
        print("\(id.rawValue): loaded from app and predicted \(input.shape) → \(result.shape), all values finite.")
    }
    print("::notice::Packaged CoreML: x4 and x8 loaded and predicted successfully; incompatible x2 absent.")
} catch {
    fputs("Packaged CoreML verification failed: \(error)\n", stderr)
    exit(1)
}
