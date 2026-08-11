//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


@MainActor
final class QuestionnaireTests: XCTestCase, Sendable {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIApplication().delete(app: "Plainly")
    }

    func testSpineAIQuestionnaireLoadsAfterFreshInstallAndRelaunch() {
        let app = makeApp()

        app.launch()
        assertQuestionnaireLoads(in: app)

        app.terminate()
        app.launch()
        assertQuestionnaireLoads(in: app)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.spineAI",
            "--disableFirebase",
            "--disableHealthRecords"
        ]
        return app
    }

    private func assertQuestionnaireLoads(in app: XCUIApplication, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["SpineAI"].waitForExistence(timeout: 10), line: line)
        let startQuestionnaire = app.buttons["Start Questionnaire"]
        XCTAssertTrue(startQuestionnaire.waitForExistence(timeout: 5), line: line)
        startQuestionnaire.tap()

        let loadingIndicator = app.descendants(matching: .any)["QuestionnaireLoadingIndicator"]
        let firstQuestion = app.staticTexts["Which option best describes your primary symptom?"]
        XCTAssertTrue(
            loadingIndicator.waitForExistence(timeout: 1) || firstQuestion.waitForExistence(timeout: 1),
            "The questionnaire presented a blank screen instead of loading feedback or content.",
            line: line
        )
        XCTAssertTrue(
            firstQuestion.waitForExistence(timeout: 5),
            "The SpineAI questionnaire did not finish loading.",
            line: line
        )
    }
}
