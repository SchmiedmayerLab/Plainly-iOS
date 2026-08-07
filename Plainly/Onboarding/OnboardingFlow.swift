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
                }
        }
    }
}


/// Displays a multi-step onboarding flow for Plainly.
struct OnboardingFlow: View {
    @Environment(HealthKit.self) private var healthKit: HealthKit?
    @Binding var completedOnboardingFlow: Bool
    
    private var healthKitAuthorization: Bool {
        // As HealthKit not available in preview simulator
        if ProcessInfo.processInfo.isPreviewSimulator {
            false
        } else {
            healthKit?.isFullyAuthorized ?? false
        }
    }
    
    
    var body: some View {
        ManagedNavigationStack(didComplete: $completedOnboardingFlow) {
            Welcome()
            Disclaimer()
            if Plainly.mode.requiresUserProvidedAPIKey {
                OpenAIAPIKey()
                OpenAIModelSelection()
            }
            if HKHealthStore.isHealthDataAvailable() && !healthKitAuthorization {
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
