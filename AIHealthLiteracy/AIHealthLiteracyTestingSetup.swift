//
// This source file is part of the Stanford AI Health Literacy iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import SwiftUI


private struct AIHealthLiteracyTestingSetup: ViewModifier {
    @LocalPreference(.onboardingFlowComplete) var completedOnboardingFlow
    
    func body(content: Content) -> some View {
        content
            .task {
                if FeatureFlags.skipOnboarding {
                    completedOnboardingFlow = true
                }
                if FeatureFlags.showOnboarding {
                    completedOnboardingFlow = false
                }
            }
    }
}


extension View {
    func testingSetup() -> some View {
        self.modifier(AIHealthLiteracyTestingSetup())
    }
}
