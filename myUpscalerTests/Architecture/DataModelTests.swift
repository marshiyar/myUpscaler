import XCTest
@testable import myUpscaler

class DataModelTests: XCTestCase {

    func testUpscaleSettingsDefaults() {
        let settings = UpscaleSettings()
        
        XCTAssertEqual(settings.fps, "60")
        XCTAssertEqual(settings.scaleFactor, 2.0)
        XCTAssertFalse(settings.aiModelPath.contains(".."), "Default paths must be safe")
    }
    func testPresetParsing() {
        let presetContent = """
        codec="hevc"
        crf="20"
        scale_factor="4.0"
        """
        
        let codec = parseValue(from: presetContent, key: "codec")
        XCTAssertEqual(codec, "hevc")
        
        let crf = parseValue(from: presetContent, key: "crf")
        XCTAssertEqual(crf, "20")
    }
    
    private func parseValue(from content: String, key: String) -> String? {
        let regex = try? NSRegularExpression(pattern: "\(key)=\"([^\"]+)\"")
        let nsString = content as NSString
        guard let match = regex?.firstMatch(in: content, range: NSRange(location: 0, length: nsString.length)) else { return nil }
        return nsString.substring(with: match.range(at: 1))
    }
}

