//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTHealthKit


@MainActor
class OnboardingTests: XCTestCase, Sendable {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIApplication().delete(app: "Plainly")
    }
    
    
    func testOnboardingFlow() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .health)
        app.launchArguments = ["--showOnboarding", "--mode", "test"]
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowOpenAI()
        try app.navigateOnboardingFlowHealthKitAccess()
        handleHealthRecordsAuthorization(systemUnderTest: app, accounts: [.sampleA], requireSheetToAppear: true)
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))
    }

    func testStudyOnboardingSkipsRemoteConfiguration() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .health)
        app.launchArguments = ["--showOnboarding", "--mode", "study"]
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()

        XCTAssertFalse(app.textFields["API Key…"].exists)
        XCTAssertFalse(app.buttons["Save Model Selection"].exists)
        try app.navigateOnboardingFlowHealthKitAccess()
        handleHealthRecordsAuthorization(systemUnderTest: app, accounts: [.sampleA], requireSheetToAppear: true)
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowHealthKitAccess()
        handleHealthRecordsAuthorization(systemUnderTest: app, timeout: 2)
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))
    }

    func testOnboardingContinuesWhenHealthRecordsAuthorizationIsCancelled() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .health)
        app.launchArguments = ["--showOnboarding", "--mode", "study"]
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowHealthKitAccess()

        XCTAssertTrue(
            app.navigationBars["HealthUI.ClinicalAuthorizationAccountsIntroView"].waitForExistence(timeout: 10)
        )
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowHealthKitAccess()
        XCTAssertTrue(
            app.navigationBars["HealthUI.ClinicalAuthorizationAccountsIntroView"].waitForExistence(timeout: 10)
        )
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))
    }

    func testOnboardingContinuesWhenNoHealthRecordsAreShared() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .health)
        app.launchArguments = ["--showOnboarding", "--mode", "study"]
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowHealthKitAccess()
        declineHealthRecordsAuthorization(systemUnderTest: app)
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))

        app.terminate()
        app.launch()
        try app.navigateOnboardingFlowWelcome()
        try app.navigateOnboardingFlowDisclaimers()
        try app.navigateOnboardingFlowHealthKitAccess()
        XCTAssertTrue(app.staticTexts["Health Records Access"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(
            app.navigationBars["HealthUI.ClinicalAuthorizationAccountsIntroView"].waitForExistence(timeout: 2)
        )
    }

    private func declineHealthRecordsAuthorization(systemUnderTest app: XCUIApplication) {
        XCTAssertTrue(
            app.navigationBars["HealthUI.ClinicalAuthorizationAccountsIntroView"].waitForExistence(timeout: 10)
        )
        app.buttons["Next"].tap()
        addSampleHealthRecordAccountIfNeeded(systemUnderTest: app)

        for _ in 0..<2 {
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
            app.buttons["Next"].tap()
        }

        XCTAssertTrue(app.buttons["Don’t Share"].waitForExistence(timeout: 5))
        app.buttons["Don’t Share"].tap()
    }

    private func addSampleHealthRecordAccountIfNeeded(systemUnderTest app: XCUIApplication) {
        guard !app.staticTexts["Sample Location A"].waitForExistence(timeout: 2) else {
            return
        }
        app.staticTexts["Add Account"].tap()

        let healthApp = XCUIApplication.healthApp
        handleHealthAppOnboardingIfNecessary(healthApp)
        let getStartedButton = healthApp.buttons["UIA.Health.SuggestedAction.SetUpClinicalRecords.PrimaryButton"]
        let addInstitutionButton = healthApp.staticTexts["Sample Institution A"]
        if getStartedButton.waitForExistence(timeout: 2), getStartedButton.isHittable,
           !(healthApp.staticTexts["Suggestions"].waitForExistence(timeout: 2)
             && addInstitutionButton.waitForExistence(timeout: 2)) {
            getStartedButton.tap()
        }

        let allowButton = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Once"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }
        XCTAssertTrue(addInstitutionButton.waitForExistence(timeout: 5))
        addInstitutionButton.tap()
        XCTAssertTrue(healthApp.staticTexts["Connect Account"].waitForExistence(timeout: 5))
        healthApp.staticTexts["Connect Account"].tap()
        XCTAssertTrue(healthApp.staticTexts["Done"].waitForExistence(timeout: 5))
        healthApp.staticTexts["Done"].tap()
    }
}


extension XCUIApplication {
    fileprivate func navigateOnboardingFlowWelcome() throws {
        XCTAssertTrue(staticTexts["Plainly"].waitForExistence(timeout: 5))
        XCTAssertTrue(buttons["Learn More"].waitForExistence(timeout: 2))
        buttons["Learn More"].tap()
    }
    
    
    fileprivate func navigateOnboardingFlowDisclaimers() throws {
        XCTAssertTrue(staticTexts["Disclaimer"].waitForExistence(timeout: 2))
        for title in ["Informational Use", "Model Limitations", "Clinical Questions", "Research Use Only"] {
            XCTAssertTrue(staticTexts[title].waitForExistence(timeout: 2))
        }
        XCTAssertTrue(buttons["I Agree"].waitForExistence(timeout: 2))
        buttons["I Agree"].tap()
    }
    
    
    fileprivate func navigateOnboardingFlowOpenAI() throws {
        try textFields["API Key…"].clear()
        XCTAssertEqual(textFields["API Key…"].textFieldValue, "")
        try textFields["API Key…"].enter(value: "sk-123456789")
        
        XCTAssertTrue(buttons["Continue"].waitForExistence(timeout: 2))
        buttons["Continue"].tap()
        
        XCTAssertTrue(buttons["Save Model Selection"].waitForExistence(timeout: 2))
        buttons["Save Model Selection"].tap()
    }
    
    
    fileprivate func navigateOnboardingFlowHealthKitAccess() throws {
        XCTAssertTrue(staticTexts["Health Records Access"].waitForExistence(timeout: 2))
        XCTAssertTrue(buttons["Continue"].waitForExistence(timeout: 2))
        buttons["Continue"].tap()
    }
}
