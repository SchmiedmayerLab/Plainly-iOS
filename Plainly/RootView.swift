//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import PlainlyStudyDefinitions
import SpeziFoundation
import SwiftUI


struct RootView: View {
    @LocalPreference(.onboardingFlowComplete) private var didCompleteOnboarding
    
    var body: some View {
        VStack {
            if !didCompleteOnboarding {
                EmptyView()
            } else {
                switch Plainly.mode {
                case .standalone, .test:
                    HomeView()
                case .study(let studyId):
                    if let studyId, let study = Study.withId(studyId), let studyConfig = studyConfig(for: studyId) {
                        StudyHomeView(study: study, config: studyConfig, userInfo: [:])
                    } else {
                        StudyHomeView()
                    }
                }
            }
        }
    }

    private func studyConfig(for studyId: Study.ID) -> StudyConfig? {
        if FeatureFlags.useFirebaseEmulator {
            StudyConfig(
                openAIAPIKey: nil,
                openAIEndpoint: .firebaseFunction(name: "chat"),
                reportEmail: "",
                encryptionKey: nil
            )
        } else {
            AppConfigFile.current().studyConfigs[studyId]
        }
    }
}
