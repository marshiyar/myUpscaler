import Foundation
import XCTest

// This target compiles the production settings, snapshot, and model registry.
// Run's cloneSettings uses the snapshot/apply path exercised here.
// XCTest's inherited initializers are nonisolated. Settings/preset checks opt
// into the main actor individually so this suite also supports Swift 6 defaults.
nonisolated final class SettingsSnapshotTests: XCTestCase {
    func testModelCatalogIsExhaustiveAndKeepsReleasedMetadata() {
        let expected: [(CoreMLModelID, String, String, Double)] = [
            (.realESRGANx2, "RealESRGAN_x2", "Real-ESRGAN x2", 2),
            (.realESRGANx4, "RealESRGAN_x4", "Real-ESRGAN x4", 4),
            (.realESRGANx8, "RealESRGAN_x8", "Real-ESRGAN x8", 8)
        ]
        let models = CoreMLModelRegistry.models
        XCTAssertEqual(models.map(\.id), CoreMLModelID.allCases)
        XCTAssertEqual(models.count, expected.count)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for (id, resource, displayName, scale) in expected {
            let model = CoreMLModelRegistry.model(for: id)
            XCTAssertEqual(model.id, id)
            XCTAssertEqual(model.resourceName, resource)
            XCTAssertEqual(model.displayName, displayName)
            XCTAssertEqual(model.nativeScale, scale)
            XCTAssertEqual(models.filter { $0.id == id }, [model])
        }
        XCTAssertEqual(CoreMLModelRegistry.defaultModel.id, .realESRGANx4)
    }

    func testModelIDsKeepTheirSavedJSONRepresentation() throws {
        let savedIDs = ["RealESRGAN_x2", "RealESRGAN_x4", "RealESRGAN_x8"]
        for (id, savedID) in zip(CoreMLModelID.allCases, savedIDs) {
            let data = try JSONEncoder().encode(id)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"\(savedID)\"")
            XCTAssertEqual(try JSONDecoder().decode(CoreMLModelID.self, from: data), id)
        }
        XCTAssertNil(CoreMLModelID(rawValue: "unregistered-model"))
        XCTAssertThrowsError(try JSONDecoder().decode(CoreMLModelID.self,
                                                      from: Data("\"unregistered-model\"".utf8)))
    }

    func testEmptyBundleDoesNotAdvertiseModelsOrInventADefaultResource() throws {
        let (directory, bundle) = try modelResourceFixture([])
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(CoreMLModelRegistry.bundledModels(in: bundle).isEmpty)
        for model in CoreMLModelRegistry.models {
            XCTAssertNil(CoreMLModelRegistry.bundledURL(for: model, bundle: bundle))
        }
        XCTAssertEqual(UpscalingModeSupport.scalers(bundledModelIDs: []), ["lanczos"])
    }

    func testResourceDiscoveryDoesNotSubstituteAnotherModelForMissingSelection() throws {
        // Empty fixture folders exercise resource lookup, not Core ML model validity.
        let (directory, bundle) = try modelResourceFixture(["RealESRGAN_x4.mlmodelc"])
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(CoreMLModelRegistry.bundledModels(in: bundle).map(\.id), [.realESRGANx4])
        for id in [CoreMLModelID.realESRGANx2, .realESRGANx8] {
            XCTAssertNil(CoreMLModelRegistry.bundledURL(for: CoreMLModelRegistry.model(for: id),
                                                       bundle: bundle))
        }
        XCTAssertEqual(CoreMLModelRegistry.bundledURL(for: CoreMLModelRegistry.defaultModel,
                                                     bundle: bundle)?.lastPathComponent,
                       "RealESRGAN_x4.mlmodelc")
    }

    func testResourceExtensionPreferenceRemainsCompiledThenPackageThenSource() throws {
        for extensions in [["mlmodel", "mlpackage", "mlmodelc"], ["mlmodel", "mlpackage"], ["mlmodel"]] {
            let (directory, bundle) = try modelResourceFixture(extensions.map { "RealESRGAN_x4.\($0)" })
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = CoreMLModelRegistry.bundledURL(for: CoreMLModelRegistry.defaultModel, bundle: bundle)
            XCTAssertEqual(url?.pathExtension, extensions.last)
        }
    }

    func testEveryModelEnforcesTheCompleteTensorShapeContract() {
        for model in CoreMLModelRegistry.models {
            let tile = 17
            let outputTile = tile * Int(model.nativeScale)
            let input = [1, 3, tile, tile]
            let output = [1, 3, outputTile, outputTile]
            XCTAssertTrue(model.supportsTensorShapes(input: input, output: output))
            let malformedInputs = [
                [], [3, tile, tile], [1, 3, tile, tile, 1], [0, 3, tile, tile], [2, 3, tile, tile],
                [1, 12, tile, tile], [1, 3, 16, 16], [1, 3, 0, 0], [1, 3, -tile, -tile], [1, 3, tile, tile + 1]
            ]
            for malformed in malformedInputs {
                XCTAssertFalse(model.supportsTensorShapes(input: malformed, output: output),
                               "\(model.id): input \(malformed)")
            }
            let malformedOutputs = [
                [], [3, outputTile, outputTile], [1, 3, outputTile, outputTile, 1],
                [0, 3, outputTile, outputTile], [2, 3, outputTile, outputTile], [1, 4, outputTile, outputTile],
                [1, 3, 0, 0], [1, 3, -outputTile, -outputTile], [1, 3, outputTile, outputTile + 1], input
            ]
            for malformed in malformedOutputs {
                XCTAssertFalse(model.supportsTensorShapes(input: input, output: malformed),
                               "\(model.id): output \(malformed)")
            }
        }
    }

    @MainActor func testSingleDeringSwitchAndLegacyPresetEffectiveState() async {
        let settings = UpscaleSettings()
        settings.secondary.useDering = true
        let saved = UpscaleSettingsSnapshot(settings: settings)
        let restored = UpscaleSettings()
        saved.apply(to: restored)
        XCTAssertTrue(restored.secondary.useDering)
        var legacy = saved
        legacy.deringActive2 = false
        legacy.apply(to: restored)
        XCTAssertFalse(restored.secondary.useDering, "Preserve the effective off state of a legacy two-switch preset")
    }

    func testUpdatedModelTileSizesAreSupported() {
        let x2 = CoreMLModelRegistry.model(for: .realESRGANx2)
        let x4 = CoreMLModelRegistry.model(for: .realESRGANx4)
        let x8 = CoreMLModelRegistry.model(for: .realESRGANx8)
        XCTAssertTrue(x2.supportsTensorShapes(input: [1, 3, 128, 128], output: [1, 3, 256, 256]))
        XCTAssertTrue(x4.supportsTensorShapes(input: [1, 3, 128, 128], output: [1, 3, 512, 512]))
        XCTAssertTrue(x8.supportsTensorShapes(input: [1, 3, 96, 96], output: [1, 3, 768, 768]))
        // Tiling currently uses a single stride for both axes.
        XCTAssertFalse(x4.supportsTensorShapes(input: [1, 3, 64, 128], output: [1, 3, 256, 512]))
    }

    func testModelTensorContractRejectsIncompatibleReleasedX2() {
        let x2 = CoreMLModelRegistry.model(for: .realESRGANx2)
        let x4 = CoreMLModelRegistry.model(for: .realESRGANx4)
        let x8 = CoreMLModelRegistry.model(for: .realESRGANx8)
        XCTAssertFalse(x2.supportsTensorShapes(input: [1, 12, 256, 256], output: [1, 3, 512, 512]))
        XCTAssertTrue(x4.supportsTensorShapes(input: [1, 3, 256, 256], output: [1, 3, 1024, 1024]))
        XCTAssertTrue(x8.supportsTensorShapes(input: [1, 3, 64, 64], output: [1, 3, 512, 512]))
        XCTAssertFalse(x4.supportsTensorShapes(input: [3, 256, 256], output: [1, 3, 1024, 1024]))
        XCTAssertFalse(x4.supportsTensorShapes(input: [2, 3, 256, 256], output: [1, 3, 1024, 1024]))
        XCTAssertFalse(x4.supportsTensorShapes(input: [1, 3, 256, 256], output: [1, 3, 512, 512]))
        XCTAssertFalse(x8.supportsTensorShapes(input: [1, 3, 16, 64], output: [1, 3, 128, 512]))
    }

    @MainActor func testRenderSnapshotPreservesModelAndOutputScale() async {
        for model in CoreMLModelID.allCases {
            for scale in [2.0, 4.0, 8.0] {
                let selected = UpscaleSettings()
                selected.upscaling.scaler = "coreml"
                selected.upscaling.coremlModelId = model
                selected.video.scaleFactor = scale
                let render = UpscaleSettings()
                UpscaleSettingsSnapshot(settings: selected).apply(to: render)
                XCTAssertEqual(render.upscaling.coremlModelId, model)
                XCTAssertEqual(render.upscaling.scaler, "coreml")
                XCTAssertEqual(render.video.scaleFactor, scale)
                XCTAssertEqual(CoreMLModelRegistry.model(for: render.upscaling.coremlModelId).id, model)
            }
        }
    }

    @MainActor func testPresetJSONRoundTripPreservesModelAndOutputScale() async throws {
        for model in CoreMLModelID.allCases {
            for scale in [2.0, 4.0, 8.0] {
                let selected = UpscaleSettings()
                selected.upscaling.scaler = "coreml"
                selected.upscaling.coremlModelId = model
                selected.video.scaleFactor = scale
                let preset = Preset(name: "Model selection", snapshot: UpscaleSettingsSnapshot(settings: selected))
                let restored = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
                XCTAssertEqual(restored, preset)
                let applied = UpscaleSettings()
                restored.snapshot.apply(to: applied)
                XCTAssertEqual(applied.upscaling.coremlModelId, model)
                XCTAssertEqual(applied.video.scaleFactor, scale)
            }
        }
    }

    @MainActor func testLegacyPresetWithoutModelKeepsHistoricalDefault() async throws {
        let selected = UpscaleSettings()
        selected.upscaling.coremlModelId = .realESRGANx2
        selected.video.scaleFactor = 8
        let data = try JSONEncoder().encode(UpscaleSettingsSnapshot(settings: selected))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "coremlModelId")
        let migrated = try JSONDecoder().decode(UpscaleSettingsSnapshot.self,
                                                from: JSONSerialization.data(withJSONObject: legacy))
        let applied = UpscaleSettings()
        applied.upscaling.coremlModelId = .realESRGANx2
        migrated.apply(to: applied)
        XCTAssertEqual(applied.upscaling.coremlModelId, UpscaleSettings().upscaling.coremlModelId)
        XCTAssertEqual(applied.video.scaleFactor, 8)
    }

    @MainActor func testMinimalLegacySnapshotUsesDefaultModel() async throws {
        let snapshot = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: Data("{}".utf8))
        XCTAssertEqual(snapshot.coremlModelId, UpscaleSettings().upscaling.coremlModelId)
    }

    @MainActor func testOutputScaleDoesNotChangeNativeModelScale() async {
        let selected = UpscaleSettings()
        selected.upscaling.coremlModelId = .realESRGANx4
        selected.video.scaleFactor = 8
        let render = UpscaleSettings()
        UpscaleSettingsSnapshot(settings: selected).apply(to: render)
        XCTAssertEqual(render.video.scaleFactor, 8)
        XCTAssertEqual(CoreMLModelRegistry.model(for: render.upscaling.coremlModelId).nativeScale, 4)
    }

    @MainActor func testCapturedModelDoesNotChangeWithLaterUISelection() async {
        let selected = UpscaleSettings()
        selected.upscaling.coremlModelId = .realESRGANx2
        let snapshot = UpscaleSettingsSnapshot(settings: selected)
        selected.upscaling.coremlModelId = .realESRGANx4
        let render = UpscaleSettings()
        snapshot.apply(to: render)
        XCTAssertEqual(render.upscaling.coremlModelId, .realESRGANx2)
        XCTAssertEqual(selected.upscaling.coremlModelId, .realESRGANx4)
    }

    private func modelResourceFixture(_ names: [String]) throws -> (URL, Bundle) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundleURL = directory.appendingPathComponent("Models.bundle")
        let contents = bundleURL.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        do {
            let info = ["CFBundleIdentifier": "local.ModelCatalog.\(UUID().uuidString)",
                        "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            for name in names {
                let url = resources.appendingPathComponent(name)
                if url.pathExtension == "mlmodel" {
                    try Data().write(to: url)
                } else {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                }
            }
            return (directory, try XCTUnwrap(Bundle(url: bundleURL)))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
