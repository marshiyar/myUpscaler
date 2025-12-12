import XCTest
@testable import myUpscaler

class ImmutabilityTests: XCTestCase {

    func testUpscaleSettingsReferenceSemantics() {
        let settingsA = UpscaleSettings()
        settingsA.preset = "TestPreset"
        
        let settingsB = settingsA
        settingsB.preset = "Changed"
        XCTAssertEqual(settingsA.preset, "Changed")
    }
    
    func testSettingsCopying() {
        
        let original = UpscaleSettings()
        original.crf = 10
        original.useHEVC = true
        let copy = UpscaleSettings()
        copy.crf = original.crf
        copy.useHEVC = original.useHEVC
        
        XCTAssertEqual(copy.crf, 10)
        XCTAssertEqual(copy.useHEVC, true)
        
        // Mutate original
        original.crf = 20
        
        XCTAssertEqual(copy.crf, 10, "Manual copy should remain independent")
    }
}

