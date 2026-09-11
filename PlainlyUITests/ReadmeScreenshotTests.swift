//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// The README pictures: the App Store screens plus the questionnaire, the task instructions and the chat, shot by
/// `scripts/readme-screenshots.sh` with the Firebase emulator standing in for the chat.
@MainActor
final class ReadmeScreenshotTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try XCTSkipUnless(ScreenshotWalk.isReadmeRun, "Run through scripts/readme-screenshots.sh.")
    }

    func testScreenshots() throws {
        ScreenshotWalk.welcomeAndDisclaimer()
        ScreenshotWalk.studyHome()
        ScreenshotWalk.questionnaire()
        try ScreenshotWalk.instructionsAndChat()
    }
}
