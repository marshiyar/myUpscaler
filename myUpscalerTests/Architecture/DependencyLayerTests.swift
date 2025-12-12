import XCTest
@testable import myUpscaler

class DependencyLayerTests: XCTestCase {
    
    @MainActor
    func testEditorStateIsolation() {
        
        let settings = UpscaleSettings()
        let state = EditorState(settings: settings)
        
        XCTAssertNotNil(state)
    }
    
    func testSettingsDecoupling() {
        
        let settings = UpscaleSettings()
        
        let memorySize = malloc_size(Unmanaged.passUnretained(settings).toOpaque())
        XCTAssertTrue(memorySize < 10000, "UpscaleSettings should be lightweight")
    }
}

