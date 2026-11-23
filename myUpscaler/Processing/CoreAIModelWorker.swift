#if canImport(CoreAI)
import CoreAI
import CoreML
import CoreVideo
import Foundation

/// Native Core AI assets stay on one worker actor. Float32 video tensors are
/// converted to the asset's actual floating boundary; weights are never relabeled.
@available(macOS 27.0, *)
actor CoreAIModelWorker {
    static let shared = CoreAIModelWorker()
    private var model: AIModel?
    private var function: InferenceFunction?
    private var specID: CoreMLModelID?
    private var layout: ModelTensorLayout?
    private var inputIsHalf = false
    private var outputIsHalf = false
    private var busy = false

    func clear() throws {
        guard !busy else { throw ProcessingControl.Failure.alreadyRunning }
        function = nil; model = nil; specID = nil; layout = nil
    }

    func prepare(spec: CoreMLModelSpec, url: URL) async throws -> ModelTensorLayout {
        guard !busy else { throw ProcessingControl.Failure.alreadyRunning }
        if specID == spec.id, let layout { return layout }
        try clear()
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let loaded = try await AIModel(contentsOf: url, options: .default)
        guard loaded.functionNames.count == 1, let name = loaded.functionNames.first,
              let fn = try loaded.loadFunction(named: name),
              fn.descriptor.inputNames.count == 1, fn.descriptor.outputNames.count == 1,
              let inputName = fn.descriptor.inputNames.first,
              let outputName = fn.descriptor.outputNames.first,
              let input = fn.descriptor.inputDescriptor(of: inputName),
              let output = fn.descriptor.outputDescriptor(of: outputName),
              case .ndArray(let inputDescriptor) = input,
              case .ndArray(let outputDescriptor) = output,
              [.float16, .float32].contains(inputDescriptor.scalarType),
              [.float16, .float32].contains(outputDescriptor.scalarType),
              spec.supportsTensorShapes(input: inputDescriptor.shape, output: outputDescriptor.shape) else {
            throw ModelError.invalidModel
        }
        try Task.checkCancellation()
        let result = ModelTensorLayout(inputName: inputName, outputName: outputName,
            inputShape: inputDescriptor.shape, outputShape: outputDescriptor.shape,
            float32Input: inputDescriptor.scalarType == .float32,
            float32Output: outputDescriptor.scalarType == .float32)
        inputIsHalf = inputDescriptor.scalarType == .float16
        outputIsHalf = outputDescriptor.scalarType == .float16
        model = loaded; function = fn; specID = spec.id; layout = result
        return result
    }

    func prediction(input: sending MLMultiArray, id: CoreMLModelID,
                    width: Int, height: Int) async throws -> sending CVPixelBuffer {
        guard !busy else { throw ProcessingControl.Failure.alreadyRunning }
        guard specID == id, let function, let layout,
              input.dataType == .float32, input.shape.map(\.intValue) == layout.inputShape,
              layout.outputShape == [1, 3, height, width] else { throw ModelError.invalidModel }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        var nativeInput = NDArray(shape: layout.inputShape, scalarType: inputIsHalf ? .float16 : .float32)
        let values = input.dataPointer.assumingMemoryBound(to: Float.self)
        let strides = input.strides.map(\.intValue)
        let side = layout.inputShape[2]
        if inputIsHalf {
            let view = nativeInput.mutableView(as: Float16.self)
            guard var elements = view.contiguousElements else { throw ModelError.invalidModel }
            for c in 0..<3 { for y in 0..<side { for x in 0..<side {
                let value = values[c * strides[1] + y * strides[2] + x * strides[3]]
                guard value.isFinite, Float16(value).isFinite else { throw ModelError.invalidModel }
                elements[c * side * side + y * side + x] = Float16(value)
            } } }
        } else {
            let view = nativeInput.mutableView(as: Float.self)
            guard var elements = view.contiguousElements else { throw ModelError.invalidModel }
            for c in 0..<3 { for y in 0..<side { for x in 0..<side {
                let value = values[c * strides[1] + y * strides[2] + x * strides[3]]
                guard value.isFinite else { throw ModelError.invalidModel }
                elements[c * side * side + y * side + x] = value
            } } }
        }
        var outputs = try await function.run(inputs: [layout.inputName: nativeInput])
        try Task.checkCancellation()
        guard let result = outputs.remove(layout.outputName), let array = result.ndArray,
              array.shape == layout.outputShape,
              array.scalarType == (outputIsHalf ? .float16 : .float32) else { throw ModelError.invalidModel }
        let tensor = try MLMultiArray(shape: layout.outputShape.map { NSNumber(value: $0) }, dataType: .float32)
        let target = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        if outputIsHalf {
            let view = array.view(as: Float16.self)
            if let elements = view.contiguousElements {
                for index in 0..<tensor.count {
                    let value = Float(elements[index])
                    guard value.isFinite else { throw ModelError.invalidModel }
                    target[index] = value
                }
            } else {
            for c in 0..<3 { for y in 0..<height { for x in 0..<width {
                let value = Float(view[scalarAt: [0, c, y, x]])
                guard value.isFinite else { throw ModelError.invalidModel }
                target[c * width * height + y * width + x] = value
            } } }
            }
        } else {
            let view = array.view(as: Float.self)
            if let elements = view.contiguousElements {
                for index in 0..<tensor.count {
                    let value = Float(elements[index])
                    guard value.isFinite else { throw ModelError.invalidModel }
                    target[index] = value
                }
            } else {
            for c in 0..<3 { for y in 0..<height { for x in 0..<width {
                let value = view[scalarAt: [0, c, y, x]]
                guard value.isFinite else { throw ModelError.invalidModel }
                target[c * width * height + y * width + x] = value
            } } }
            }
        }
        return try CoreMLProcessingJob.makePixelBuffer(tensor: tensor, width: width, height: height)
    }
}
#endif
