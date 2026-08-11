//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import UIKit
import XCTest


@MainActor
private enum SnapshotSupport {
    static var app: XCUIApplication?
    static var directory: URL?
}


@MainActor
final class AppStoreScreenshotTests: XCTestCase, Sendable {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }


    func testScreenshots() throws {
        let onboardingApp = XCUIApplication()
        setupSnapshot(onboardingApp)
        onboardingApp.launchArguments += [
            "-onboardingFlow.complete",
            "NO",
            "--showOnboarding",
            "--mode",
            "test",
            "--disableFirebase",
            "--disableHealthRecords"
        ]
        onboardingApp.launch()
        setScreenshotOrientation()

        XCTAssertTrue(onboardingApp.staticTexts["Plainly"].waitForExistence(timeout: 10))
        snapshot("00_Welcome")

        onboardingApp.buttons["Learn More"].tap()
        XCTAssertTrue(onboardingApp.staticTexts["Disclaimer"].waitForExistence(timeout: 5))
        let agreementButton = onboardingApp.buttons["I Agree"]
        let visibleElements = ["Informational Use", "Model Limitations", "Clinical Questions", "Research Use Only"]
            .map { onboardingApp.staticTexts[$0] } + [agreementButton]
        let visibleFrame = onboardingApp.windows.firstMatch.frame
        for element in visibleElements {
            XCTAssertTrue(element.waitForExistence(timeout: 5))
            XCTAssertTrue(visibleFrame.contains(element.frame))
        }
        XCTAssertTrue(agreementButton.isHittable)
        snapshot("01_Disclaimer")

        onboardingApp.terminate()

        let studyApp = XCUIApplication()
        setupSnapshot(studyApp)
        studyApp.launchArguments += [
            "-onboardingFlow.complete",
            "YES",
            "--skipOnboarding",
            "--mode",
            "study:edu.stanford.plainly.usabilityStudy",
            "--disableFirebase",
            "--disableHealthRecords"
        ]
        studyApp.launch()
        setScreenshotOrientation()

        XCTAssertTrue(studyApp.staticTexts["Plainly User Study"].waitForExistence(timeout: 10))
        snapshot("02_Study")
        studyApp.terminate()
        SnapshotSupport.app = nil
        SnapshotSupport.directory = nil
    }
}


@MainActor
private func setScreenshotOrientation() {
    XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("iPad") == true
        ? .landscapeLeft
        : .portrait
}


@MainActor
private func setupSnapshot(_ app: XCUIApplication) {
    SnapshotSupport.app = app

    guard let simulatorHostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else {
        XCTFail("Unable to locate the simulator host home directory.")
        return
    }

    let cacheDirectory = URL(fileURLWithPath: simulatorHostHome)
        .appendingPathComponent("Library/Caches/tools.fastlane", isDirectory: true)
    SnapshotSupport.directory = cacheDirectory.appendingPathComponent("screenshots", isDirectory: true)

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


@MainActor
private func snapshot(_ name: String) {
    guard SnapshotSupport.app != nil,
          let directory = SnapshotSupport.directory,
          var simulatorName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] else {
        XCTFail("Screenshot support was not configured.")
        return
    }

    simulatorName = simulatorName.replacingOccurrences(
        of: "Clone [0-9]+ of ",
        with: "",
        options: .regularExpression
    )
    let outputURL = directory.appendingPathComponent("\(simulatorName)-\(name).png")

    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshot = XCUIScreen.main.screenshot()
        let image = XCUIDevice.shared.orientation.isLandscape
            ? fixedLandscapeOrientation(of: screenshot.image)
            : screenshot.image
        guard let data = image.pngData() else {
            XCTFail("Unable to encode screenshot \(name) as PNG.")
            return
        }
        try data.write(to: outputURL, options: .atomic)
    } catch {
        XCTFail("Unable to write screenshot \(name): \(error.localizedDescription)")
    }
}


@MainActor
private func fixedLandscapeOrientation(of image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}
