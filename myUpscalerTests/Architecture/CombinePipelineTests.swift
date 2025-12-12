import XCTest
import Combine
@testable import myUpscaler

class CombinePipelineTests: XCTestCase {
    
    var cancellables = Set<AnyCancellable>()
    
    @MainActor
    func testEditorStateThrottle() {
        let settings = UpscaleSettings()
        let state = EditorState(settings: settings)
        
        let expectation = XCTestExpectation(description: "Throttled update")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = false
        
        state.$thumbnailImage
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        Task { @MainActor in
            for i in 0..<100 {
                state.contrast = Double(i)
            }
        }
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    @MainActor
    func testMemoryLeaksInSubscriptions() {
        weak var weakState: EditorState?
        
        autoreleasepool {
            let settings = UpscaleSettings()
            let state = EditorState(settings: settings)
            weakState = state
            
            state.contrast = 1.5
        }
        
        XCTAssertNil(weakState, "EditorState should be deallocated after release")
    }
}

