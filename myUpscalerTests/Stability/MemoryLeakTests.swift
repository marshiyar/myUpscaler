import XCTest
@testable import myUpscaler

class MemoryLeakTests: XCTestCase {

    func testUpscaleRunnerLeak() {
        weak var weakRunner: UpscaleRunner?
        
        autoreleasepool {
            let runner = UpscaleRunner(
                fileSystem: MockFileSystem(),
                engine: MockEngine(),
                assetLoader: MockAssetLoader()
            )
            weakRunner = runner
            
            runner.inputPath = "/tmp/test.mp4"
            runner.run()
            runner.cancel()
        }
        
        XCTAssertNil(weakRunner, "UpscaleRunner leaked after run/cancel cycle")
    }
    
    @MainActor
    func testEditorStateLeak() {
        weak var weakState: EditorState?
        
        autoreleasepool {
            let settings = UpscaleSettings()
            let state = EditorState(settings: settings)
            weakState = state
            
            state.contrast = 1.2
        }
        
        XCTAssertNil(weakState, "EditorState leaked")
    }
}

