//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// Mirrors the app's `FirebaseMockScenario`: a UI test runs in its own process and cannot import the app.
private enum MockScenario: String {
    case chatError
    case chatErrorAfterFirstChunk
    case responseStreamingUnsupported
    case incrementalResponseState
    case responseToolCall
}


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
        let app = launchApp(scenario: .incrementalResponseState)
        let startSession = startSession(in: app)

        let responses = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedResponse))
        let response = responses.firstMatch
        XCTAssertTrue(
            response.waitForExistence(timeout: 30),
            "The Firebase-backed streaming chat response did not appear."
        )
        XCTAssertEqual(responses.count, 1, "The hidden opening prompt generated more than one assistant response.")
        XCTAssertFalse(app.buttons["Add Attachment"].exists, "Study chat unexpectedly enabled file or photo uploads.")
        XCTAssertFalse(
            app.staticTexts["Follow the study instructions to begin the conversation."].exists,
            "The internal Responses API conversation starter was visible to the participant."
        )

        let messageField = app.textFields["Message Input Textfield"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        // Typed through the helper rather than `typeText`: a CI simulator keeps the hardware
        // keyboard attached, and a plain tap then never hands the field keyboard focus.
        try messageField.enter(value: Self.userMessage, options: [.disableKeyboardDismiss])

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

        completeStudy(in: app, returningTo: startSession)
    }

    func testChatErrorThroughFirebaseEmulators() throws {
        let app = launchApp(scenario: .chatError)
        _ = startSession(in: app)

        assertChatError(in: app)
    }

    func testChatErrorAfterStreamStartsThroughFirebaseEmulators() throws {
        let app = launchApp(scenario: .chatErrorAfterFirstChunk)
        _ = startSession(in: app)

        assertChatError(in: app)
    }

    func testChatFallsBackWhenResponseStreamingIsUnsupported() throws {
        let app = launchApp(scenario: .responseStreamingUnsupported)
        _ = startSession(in: app)

        let responses = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedResponse))
        XCTAssertTrue(
            responses.firstMatch.waitForExistence(timeout: 30),
            "The non-streaming Responses API fallback did not appear."
        )
        XCTAssertEqual(responses.count, 1, "The fallback displayed the response more than once.")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The recovered streaming failure was presented as an error.")
    }

    func testResponsesFunctionCallRoundTripThroughFirebaseEmulators() throws {
        let app = launchApp(scenario: .responseToolCall)
        _ = startSession(in: app)

        XCTAssertTrue(
            app.staticTexts[expectedResponse].waitForExistence(timeout: 30),
            "The answer after the Responses API function-call continuation did not appear."
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "get_resources")).firstMatch.exists,
            "The internal health-record function call was visible to the participant."
        )
        XCTAssertFalse(app.alerts.firstMatch.exists, "The function-call continuation presented an error.")
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

    private func completeStudy(in app: XCUIApplication, returningTo startSession: XCUIElement) {
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
            app.staticTexts["You're All Set"].waitForExistence(timeout: 30),
            "The confirmation was not shown after uploading the report to Firebase Storage."
        )

        app.buttons["Done"].tap()
        XCTAssertTrue(
            startSession.waitForExistence(timeout: 10),
            "The study did not dismiss after confirming the completion."
        )
    }

    /// A report that cannot be uploaded is kept on device, surfaced on the home screen, and retried.
    func testFailedReportUploadIsRetainedAndRetried() throws {
        let app = launchApp(mockUploadError: true)
        _ = startSession(in: app)
        endSessionAfterFirstResponse(in: app)

        XCTAssertTrue(
            app.staticTexts["You're All Set"].waitForExistence(timeout: 30),
            "The completion confirmation was not shown after a failed upload."
        )
        app.buttons["Done"].tap()
        XCTAssertTrue(
            pendingNotice(in: app).waitForExistence(timeout: 15),
            "The home screen did not report the session that is waiting to be sent."
        )

        // Relaunching without the failure injected should drain the retained report.
        app.terminate()
        let retryApp = launchApp(keepRetainedReports: true)
        XCTAssertTrue(
            retryApp.staticTexts["Language Study"].waitForExistence(timeout: 10),
            "The study home screen did not appear after relaunching."
        )
        XCTAssertTrue(
            pendingNotice(in: retryApp).waitForNonExistence(timeout: 30),
            "The retained report was not uploaded on the next launch."
        )
    }

    /// The retry on launch runs before the anonymous sign-in completes, so the upload has to wait for it.
    ///
    /// Without that wait the retained report fails with a missing user and stays on the device, which is
    /// what `--useSlowFirebaseAuth` makes deterministic: it holds the sign-in back past the retry.
    func testRetainedReportUploadsWhenAuthenticationIsSlow() throws {
        let app = launchApp(mockUploadError: true)
        _ = startSession(in: app)
        endSessionAfterFirstResponse(in: app)

        XCTAssertTrue(
            app.staticTexts["You're All Set"].waitForExistence(timeout: 30),
            "The completion confirmation was not shown after a failed upload."
        )
        app.buttons["Done"].tap()
        XCTAssertTrue(
            pendingNotice(in: app).waitForExistence(timeout: 15),
            "The home screen did not report the session that is waiting to be sent."
        )

        app.terminate()
        let retryApp = launchApp(slowAuthentication: true, keepRetainedReports: true)
        XCTAssertTrue(
            retryApp.staticTexts["Language Study"].waitForExistence(timeout: 10),
            "The study home screen did not appear after relaunching."
        )
        // Nothing else triggers a retry here, so the report only clears if the upload waited for the
        // sign-in that the launch retry raced.
        XCTAssertTrue(
            pendingNotice(in: retryApp).waitForNonExistence(timeout: 60),
            "The retained report was not uploaded once the delayed authentication completed."
        )
    }

    /// - Parameter keepRetainedReports: pass `true` for a relaunch that has to find the report the
    ///   preceding launch retained. Every test otherwise starts without reports an earlier one left behind,
    ///   so the notice it waits for can only come from its own session.
    private func launchApp(
        scenario: MockScenario? = nil,
        mockUploadError: Bool = false,
        slowAuthentication: Bool = false,
        keepRetainedReports: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.languageStudy",
            "--useFirebaseEmulator",
            "--disableHealthRecords"
        ]
        if !keepRetainedReports {
            app.launchArguments.append("--resetRetainedReports")
        }
        if let scenario {
            app.launchArguments.append(contentsOf: ["--firebaseMockScenario", scenario.rawValue])
        }
        if mockUploadError {
            app.launchArguments.append("--useFirebaseMockUploadError")
        }
        if slowAuthentication {
            app.launchArguments.append("--useSlowFirebaseAuth")
        }
        app.launch()
        return app
    }

    /// Waits for the first streamed response, then ends the session from the task toolbar.
    private func endSessionAfterFirstResponse(in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", expectedResponse))
                .firstMatch
                .waitForExistence(timeout: 30),
            "The Firebase-backed streaming chat response did not appear."
        )
        let nextTask = app.buttons["Proceed to the next task"]
        XCTAssertTrue(nextTask.waitForExistence(timeout: 5))
        nextTask.tap()
        XCTAssertTrue(app.alerts["End Chat?"].waitForExistence(timeout: 5))
        app.alerts["End Chat?"].buttons["End Chat"].tap()
    }

    /// Matches the notice whichever plural variation it uses, rather than pinning the test to its wording.
    private func pendingNotice(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "waiting to be sent")).firstMatch
    }

    private func startSession(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["Language Study"].waitForExistence(timeout: 10))
        // Reports an earlier test left behind are discarded at launch, so a notice this test goes on to
        // observe can only describe its own session.
        XCTAssertFalse(pendingNotice(in: app).exists, "The launch did not start without retained reports.")
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 10))
        startSession.tap()
        return startSession
    }
}
