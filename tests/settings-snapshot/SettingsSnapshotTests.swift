import Foundation
import XCTest

// This target compiles the production settings, snapshot, and model registry.
// Run's cloneSettings uses the snapshot/apply path exercised here.
final class SettingsSnapshotTests: XCTestCase {
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

    func testRenderSnapshotPreservesModelAndOutputScale() {
        for model in CoreMLModelID.allCases {
            for scale in [2.0, 4.0, 8.0] {
                let selected = UpscaleSettings()
                selected.scaler = "coreml"
                selected.coremlModelId = model
                selected.scaleFactor = scale
                let render = UpscaleSettings()
                UpscaleSettingsSnapshot(settings: selected).apply(to: render)
                XCTAssertEqual(render.coremlModelId, model)
                XCTAssertEqual(render.scaler, "coreml")
                XCTAssertEqual(render.scaleFactor, scale)
                XCTAssertEqual(CoreMLModelRegistry.model(for: render.coremlModelId).id, model)
            }
        }
    }

    func testPresetJSONRoundTripPreservesModelAndOutputScale() throws {
        for model in CoreMLModelID.allCases {
            for scale in [2.0, 4.0, 8.0] {
                let selected = UpscaleSettings()
                selected.scaler = "coreml"
                selected.coremlModelId = model
                selected.scaleFactor = scale
                let preset = Preset(name: "Model selection", snapshot: UpscaleSettingsSnapshot(settings: selected))
                let restored = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
                XCTAssertEqual(restored, preset)
                let applied = UpscaleSettings()
                restored.snapshot.apply(to: applied)
                XCTAssertEqual(applied.coremlModelId, model)
                XCTAssertEqual(applied.scaleFactor, scale)
            }
        }
    }

    func testLegacyPresetWithoutModelKeepsHistoricalDefault() throws {
        let selected = UpscaleSettings()
        selected.coremlModelId = .realESRGANx2
        selected.scaleFactor = 8
        let data = try JSONEncoder().encode(UpscaleSettingsSnapshot(settings: selected))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "coremlModelId")
        let migrated = try JSONDecoder().decode(UpscaleSettingsSnapshot.self,
                                                from: JSONSerialization.data(withJSONObject: legacy))
        let applied = UpscaleSettings()
        applied.coremlModelId = .realESRGANx2
        migrated.apply(to: applied)
        XCTAssertEqual(applied.coremlModelId, UpscaleSettings().coremlModelId)
        XCTAssertEqual(applied.scaleFactor, 8)
    }

    func testMinimalLegacySnapshotUsesDefaultModel() throws {
        let snapshot = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: Data("{}".utf8))
        XCTAssertEqual(snapshot.coremlModelId, UpscaleSettings().coremlModelId)
    }

    func testOutputScaleDoesNotChangeNativeModelScale() {
        let selected = UpscaleSettings()
        selected.coremlModelId = .realESRGANx4
        selected.scaleFactor = 8
        let render = UpscaleSettings()
        UpscaleSettingsSnapshot(settings: selected).apply(to: render)
        XCTAssertEqual(render.scaleFactor, 8)
        XCTAssertEqual(CoreMLModelRegistry.model(for: render.coremlModelId).nativeScale, 4)
    }

    func testCapturedModelDoesNotChangeWithLaterUISelection() {
        let selected = UpscaleSettings()
        selected.coremlModelId = .realESRGANx2
        let snapshot = UpscaleSettingsSnapshot(settings: selected)
        selected.coremlModelId = .realESRGANx4
        let render = UpscaleSettings()
        snapshot.apply(to: render)
        XCTAssertEqual(render.coremlModelId, .realESRGANx2)
        XCTAssertEqual(selected.coremlModelId, .realESRGANx4)
    }
}
