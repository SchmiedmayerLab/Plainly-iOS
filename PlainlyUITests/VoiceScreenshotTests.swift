//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


@MainActor
final class VoiceScreenshotTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PLAINLY_VOICE_SCREENSHOTS"] == "1",
            "Set PLAINLY_VOICE_SCREENSHOTS=1 with the Firebase emulator running."
        )
    }

    func testVoiceScreenshots() throws {
        try ScreenshotWalk.voiceConversation()
    }
}
