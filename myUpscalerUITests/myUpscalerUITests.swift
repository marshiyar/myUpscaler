//
//  myUpscalerUITests.swift
//  myUpscalerUITests
//
//  Created by Arshiya on 11/24/25.
//

import XCTest

final class myUpscalerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false

    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAppLaunchAndBasicNavigation() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Verify window exists
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        
    }
    
    @MainActor
    func testSettingsInteraction() throws {
        let app = XCUIApplication()
        app.launch()
        
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
