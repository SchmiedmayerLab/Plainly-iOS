//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest

@MainActor
final class FirebaseEndToEndTests: XCTestCase, Sendable {
    private static let defaultResponse = "Plainly Firebase end-to-end response."

    private var expectedResponse: String {
        ProcessInfo.processInfo.environment["PLAINLY_MOCK_CHAT_RESPONSE"] ?? Self.defaultResponse
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAINLY_RUN_FIREBASE_E2E"] == "1",
            "Run through scripts/run-firebase-e2e.sh so the Firebase emulators are available."
        )
    }

    func testChatAndReportUploadThroughFirebaseEmulators() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.languageStudy",
            "--useFirebaseEmulator",
            "--disableHealthRecords"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Language Study"].waitForExistence(timeout: 10))
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 10))
        startSession.tap()

        let response = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedResponse))
            .firstMatch
        XCTAssertTrue(
            response.waitForExistence(timeout: 30),
            "The Firebase-backed streaming chat response did not appear."
        )

        let nextTask = app.buttons["Proceed to the next task"]
        XCTAssertTrue(nextTask.waitForExistence(timeout: 5))
        nextTask.tap()
        XCTAssertTrue(app.alerts["End Chat?"].waitForExistence(timeout: 5))
        app.alerts["End Chat?"].buttons["End Chat"].tap()

        XCTAssertTrue(
            app.staticTexts["Language Study"].waitForExistence(timeout: 30),
            "The study did not dismiss after uploading its report to Firebase Storage."
        )
    }
}
