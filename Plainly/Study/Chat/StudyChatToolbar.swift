//
// This source file is part of the Stanford Spezi project
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
        .confirmationDialog(
            "Going back will reset your chat history.",
            isPresented: $model.isDismissDialogPresented,
            titleVisibility: .visible,
            actions: {
                Button("Yes", role: .destructive, action: onDismiss)
                Button("No", role: .cancel) {}
            },
            message: {
                Text("Do you want to continue?")
            }
        )
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
