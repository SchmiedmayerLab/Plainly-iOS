//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


@MainActor
final class SyntheticRecordsTests: XCTestCase, Sendable {
    /// Test mode substitutes the bundled synthetic patients for health records, so the study can be
    /// exercised without granting HealthKit access.
    func testTestModeLoadsSyntheticRecords() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skipOnboarding", "--mode", "test", "--disableFirebase", "--disableHealthRecords"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Welcome"].waitForExistence(timeout: 10),
            "The study home screen did not appear."
        )
        XCTAssertTrue(
            app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Health records since:'")).firstMatch
                .waitForExistence(timeout: 15),
            "The synthetic health records were not loaded."
        )
    }
}
