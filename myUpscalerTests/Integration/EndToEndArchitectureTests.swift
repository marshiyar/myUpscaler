import XCTest
@testable import myUpscaler

class EndToEndArchitectureTests: XCTestCase {

    @MainActor
    func testComponentWiring() {
        
        let settings = UpscaleSettings()
        let editor = EditorState(settings: settings)
        let runner = UpscaleRunner(engine: MockEngine())
        
        runner.settings = settings

        runner.settings.preset = "LoadedPreset"
        
        editor.syncFromSettings(runner.settings)
        let boundEditor = EditorState(settings: settings)
        settings.eqContrast = "2.0"
        
        let exp = expectation(description: "Sync")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if boundEditor.contrast == 2.0 {
                exp.fulfill()
            }
        }
        
        wait(for: [exp], timeout: 1.0)
    }
}

