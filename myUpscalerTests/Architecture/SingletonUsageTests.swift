import XCTest
@testable import myUpscaler

class SingletonUsageTests: XCTestCase {

    func testEngineSingletonUniqueness() {
        let s1 = Up60PEngine.shared
        let s2 = Up60PEngine.shared
        
        // Assert they are the exact same instance
        XCTAssertTrue(s1 === s2, "Up60PEngine.shared must return the same instance")
    }
    
    func testSingletonThreadSafety() {
        // Architecture Check: Concurrent access to the singleton shouldn't crash
        let group = DispatchGroup()
        for _ in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                let _ = Up60PEngine.shared
                group.leave()
            }
        }
        
        let result = group.wait(timeout: .now() + 2.0)
        XCTAssertEqual(result, .success, "Concurrent singleton access timed out or deadlocked")
    }
}

