//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest


/// The App Store pictures: welcome, disclaimer and the study home, taken by `fastlane screenshots`.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    func testScreenshots() {
        ScreenshotWalk.welcomeAndDisclaimer()
        ScreenshotWalk.studyHome()
    }
}
