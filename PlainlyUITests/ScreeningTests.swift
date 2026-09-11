//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveQuestionnaire


/// The SpineAI intake stops the study on a cauda equina symptom, and the stop outlives the launch.
final class ScreeningTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testSymptomNeedingAttentionStopsTheStudyForGood() throws {
        let app = makeApp(startingFresh: true)
        app.launch()

        let startQuestionnaire = app.buttons["Start Questionnaire"]
        XCTAssertTrue(startQuestionnaire.waitForExistence(timeout: 10))
        startQuestionnaire.tap()

        // The page carries the questionnaire's name; the group's name is its caption.
        let questionnaire = QuestionnaireSheetNavigator(app)
        XCTAssertTrue(questionnaire.waitUntilTitled("SpineAI Questionnaire", timeout: 30))
        XCTAssertTrue(app.staticTexts["Triage Questions"].waitForExistence(timeout: 5))
        questionnaire.question("1.1").select("Low back pain only")
        questionnaire.question("1.2").select("Less than 6 weeks")
        questionnaire.question("1.3").select("No")
        questionnaire.question("1.4").select("No")
        questionnaire.question("1.5").select("No")
        questionnaire.question("1.6").select("Loss of bladder or bowel control")
        questionnaire.question("1.7").select("None / not sure")
        questionnaire.question("1.9").select("No")
        questionnaire.advance()

        // The questionnaire ends on the attention page; nothing after it is asked.
        XCTAssertTrue(app.staticTexts["Please Have Your Symptoms Checked"].waitForExistence(timeout: 10))
        questionnaire.question("5.2").select("I have read this")
        questionnaire.submit()

        assertStopPage(in: app)

        // The decision is kept: a relaunch lands on the stop page, not on the questionnaire.
        let relaunched = makeApp(startingFresh: false)
        relaunched.launch()
        assertStopPage(in: relaunched)
    }

    @MainActor
    private func assertStopPage(in app: XCUIApplication, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["Please Have Your Symptoms Checked"].waitForExistence(timeout: 10), line: line)
        XCTAssertTrue(app.buttons["Call 911"].waitForExistence(timeout: 5), line: line)
        XCTAssertTrue(app.buttons["Find Emergency Care Nearby"].exists, line: line)
        XCTAssertFalse(app.buttons["Start Questionnaire"].exists, "the study must not go on", line: line)
        XCTAssertFalse(app.buttons["Start Session"].exists, "the chat must stay closed", line: line)
    }

    private func makeApp(startingFresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.spineAI",
            "--disableFirebase",
            "--disableHealthRecords"
        ]
        if startingFresh {
            app.launchArguments.append("--resetPreferences")
        }
        return app
    }
}
