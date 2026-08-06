//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


@MainActor
final class FHIRDisplayTests: XCTestCase, Sendable {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skipOnboarding", "--mode", "test"]
        app.launch()
    }
    
    
    func testFHIRResourcesView() throws {
        let app = XCUIApplication()
        
        app.swipeUp()

        let mockResource = app.staticTexts["Mock Resource"]
        XCTAssertTrue(mockResource.waitForExistence(timeout: 5), "The 'Mock Resource' does not exist.")

        mockResource.tap()
        XCTAssertTrue(
            app.navigationBars["Mock Resource"].waitForExistence(timeout: 5),
            "The resource detail screen did not appear."
        )
    }
}
