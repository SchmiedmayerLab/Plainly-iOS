//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import SpeziHealthKit
import SpeziViews
import SwiftUI


struct OnboardingSheet: View {
    @Binding var didComplete: Bool

    var body: some View {
        if !didComplete {
            Color.clear
                .frame(height: 0)
                .sheet(isPresented: !$didComplete) {
                    OnboardingFlow(completedOnboardingFlow: $didComplete)
                        .presentationSizing(.page)
                }
        }
    }
}


/// Displays a multi-step onboarding flow for Plainly.
struct OnboardingFlow: View {
    @Binding var completedOnboardingFlow: Bool
    @State private var navigationPath = ManagedNavigationStack.Path()
    
    
    var body: some View {
        ManagedNavigationStack(didComplete: $completedOnboardingFlow, path: navigationPath) {
            Welcome()
            Disclaimer()
            if Plainly.mode.requiresUserProvidedAPIKey {
                OpenAIAPIKey()
                OpenAIModelSelection()
            }
            if HKHealthStore.isHealthDataAvailable() {
                HealthKitPermissions()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!completedOnboardingFlow)
    }
}


#Preview {
    OnboardingFlow(completedOnboardingFlow: .constant(false))
}
