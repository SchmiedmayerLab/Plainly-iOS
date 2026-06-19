//
// This source file is part of the Stanford AI Health Literacy iOS project
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


/// Displays an multi-step onboarding flow for AIHealthLiteracy.
struct OnboardingFlow: View {
    @Environment(HealthKit.self) private var healthKit: HealthKit?
    @LocalPreference(.onboardingFlowComplete) var completedOnboardingFlow
    
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
            switch AIHealthLiteracy.mode {
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
    OnboardingFlow()
}
