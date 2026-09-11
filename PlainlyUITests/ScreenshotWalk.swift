//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import UIKit
import XCTest
import XCTestExtensions


/// The screens the App Store and the README show, walked the same way for both.
///
/// `fastlane screenshots` runs the App Store walk and collects what ``snapshot(_:)`` writes; `scripts/readme-screenshots.sh`
/// runs the README walk and shoots the simulator through RocketSim on every `CAPTURE` line the same call prints.
@MainActor
enum ScreenshotWalk {
    private static var app: XCUIApplication?
    private static var directory: URL?

    /// Whether `scripts/readme-screenshots.sh` is driving the walk, which pauses after every picture until the
    /// marker has reached the script.
    static var isReadmeRun: Bool {
        ProcessInfo.processInfo.environment["PLAINLY_README_SCREENSHOTS"] == "1"
    }

    static func welcomeAndDisclaimer() {
        let app = launch(arguments: ["-onboardingFlow.complete", "NO", "--showOnboarding", "--mode", "test"])
        XCTAssertTrue(app.staticTexts["Plainly"].waitForExistence(timeout: 10))
        snapshot("00_Welcome")

        app.buttons["Learn More"].tap()
        XCTAssertTrue(app.staticTexts["Disclaimer"].waitForExistence(timeout: 5))
        let agreementButton = app.buttons["I Agree"]
        let visibleElements = ["Informational Use", "Model Limitations", "Clinical Questions", "Research Use Only"]
            .map { app.staticTexts[$0] } + [agreementButton]
        let visibleFrame = app.windows.firstMatch.frame
        for element in visibleElements {
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            XCTAssertTrue(visibleFrame.contains(element.frame))
        }
        XCTAssertTrue(agreementButton.isHittable)
        snapshot("01_Disclaimer")
        app.terminate()
    }

    static func studyHome() {
        let app = launch(arguments: ["-onboardingFlow.complete", "YES", "--skipOnboarding", "--mode", "study:edu.stanford.plainly.usabilityStudy"])
        XCTAssertTrue(app.staticTexts["Plainly User Study"].waitForExistence(timeout: 10))
        snapshot("02_Study")
        app.terminate()
    }

    static func questionnaire() {
        let app = launch(arguments: [
            "-onboardingFlow.complete", "YES", "--skipOnboarding", "--resetPreferences", "--mode", "study:edu.stanford.plainly.spineAI"
        ])
        let startQuestionnaire = app.buttons["Start Questionnaire"]
        XCTAssertTrue(startQuestionnaire.waitForExistence(timeout: 10))
        startQuestionnaire.tap()
        XCTAssertTrue(app.staticTexts["Triage Questions"].waitForExistence(timeout: 30))
        snapshot("03_Questionnaire")
        app.terminate()
    }

    /// The first task's instructions over the chat, then the chat with the emulator's opening summary and a question
    /// typed but not yet sent, since the emulator answers every turn with the same text.
    static func instructionsAndChat() throws {
        let app = launch(arguments: [
            "-onboardingFlow.complete", "YES", "--skipOnboarding", "--resetRetainedReports", "--useFirebaseEmulator",
            "--mode", "study:edu.stanford.plainly.usabilityStudy"
        ])
        let startSession = app.buttons["Start Session"]
        XCTAssertTrue(startSession.waitForExistence(timeout: 10))
        startSession.tap()
        XCTAssertTrue(app.staticTexts["Welcome"].waitForExistence(timeout: 30))
        snapshot("04_Instructions")

        // The chat's own close button sits above the sheet's; the sheet's is the lower one.
        let closeButtons = app.buttons.matching(identifier: "Close").allElementsBoundByIndex
        let sheetClose = try XCTUnwrap(closeButtons.max { $0.frame.minY < $1.frame.minY })
        sheetClose.tap()
        let summary = ProcessInfo.processInfo.environment["PLAINLY_MOCK_CHAT_RESPONSE"] ?? ""
        XCTAssertFalse(summary.isEmpty, "PLAINLY_MOCK_CHAT_RESPONSE names the summary the emulator answers with.")
        let response = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", summary)).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 30))
        let messageField = app.textFields["Message Input Textfield"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        try messageField.enter(value: "What does my most recent diagnosis mean for me?", options: [.disableKeyboardDismiss])
        snapshot("05_Chat")
        app.terminate()
    }

    private static func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += arguments + ["--disableHealthRecords"]
        if !arguments.contains("--useFirebaseEmulator") {
            app.launchArguments.append("--disableFirebase")
        }
        app.launch()
        XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("iPad") == true
            ? .landscapeLeft
            : .portrait
        return app
    }

    private static func setupSnapshot(_ app: XCUIApplication) {
        Self.app = app
        guard let simulatorHostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
            XCTFail("Unable to locate the simulator host home directory.")
            return
        }
        let cacheDirectory = URL(fileURLWithPath: simulatorHostHome)
            .appendingPathComponent("Library/Caches/tools.fastlane", isDirectory: true)
        directory = cacheDirectory.appendingPathComponent("screenshots", isDirectory: true)
        if let language = try? String(contentsOf: cacheDirectory.appendingPathComponent("language.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        if let locale = try? String(contentsOf: cacheDirectory.appendingPathComponent("locale.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !locale.isEmpty {
            app.launchArguments += ["-AppleLocale", locale]
        }
        app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES", "-ui_testing"]
    }

    private static func snapshot(_ name: String) {
        guard app != nil, let directory, var simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] else {
            XCTFail("Screenshot support was not configured.")
            return
        }
        simulatorName = simulatorName.replacingOccurrences(of: "Clone [0-9]+ of ", with: "", options: .regularExpression)
        let outputURL = directory.appendingPathComponent("\(simulatorName)-\(name).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let screenshot = XCUIScreen.main.screenshot()
            let image = XCUIDevice.shared.orientation.isLandscape ? fixedLandscapeOrientation(of: screenshot.image) : screenshot.image
            guard let data = image.pngData() else {
                XCTFail("Unable to encode screenshot \(name) as PNG.")
                return
            }
            try data.write(to: outputURL, options: .atomic)
        } catch {
            XCTFail("Unable to write screenshot \(name): \(error.localizedDescription)")
        }
        // The README script shoots on this line; the pause keeps the screen still until the line has reached it.
        print("CAPTURE \(name.drop { $0.isNumber || $0 == "_" })")
        if isReadmeRun {
            sleep(6)
        }
    }

    private static func fixedLandscapeOrientation(of image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
