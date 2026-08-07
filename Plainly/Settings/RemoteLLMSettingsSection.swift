//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
import SpeziLLMOpenAI
import SpeziViews
import SwiftUI


struct RemoteLLMSettingsSection: View {
    @Environment(ManagedNavigationStack.Path.self) private var path
    @Environment(FHIRInterpretationModule.self) private var interpretationModule
    @LocalPreference(.openAIModel) private var model

    var body: some View {
        Section("SETTINGS_LLM") {
            if Plainly.mode.requiresUserProvidedAPIKey {
                SettingsNavigationButton("SETTINGS_OPENAI_KEY", action: showAPIKeySettings)
            }
            SettingsNavigationButton("SETTINGS_OPENAI_MODEL", action: showModelSettings)
            SettingsNavigationButton("SETTINGS_OPENAI_MODEL_PARAMETERS", action: showModelParameterSettings)
        }
    }

    private func showAPIKeySettings() {
        path.append {
            LLMOpenAIAPITokenOnboardingStep(actionText: "OPEN_AI_KEY_SAVE_ACTION") {
                path.removeLast()
            }
        }
    }

    private func showModelSettings() {
        path.append {
            LLMOpenAIModelOnboardingStep(
                "OPEN_AI_MODEL_SAVE_ACTION",
                models: OpenAIModelSelection.supportedModels,
                initial: model
            ) { selectedModel in
                model = selectedModel
                Task {
                    await interpretationModule.updateSchemas()
                    path.removeLast()
                }
            }
        }
    }

    private func showModelParameterSettings() {
        path.append {
            OpenAIModelParametersView()
        }
    }
}
