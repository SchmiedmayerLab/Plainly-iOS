//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import SpeziLLMOpenAI


extension LocalPreferenceKeys {
    // MARK: - Onboarding
    /// A `Bool` flag indicating of the onboarding was completed.
    static let onboardingFlowComplete = LocalPreferenceKey<Bool>("onboardingFlow.complete", default: false)
    // MARK: - Home
    /// Show the onboarding instructions
    static let onboardingInstructions = LocalPreferenceKey<Bool>("resources.onboardingInstructions", default: true)
    
    
    // MARK: - Settings
    /// Indicates if the messages should be spoken
    static let enableTextToSpeech = LocalPreferenceKey<Bool>("settings.enableTextToSpeech", default: false)
    
    /// Indicates the limit of resources that should be included in the all resources query
    static let resourceLimit = LocalPreferenceKey<Int>("settings.resourceLimit", default: 250)
    
    /// Indicates the chosen OpenAI GPT model for resource interpretation.
    static let openAIModel = LocalPreferenceKey<LLMOpenAIParameters.ModelType>("settings.openAIModel.multipleResourceInterpretation", default: .gpt4o)
    
    /// Model temperature
    static let openAIModelTemperature = LocalPreferenceKey<Double>("settings.openAIModel.temperature", default: 0)
}
