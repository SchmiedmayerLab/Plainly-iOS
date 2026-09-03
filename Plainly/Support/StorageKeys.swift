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

    // MARK: - Explanation Detail
    /// Whether the participant has taken over how detailed an answer should be.
    ///
    /// Off by default: a study reads what its own instructions ask for until someone decides otherwise.
    static let explanationLevelEnabled = LocalPreferenceKey<Bool>("chat.explanationLevel.enabled", default: false)
    /// The level the participant chose, kept between sessions so the chat opens the way they left it.
    static let explanationLevel = LocalPreferenceKey<String?>("chat.explanationLevel.selection", default: nil)
}
