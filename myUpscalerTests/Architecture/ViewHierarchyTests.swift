import XCTest
import SwiftUI
@testable import myUpscaler

class ViewHierarchyTests: XCTestCase {

    func testContentViewInitialization() {
        // Architecture Check: ContentView should init without crashing
        // and shouldn't require complex environment setup for basic init.
        let view = ContentView()
        XCTAssertNotNil(view)
    }
    
    func testSettingsViewDependencies() {
        // SettingsView usually requires an ObservableObject (UpscaleSettings)
        // We verify we can inject it.
        let settings = UpscaleSettings()
        let view = SettingsView(settings: settings)
        XCTAssertNotNil(view)
    }
}

