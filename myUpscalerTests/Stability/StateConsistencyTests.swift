import XCTest
@testable import myUpscaler

class StateConsistencyTests: XCTestCase {

    func testSettingsConsistency() {
        let settings = UpscaleSettings()
        settings.useHEVC = true
        settings.preset = "fast"
        
        
        settings.x265AqMode = "3"
        XCTAssertTrue(settings.x265Params.contains("aq-mode=3"))
        
        settings.x265AqMode = ""
        XCTAssertFalse(settings.x265Params.contains("aq-mode="))
    }
}

