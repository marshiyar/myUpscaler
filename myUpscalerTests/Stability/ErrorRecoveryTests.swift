import XCTest
import Combine
@testable import myUpscaler

@MainActor class ErrorRecoveryTests: XCTestCase {
    
    func testEngineFailureRecovery() {
        let mockEngine = MockEngine()
        mockEngine.simulateError = Up60PEngineError.ffmpegNotFound
        
        let runner = UpscaleRunner(
            fileSystem: MockFileSystem(),
            engine: mockEngine,
            assetLoader: MockAssetLoader()
        )
        
        runner.inputPath = "/tmp/test.mp4"
        
        let expectation = XCTestExpectation(description: "Run finished with error")
        
        _ = runner.$isRunning
            .dropFirst()
            .filter { $0 == false }
            .sink { _ in

                 if runner.log.contains("FFmpeg executable not found") {
                     expectation.fulfill()
                 }
            }
        
        runner.run()
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(runner.isRunning)
    }
}

