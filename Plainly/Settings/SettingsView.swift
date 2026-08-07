//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SpeziFoundation
import SpeziViews
import SwiftUI


struct SettingsView: View {
    @Environment(FHIRInterpretationModule.self) private var fhirInterpretationModule

    @LocalPreference(.enableTextToSpeech) private var enableTextToSpeech
    @LocalPreference(.resourceLimit) private var resourceLimit
    
    @State private var path = ManagedNavigationStack.Path()
    
    var body: some View {
        ManagedNavigationStack(path: path) {
            Form {
                RemoteLLMSettingsSection()
                speechSettings
                resourcesLimitSettings
                resourcesSettings
                promptsSettings
            }
            .navigationTitle("SETTINGS_TITLE")
            .toolbar {
                ToolbarItem {
                    DismissButton()
                }
            }
        }
    }

    private var speechSettings: some View {
        Section("SETTINGS_SPEECH") {
            Toggle(isOn: $enableTextToSpeech) {
                Text("SETTINGS_SPEECH_TEXT_TO_SPEECH")
            }
        }
    }
    
    private var resourcesLimitSettings: some View {
        Section("Resource Limit") {
            Stepper(value: $resourceLimit, in: 10...2000, step: 10) {
                Text("Resource Limit \(resourceLimit)")
            } onEditingChanged: { complete in
                if complete {
                    Task {
                        await fhirInterpretationModule.updateSchemas()
                    }
                }
            }
        }
    }
    
    private var resourcesSettings: some View {
        Section("Resource Selection") {
            SettingsNavigationButton("Resource Selection") {
                path.append {
                    ResourceSelection()
                }
            }
        }
    }

    private var promptsSettings: some View {
        Section("SETTINGS_PROMPTS") {
            customizePromptButton(for: .summarizeSingleFHIRResourceDefaultPrompt, label: "SETTINGS_PROMPTS_SUMMARY")
            customizePromptButton(for: .interpretSingleFHIRResource, label: "SETTINGS_PROMPTS_INTERPRETATION")
            customizePromptButton(
                for: .interpretMultipleResourcesDefaultPrompt,
                label: "SETTINGS_PROMPTS_INTERPRETATION_MULTIPLE_RESOURCES"
            )
        }
    }
    
    private func customizePromptButton(for promptDefinition: FHIRPrompt, label: LocalizedStringResource) -> some View {
        SettingsNavigationButton(label) {
            path.append {
                FHIRPromptCustomizationView(label, prompt: promptDefinition) {
                    await fhirInterpretationModule.updateSchemas()
                    path.removeLast()
                }
            }
        }
    }
}
