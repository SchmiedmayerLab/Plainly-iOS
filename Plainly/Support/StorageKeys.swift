//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SpeziFoundation
import SpeziLLMOpenAI


extension LocalPreferenceKeys {
    // MARK: - Onboarding
    /// A `Bool` flag indicating of the onboarding was completed.
    static let onboardingFlowComplete = LocalPreferenceKey<Bool>("onboardingFlow.complete", default: false)

    // MARK: - Settings
    /// Indicates the limit of resources that should be included in the all resources query
    static let resourceLimit = LocalPreferenceKey<Int>("settings.resourceLimit", default: 250)
}
