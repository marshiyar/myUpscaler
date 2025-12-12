import XCTest
@testable import myUpscaler

@MainActor class BridgingStabilityTests: XCTestCase {
    func testExtremeParameterValues() async throws {

        // Different from fuzzing (garbage) - these are "valid" doubles that might cause overflow in C math.
        
        let settings = UpscaleSettings()
        settings.denoiseStrength = "9999.99" // Way above normal
        settings.scaleFactor = 0.0001 // Tiny
        
        // Mock bridge again to see what happens
        // Reuse logic from SecurityTests if possible, or just standard run
        // We just want to ensure no crash in the Swift->C setup.
        for _ in 0..<100 {
            let engine = Up60PEngine.shared
            _ = try? await engine.process(inputPath: "stub", settings: settings, outputDirectory: "stub")
        }
    }
}

