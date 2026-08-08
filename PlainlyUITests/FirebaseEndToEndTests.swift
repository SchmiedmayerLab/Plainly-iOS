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
    private static let userMessage = "Tell me more about my health records."

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
        let app = launchApp()
        let startSession = startSession(in: app)

        let responses = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedResponse))
        let response = responses.firstMatch
        XCTAssertTrue(
            response.waitForExistence(timeout: 30),
            "The Firebase-backed streaming chat response did not appear."
        )

        let messageField = app.textFields["Message Input Textfield"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        messageField.tap()
        messageField.typeText(Self.userMessage)

        let sendMessage = app.buttons["Send Message"]
        XCTAssertTrue(sendMessage.waitForExistence(timeout: 5))
        sendMessage.tap()

        XCTAssertTrue(
            app.staticTexts[Self.userMessage].waitForExistence(timeout: 5),
            "The submitted user message was not written back to the chat."
        )
        let followUpResponse = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in responses.count >= 2 },
            object: responses
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [followUpResponse], timeout: 30),
            .completed,
            "The Firebase-backed follow-up response did not appear."
        )

        let nextTask = app.buttons["Proceed to the next task"]
        XCTAssertTrue(nextTask.waitForExistence(timeout: 5))
        nextTask.tap()
        XCTAssertTrue(app.alerts["End Chat?"].waitForExistence(timeout: 5))
        app.alerts["End Chat?"].buttons["End Chat"].tap()

        XCTAssertTrue(
            nextTask.waitForNonExistence(timeout: 30),
            "The study session remained visible after ending the chat."
        )
        XCTAssertTrue(
            startSession.waitForExistence(timeout: 30),
            "The study did not dismiss after uploading its report to Firebase Storage."
        )
    }

    func testChatErrorThroughFirebaseEmulators() throws {
        let app = launchApp(mockChatError: true)
        _ = startSession(in: app)

        assertChatError(in: app)
    }

    func testChatErrorAfterStreamStartsThroughFirebaseEmulators() throws {
        let app = launchApp(mockChatErrorAfterChunk: true)
        _ = startSession(in: app)

        assertChatError(in: app)
    }

    private func assertChatError(in app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(
            alert.waitForExistence(timeout: 30),
            "The Firebase callable error was not presented to the participant."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", expectedResponse))
                .firstMatch
                .exists,
            "The mock response should not be displayed after a callable error."
        )
    }

    private func launchApp(
        mockChatError: Bool = false,
        mockChatErrorAfterChunk: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.languageStudy",
            "--useFirebaseEmulator",
            "--disableHealthRecords"
        ]
        if mockChatError {
            app.launchArguments.append("--useFirebaseMockChatError")
        }
        if mockChatErrorAfterChunk {
            app.launchArguments.append("--useFirebaseMockChatErrorAfterChunk")
        }
        app.launch()
        return app
    }

    private func startSession(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["Language Study"].waitForExistence(timeout: 10))
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 10))
        startSession.tap()
        return startSession
    }
}
