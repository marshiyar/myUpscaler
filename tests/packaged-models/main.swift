import Foundation
import CoreML

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "PackagedModels", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--list-resources" {
        CoreMLModelRegistry.models.forEach { print($0.resourceName) }
        exit(0)
    }
    guard (2...3).contains(CommandLine.arguments.count),
          CommandLine.arguments.count != 3 || CommandLine.arguments[2] == "--predict" else {
        throw NSError(domain: "PackagedModels", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Supply a models directory or built app path, optionally --predict."])
    }
    let path = URL(fileURLWithPath: CommandLine.arguments[1])
    let directory: URL
    if path.pathExtension == "app" {
        guard let resources = Bundle(path: path.path)?.resourceURL else {
            throw NSError(domain: "PackagedModels", code: 1)
        }
        directory = resources
    } else {
        directory = path
    }
    let models = CoreMLModelRegistry.models.filter {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.resourceName + ".mlmodelc").path)
    }
    try require(!models.isEmpty, "No registered compiled models found at \(directory.path)")
    let predict = CommandLine.arguments.last == "--predict"
    for spec in models {
        let id = spec.id
        let url = directory.appendingPathComponent(spec.resourceName + ".mlmodelc")
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
        if !predict {
            print("\(id.rawValue): CoreML loaded compatible tensors \(input.shape) → \(output.shape).")
            continue
        }
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
        print("\(id.rawValue): loaded and predicted \(input.shape) → \(result.shape), all values finite.")
    }
    if predict {
        print("::notice::CoreML predictions passed for: \(models.map { $0.resourceName }.joined(separator: ", ")).")
    }
} catch {
    fputs("Packaged CoreML verification failed: \(error)\n", stderr)
    exit(1)
}
