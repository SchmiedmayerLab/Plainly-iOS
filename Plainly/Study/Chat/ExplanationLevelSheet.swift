//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SwiftUI


/// Lets the participant say how much clinical detail they want, mid-conversation.
struct ExplanationLevelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var model: StudyChatViewModel

    var body: some View {
        NavigationStack {
            // Laid out top down with the spacer last: a form in a sheet this short leaves the choice
            // stranded between the navigation bar and the bottom edge.
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $model.isExplanationLevelEnabled.animation(.easeInOut(duration: 0.2))) {
                    Text("Set the level of detail")
                        .font(.subheadline.weight(.medium))
                }

                Text("Off, answers follow the study's own style. On, you choose how much detail they carry.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if model.isExplanationLevelEnabled {
                    levelSelection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Explanation Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // The confirm role draws the system's own glyph, so the sheet dismisses the way every
                    // other one does on this OS rather than with a word of its own.
                    Group {
                        if #available(iOS 26.0, *) {
                            Button(role: .confirm) {
                                dismiss()
                            }
                        } else {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("ExplanationLevelConfirm")
                }
            }
        }
        .presentationDetents([.height(model.isExplanationLevelEnabled ? 340 : 200)])
    }

    @ViewBuilder private var levelSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Detail", selection: $model.explanationLevel) {
                ForEach(ExplanationLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Explanation Detail")

            Text(model.explanationLevel.explainer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.2), value: model.explanationLevel)

            Text("This applies to the next answer. You can change it whenever you like.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
