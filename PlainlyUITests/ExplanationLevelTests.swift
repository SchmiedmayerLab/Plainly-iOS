//
// This source file is part of the Plainly based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// Runs through the Firebase emulators like the end-to-end tests: a chat cannot open without a backend.
/// SpineAI's questionnaire is skipped by flag; it is covered by the questionnaire tests.
@MainActor
final class ExplanationLevelUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAINLY_RUN_FIREBASE_E2E"] == "1",
            "Run through scripts/run-firebase-e2e.sh so the Firebase emulators are available."
        )
    }

    func testTheStudyThatMeasuresComprehensionOffersTheControl() throws {
        let app = launchApp(study: "edu.stanford.plainly.spineAI")
        openChat(in: app)
        let control = app.buttons["Explanation Detail"]
        XCTAssertTrue(control.waitForExistence(timeout: 10), "SpineAI did not offer the explanation control.")
        control.tap()

        // Off until the participant opts in, so the levels stay out of sight until the toggle is on.
        let toggle = app.switches["Set the level of detail"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The sheet opened without the opt-in toggle.")
        XCTAssertFalse(app.buttons["Balanced"].exists, "The levels showed before the participant opted in.")
        // SwiftUI nests the switch inside the labelled row; a tap on the row's text does not flip it.
        if toggle.switches.firstMatch.exists {
            toggle.switches.firstMatch.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }

        // The study pre-selects a level, so opting in lands on a choice rather than on nothing.
        let balanced = app.buttons["Balanced"]
        XCTAssertTrue(balanced.waitForExistence(timeout: 5), "Opting in did not reveal the level options.")
        XCTAssertTrue(balanced.isSelected, "The sheet ignored the level the study pre-selects.")
        app.buttons["Detailed"].tap()
        XCTAssertTrue(app.buttons["Detailed"].isSelected, "Choosing a level did not take effect.")

        app.buttons["ExplanationLevelConfirm"].tap()
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Closing the sheet left the chat behind.")
    }

    func testAStudyWithoutTheSettingDoesNotShowTheControl() throws {
        let app = launchApp(study: "edu.stanford.plainly.languageStudy")
        openChat(in: app)
        XCTAssertTrue(
            app.buttons["View Instructions"].waitForExistence(timeout: 10),
            "The chat did not open, so the missing control proves nothing."
        )
        XCTAssertFalse(
            app.buttons["Explanation Detail"].exists,
            "A study that does not configure the control still showed it."
        )
    }

    private func launchApp(study: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--resetPreferences",
            "--skipOnboarding",
            "--skipInitialQuestionnaire",
            "--mode",
            "study:\(study)",
            "--useFirebaseEmulator",
            "--disableHealthRecords",
            "--firebaseMockScenario",
            "incrementalResponseState"
        ]
        app.launch()
        return app
    }

    private func openChat(in app: XCUIApplication, line: UInt = #line) {
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 15), "The study did not offer to start a session.", line: line)
        startSession.tap()
    }
}
