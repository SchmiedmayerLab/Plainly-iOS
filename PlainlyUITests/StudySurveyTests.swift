//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// A task's questions stand between the participant and the next task, however they leave the survey sheet.
///
/// Runs through the Firebase emulators like the end-to-end tests: a chat cannot open without a backend.
@MainActor
final class StudySurveyTests: XCTestCase {
    private static let firstTaskQuestion = "How clear and understandable was the summary provided by the app?"
    private static let secondTaskInstructions = "Ask a clarifying question about the most recent diagnosis from your last medical visit."

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAINLY_RUN_FIREBASE_E2E"] == "1",
            "Run through scripts/run-firebase-e2e.sh so the Firebase emulators are available."
        )
    }

    /// Closing the survey and tapping Next Task used to move on to the next task without any answers, and past the
    /// last task it uploaded the report without them.
    func testClosingTheSurveyDoesNotSkipTheTask() throws {
        let app = launchApp()
        try openFirstTaskChat(in: app)

        let nextTask = app.buttons["Proceed to the next task"]
        XCTAssertTrue(nextTask.waitForExistence(timeout: 10))
        nextTask.tap()
        let question = app.staticTexts[Self.firstTaskQuestion]
        XCTAssertTrue(question.waitForExistence(timeout: 10), "Next Task did not present the task's questions.")

        // Untouched, the questionnaire closes without asking, which is how a participant leaves it in one tap.
        let closeQuestionnaire = app.buttons["CloseQuestionnaire"]
        XCTAssertTrue(closeQuestionnaire.waitForExistence(timeout: 5))
        closeQuestionnaire.tap()
        XCTAssertTrue(question.waitForNonExistence(timeout: 10), "Closing the questionnaire left it on screen.")

        XCTAssertTrue(nextTask.waitForExistence(timeout: 5))
        nextTask.tap()
        XCTAssertFalse(
            app.staticTexts[Self.secondTaskInstructions].waitForExistence(timeout: 5),
            "Next Task moved on to the second task although the first task's questions were never answered."
        )
        XCTAssertTrue(
            question.waitForExistence(timeout: 10),
            "Next Task did not bring back the questions the participant closed without answering."
        )
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--resetPreferences",
            "--skipOnboarding",
            "--resetRetainedReports",
            "--mode",
            "study:edu.stanford.plainly.usabilityStudy",
            "--useFirebaseEmulator",
            "--disableHealthRecords",
            "--firebaseMockScenario",
            "incrementalResponseState"
        ]
        app.launch()
        return app
    }

    /// Starts a session and waits for the opening answer, which is all the first task asks for before its questions.
    private func openFirstTaskChat(in app: XCUIApplication) throws {
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 15), "The study did not offer to start a session.")
        startSession.tap()
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 30), "The first task's instructions did not appear.")

        // The chat's own close button sits above the sheet's; the sheet's is the lower one.
        let closeButtons = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
        let sheetClose = try XCTUnwrap(closeButtons.max { $0.frame.minY < $1.frame.minY })
        sheetClose.tap()

        let expectedResponse = ProcessInfo.processInfo.environment["PLAINLY_MOCK_CHAT_RESPONSE"]
            ?? "Plainly Firebase end-to-end response."
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", expectedResponse))
                .firstMatch
                .waitForExistence(timeout: 30),
            "The opening answer did not appear, so the first task cannot be completed."
        )
    }
}
