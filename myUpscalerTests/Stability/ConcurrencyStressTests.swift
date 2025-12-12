import XCTest
@testable import myUpscaler

@MainActor class ConcurrencyStressTests: XCTestCase {

    func testUpscaleRunnerStateStress() async {
        let runner = UpscaleRunner(
            fileSystem: MockFileSystem(),
            engine: MockEngine(),
            assetLoader: MockAssetLoader()
        )
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let _ = await MainActor.run {
                        runner.progress = Double(i) / 100.0
                        runner.log.append("Log \(i)\n")
                    }
                }
            }
        }
        let count = await MainActor.run { runner.log.count }
        XCTAssertTrue(count > 0)
    }
}

