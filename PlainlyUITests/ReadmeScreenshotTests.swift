//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// The README pictures: the disclaimer and the study home, the questionnaire, the task instructions, the chat, and a
/// voice conversation, shot by `scripts/readme-screenshots.sh` with the Firebase emulator standing in for the chat.
@MainActor
final class ReadmeScreenshotTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try XCTSkipUnless(ScreenshotWalk.isReadmeRun, "Run through scripts/readme-screenshots.sh.")
    }

    func testScreenshots() throws {
        ScreenshotWalk.welcomeAndDisclaimer(capturesWelcome: false)
        ScreenshotWalk.studyHome()
        ScreenshotWalk.questionnaire()
        try ScreenshotWalk.instructionsAndChat()
        try ScreenshotWalk.voiceConversation(shots: [("06_Voice", .speaking)])
    }
}
