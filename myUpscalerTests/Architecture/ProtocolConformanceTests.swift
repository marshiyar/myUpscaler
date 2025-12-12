import XCTest
@testable import myUpscaler

class ProtocolConformanceTests: XCTestCase {

    func testUpscaleRunnerDependencies() {
        // Architecture Check: UpscaleRunner should rely on protocols, not concrete implementations
        // This ensures we can swap out the engine or filesystem for testing.
        
        // We verify this by ensuring we can initialize it with Mocks.
        let mockFS = MockFileSystem()
        let mockEngine = MockEngine()
        let mockLoader = MockAssetLoader()
        
        let runner = UpscaleRunner(fileSystem: mockFS, engine: mockEngine, assetLoader: mockLoader)
        
        XCTAssertNotNil(runner, "UpscaleRunner failed to initialize with protocol mocks")
    }

    func testEngineProtocolConformance() {
        // Verify Up60PEngine conforms to EngineProtocol
        // This is a compile-time check mostly, but runtime verification helps reflection-based tools.
        let engine: Any = Up60PEngine.shared
        XCTAssertTrue(engine is EngineProtocol, "Up60PEngine must conform to EngineProtocol")
    }
    
    func testFileSystemProtocolConformance() {
        // Verify FileManager conforms (via extension in actual app usually, or wrapper)
        // Since FileManager.default is passed as default arg, it should conform.
        let fm: Any = FileManager.default
        XCTAssertTrue(fm is FileSystemProtocol, "FileManager must conform to FileSystemProtocol")
    }
}

