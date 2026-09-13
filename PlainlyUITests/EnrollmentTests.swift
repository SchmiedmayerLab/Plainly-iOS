//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// A simulator has no camera to scan an enrollment code with, so a debug build lists the studies where the scanner
/// would be; choosing one enrols the way its code would.
final class EnrollmentTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testChoosingAStudyInTheSimulatorEnrols() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--resetPreferences", "--skipOnboarding", "--mode", "study", "--disableFirebase", "--disableHealthRecords"]
        app.launch()

        let scan = app.buttons["Scan QR Code"].firstMatch
        XCTAssert(scan.waitForExistence(timeout: 20), "Without a study, the home offers to enrol.")
        scan.tap()

        XCTAssert(app.navigationBars["Choose a Study"].waitForExistence(timeout: 5), "The scanner's place lists the studies in a simulator.")
        XCTAssert(app.staticTexts["edu.stanford.plainly.spineAI"].exists, "Each study shows with its identifier.")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'SpineAI'")).firstMatch.tap()

        XCTAssert(app.navigationBars["Choose a Study"].waitForNonExistence(timeout: 5), "Choosing a study closes the list.")
        XCTAssert(app.staticTexts["SpineAI"].waitForExistence(timeout: 5), "The home shows the chosen study.")
    }
}
