import XCTest
@testable import myUpscaler

@MainActor class BridgingStabilityTests: XCTestCase {
    func testExtremeParameterValues() async throws {

        let settings = UpscaleSettings()
        settings.denoiseStrength = "9999.99"
        settings.scaleFactor = 0.0001
        
        for _ in 0..<100 {
            let engine = Up60PEngine.shared
            _ = try? await engine.process(inputPath: "stub", settings: settings, outputDirectory: "stub")
        }
    }
}

