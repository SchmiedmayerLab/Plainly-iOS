//
// This source file is part of the Plainly iOS open-source project
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

    @LocalPreference(.resourceLimit) private var resourceLimit
    
    @State private var path = ManagedNavigationStack.Path()
    
    var body: some View {
        ManagedNavigationStack(path: path) {
            Form {
                resourcesLimitSettings
                resourcesSettings
            }
            .navigationTitle("SETTINGS_TITLE")
            .toolbar {
                ToolbarItem {
                    DismissButton()
                }
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
}
