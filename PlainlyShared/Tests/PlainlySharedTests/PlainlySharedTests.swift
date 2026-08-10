//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import Testing


@Suite
struct PlainlySharedTests {
    @Test(arguments: [
        AppLaunchMode.test,
        .study(studyId: nil),
        .study(studyId: "study")
    ])
    func launchModeRoundTrips(mode: AppLaunchMode) {
        #expect(AppLaunchMode(rawValue: mode.rawValue) == mode)
    }
}
