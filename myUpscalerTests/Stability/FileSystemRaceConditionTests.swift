import XCTest
@testable import myUpscaler

class FileSystemRaceConditionTests: XCTestCase {
    
    func testOutputAppearanceRace() {
        let mockFS = MockFileSystem()
        let runner = UpscaleRunner(fileSystem: mockFS, engine: MockEngine(), assetLoader: MockAssetLoader())
        
        runner.inputPath = "/tmp/race.mp4"
        mockFS.mockFile(atPath: "/tmp/race_[restored].mp4", size: 100)
        
        runner.checkForCompletedOutput()
        
        XCTAssertEqual(runner.completedOutputPath, "/tmp/race_[restored].mp4")
    }
}

