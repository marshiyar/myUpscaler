import Foundation
import CoreML
import CoreVideo

nonisolated struct ModelTensorLayout: Sendable {
    let inputName: String
    let outputName: String
    let inputShape: [Int]
    let outputShape: [Int]
    let float32Input: Bool
    let float32Output: Bool
}

actor ModelManager {
    static let shared = ModelManager()
    private let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }
    private var cachedModel: (CoreMLModelID, MLModel)?
    private let predictionOptions = MLPredictionOptions()

    private func cached(for id: CoreMLModelID) -> MLModel? {
        return cachedModel?.0 == id ? cachedModel?.1 : nil
    }

    private func remember(_ model: MLModel, for id: CoreMLModelID) {
        // Bound retained resources to one model, even after switching models.
        cachedModel = (id, model)
    }

    private func sourceModelURL(resourceName: String) -> URL? {
        if let url = bundle.url(forResource: resourceName, withExtension: "mlpackage") { return url }
        if let url = bundle.url(forResource: resourceName, withExtension: "mlmodel") { return url }
        return nil
    }

    func prepareModel(spec: CoreMLModelSpec) async throws -> ModelTensorLayout {
        if spec.backend == .coreAI {
            #if canImport(CoreAI)
            if #available(macOS 27.0, *) {
                guard let url = CoreMLModelRegistry.bundledURL(for: spec, bundle: bundle) else { throw ModelError.modelNotFound }
                cachedModel = nil
                return try await CoreAIModelWorker.shared.prepare(spec: spec, url: url)
            }
            #endif
            throw ModelError.invalidModel
        }
        #if canImport(CoreAI)
        if #available(macOS 27.0, *) { try await CoreAIModelWorker.shared.clear() }
        #endif
        let model = try await loadModel(spec: spec)
        let description = model.modelDescription
        guard description.inputDescriptionsByName.count == 1,
              description.outputDescriptionsByName.count == 1,
              let inputName = description.inputDescriptionsByName.keys.first,
              let outputName = description.outputDescriptionsByName.keys.first,
              let input = description.inputDescriptionsByName[inputName]?.multiArrayConstraint,
              let output = description.outputDescriptionsByName[outputName]?.multiArrayConstraint else {
            throw ModelError.invalidModel
        }
        return ModelTensorLayout(inputName: inputName, outputName: outputName,
            inputShape: input.shape.map { $0.intValue }, outputShape: output.shape.map { $0.intValue },
            float32Input: input.dataType == .float32, float32Output: output.dataType == .float32)
    }

    // The model never leaves this actor. Fresh tensors transfer ownership once;
    // synchronous prediction executes on this worker actor, never the UI actor.
    func prediction(input: sending MLMultiArray, specID: CoreMLModelID,
                    inputName: String, outputName: String, width: Int, height: Int) async throws -> sending CVPixelBuffer {
        if CoreMLModelRegistry.model(for: specID).backend == .coreAI {
            #if canImport(CoreAI)
            if #available(macOS 27.0, *) {
                return try await CoreAIModelWorker.shared.prediction(input: input, id: specID, width: width, height: height)
            }
            #endif
            throw ModelError.invalidModel
        }
        return try coreMLPrediction(input: input, specID: specID, inputName: inputName,
                                    outputName: outputName, width: width, height: height)
    }

    private func coreMLPrediction(input: sending MLMultiArray, specID: CoreMLModelID,
                                  inputName: String, outputName: String, width: Int, height: Int) throws -> sending CVPixelBuffer {
        guard let model = cached(for: specID) else { throw ModelError.invalidModel }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: input])
        let result = try model.prediction(from: provider, options: predictionOptions)
        guard let tensor = result.featureValue(for: outputName)?.multiArrayValue else { throw ModelError.invalidModel }
        return try CoreMLProcessingJob.makePixelBuffer(tensor: tensor, width: width, height: height)
    }

    private func loadModel(spec: CoreMLModelSpec, progressHandler: ((Double) -> Void)? = nil) async throws -> MLModel {
        if let model = cached(for: spec.id) {
            progressHandler?(1.0)
            return model
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        config.allowLowPrecisionAccumulationOnGPU = true

        guard let modelURL = CoreMLModelRegistry.bundledURL(for: spec, bundle: bundle) else {
            throw ModelError.modelNotFound
        }
        let sourceURL = sourceModelURL(resourceName: spec.resourceName)

        progressHandler?(0.5)

        do {
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            remember(model, for: spec.id)
            progressHandler?(1.0)
            return model
        } catch {
            print("DEBUG: Failed to load model with .all compute units. Retry compiling...")

            if let src = sourceURL ?? (modelURL.pathExtension != "mlmodelc" ? modelURL : nil) {
                let compiledURL = try await MLModel.compileModel(at: src)
                let compiledModel = try MLModel(contentsOf: compiledURL, configuration: config)
                remember(compiledModel, for: spec.id)
                progressHandler?(1.0)
                return compiledModel
            }

            config.computeUnits = .cpuOnly
            config.allowLowPrecisionAccumulationOnGPU = false
            if let model = try? MLModel(contentsOf: modelURL, configuration: config) {
                remember(model, for: spec.id)
                progressHandler?(1.0)
                return model
            }
            throw ModelError.invalidModel
        }
    }
}
