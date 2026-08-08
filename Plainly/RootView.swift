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
        .onAppear {
            logRoutingState(reason: "appeared")
        }
        .onChange(of: didCompleteOnboarding) { _, _ in
            logRoutingState(reason: "onboarding state changed")
        }
    }

    private func studyConfig(for studyId: Study.ID) -> StudyConfig? {
        if FeatureFlags.useFirebaseEmulator {
            AppDiagnostics.configuration.notice(
                "Using Firebase emulator study configuration; study=\(studyId, privacy: .public)"
            )
            return StudyConfig(
                openAIAPIKey: nil,
                openAIEndpoint: .firebaseFunction(name: "chat"),
                reportEmail: "",
                encryptionKey: nil
            )
        } else {
            let config = AppConfigFile.current().studyConfigs[studyId]
            if config == nil {
                AppDiagnostics.configuration.fault(
                    "No bundled study configuration matches the selected study; study=\(studyId, privacy: .public)"
                )
            } else {
                AppDiagnostics.configuration.notice(
                    "Bundled study configuration selected; study=\(studyId, privacy: .public)"
                )
            }
            return config
        }
    }

    private func logRoutingState(reason: String) {
        switch Plainly.mode {
        case .standalone:
            AppDiagnostics.lifecycle.notice(
                "Root routing evaluated; reason=\(reason, privacy: .public); onboardingComplete=\(didCompleteOnboarding); mode=standalone"
            )
        case .test:
            AppDiagnostics.lifecycle.notice(
                "Root routing evaluated; reason=\(reason, privacy: .public); onboardingComplete=\(didCompleteOnboarding); mode=test"
            )
        case .study(let studyId):
            AppDiagnostics.lifecycle.notice("""
                Root routing evaluated; reason=\(reason, privacy: .public); onboardingComplete=\(didCompleteOnboarding); \
                mode=study; hasStudyID=\(studyId != nil)
                """)
        }
    }
}
