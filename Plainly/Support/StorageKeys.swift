//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import GroveLLMOpenAI
import PlainlyShared


extension LocalPreferenceKeys {
    // MARK: - Onboarding
    /// A `Bool` flag indicating of the onboarding was completed.
    static let onboardingFlowComplete = LocalPreferenceKey<Bool>("onboardingFlow.complete", default: false)

    // MARK: - Settings
    /// Indicates the limit of resources that should be included in the all resources query
    static let resourceLimit = LocalPreferenceKey<Int>("settings.resourceLimit", default: 250)
}
