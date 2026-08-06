//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import SpeziHealthKit
import SpeziLLMOpenAI
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
            switch Plainly.mode {
            case .study:
                let _ = () // swiftlint:disable:this redundant_discardable_let
            case .standalone, .test:
                // Always show OpenAI model onboarding for chat-based interaction.
                OpenAIAPIKey()
                OpenAIModelSelection()
                // Presents the onboarding flow for the respective local, fog, or cloud LLM.
                LLMSourceSelection()
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
