//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct StudyChatToolbar: ToolbarContent {
    var model: StudyChatViewModel
    let onDismiss: @MainActor () -> Void

    private var enableContinueAction: Bool {
        model.shouldEnableContinueToNextTaskAction
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            dismissButton
        }
        if model.study.defaultExplanationLevel != nil {
            ToolbarItem(placement: .primaryAction) {
                explanationLevelButton
            }
        }
        ToolbarItem(placement: .primaryAction) {
            viewInstructionsButton
        }
        ToolbarItem(placement: .primaryAction) {
            continueButton
        }
    }

    @ViewBuilder private var dismissButton: some View {
        @Bindable var model = model
        Button {
            model.isDismissDialogPresented = true
        } label: {
            Image(systemName: "xmark")
                .accessibilityLabel("Dismiss")
        }
        .disabled(model.isProcessing)
        // An alert rather than a confirmation dialog: anchored to a toolbar button, a dialog shows only its destructive
        // button, and the way to stay is a tap beside it that participants do not find.
        .alert("Leave This Session?", isPresented: $model.isDismissDialogPresented) {
            Button("Stay in Chat", role: .cancel) {}
            Button("Leave and Delete Chat", role: .destructive, action: onDismiss)
        } message: {
            Text("This chat and the answers you gave in it will be deleted and not sent to the study team.")
        }
    }

    private var explanationLevelButton: some View {
        Button {
            model.presentedSheet = .explanationLevel
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("Explanation Detail")
        }
    }

    private var viewInstructionsButton: some View {
        Button {
            model.presentedSheet = .instructions
        } label: {
            Image(systemName: "info.circle")
                .accessibilityLabel("View Instructions")
        }
        .disabled(model.isTaskIntructionButtonDisabled)
    }

    @ViewBuilder private var continueButton: some View {
        let button = Button {
            model.advance()
        } label: {
            Label("Next Task", systemImage: "arrow.forward.circle")
                .accessibilityLabel("Next Task")
                .pulsate(enableContinueAction)
        }
        .disabled(!enableContinueAction)
        if model.navigationState != .completed {
            if #available(iOS 26.0, *) {
                button
                    .if(enableContinueAction) { $0.buttonStyle(.glassProminent) }
                    .animation(.interactiveSpring, value: !enableContinueAction)
            } else {
                button
            }
        }
    }
}
