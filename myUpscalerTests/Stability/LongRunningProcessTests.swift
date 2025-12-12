import XCTest
@testable import myUpscaler

@MainActor class LongRunningProcessTests: XCTestCase {

    func testLongSimulation() async {
        
        let mockEngine = MockEngine()
        mockEngine.simulateDelay = 0.5
        mockEngine.simulateLogOutput = [
            "frame= 100 fps=30.0 time=00:00:03.33 progress=0.10",
            "frame= 200 fps=30.0 time=00:00:06.66 progress=0.20",
            "frame= 300 fps=30.0 time=00:00:10.00 progress=0.30"
        ]
        
        let runner = UpscaleRunner(
            fileSystem: MockFileSystem(),
            engine: mockEngine,
            assetLoader: MockAssetLoader()
        )
        
        runner.inputPath = "/tmp/long.mp4"
        runner.run()
        
     
        var seenProgress = false
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let progress = await MainActor.run { runner.progress }
            if progress > 0 {
                seenProgress = true
                break
            }
        }
        
        XCTAssertTrue(seenProgress, "Progress should update during long run")
    }
}

