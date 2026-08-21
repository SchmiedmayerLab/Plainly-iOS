//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import PlainlyShared
import PlainlyStudyDefinitions
import SwiftUI


struct RootView: View {
    @LocalPreference(.onboardingFlowComplete) private var didCompleteOnboarding

    var body: some View {
        VStack {
            if !didCompleteOnboarding {
                EmptyView()
            } else if case .study(.some(let studyId)) = Plainly.mode, let study = Study.withId(studyId) {
                StudyHomeView(study: study, userInfo: [:])
            } else {
                StudyHomeView()
            }
        }
    }
}
