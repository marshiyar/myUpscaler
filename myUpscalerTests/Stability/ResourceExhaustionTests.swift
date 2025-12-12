import XCTest
@testable import myUpscaler

class ResourceExhaustionTests: XCTestCase {

    @MainActor
    func testFilterCacheLimit() {
        let state = EditorState()
        XCTAssertNotNil(state)
    }
}

