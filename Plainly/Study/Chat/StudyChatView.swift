//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SpeziChat
import SpeziFoundation
import SpeziLLM
import SpeziViews
import SwiftUI


struct StudyChatView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var model: StudyChatViewModel
    @State private var viewState: ViewState = .idle
    @State private var responseGenerationTask: Task<Void, Never>?
    @State private var responseGenerationAttempt = 0
    /// An error that can only be shown once the presented sheet has gone away.
    @State private var pendingError: AnyLocalizedError?

    private var userMessageCount: Int {
        model.llmSession.context.count(where: { $0.role == .user })
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack { // swiftlint:disable:this closure_body_length
            chatView
                .applyTitleConfig(model.navigationState.titleConfig(in: model.study))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    StudyChatToolbar(
                        model: model,
                        onDismiss: {
                            model.handleDismiss(dismiss: dismiss)
                        }
                    )
                }
                .sheet(item: $model.presentedSheet, onDismiss: presentPendingError) { sheet in
                    switch sheet {
                    case .instructions:
                        taskInstructionSheet()
                    case .survey:
                        SurveySheet(model: model)
                    case .completion:
                        StudyCompletedSheet(studyTitle: model.study.title, state: model.completionState) {
                            model.finishCompletedStudy()
                            dismiss()
                        }
                    }
                }
                .alert("End Chat?", isPresented: $model.isShowingConfirmEndChatAlert) {
                    Button("Continue Chat", role: .cancel) {}
                    Button("End Chat") {
                        model.endStudy()
                    }
                } message: {
                    Text("Do you want to end the chat and complete your participation in the study?")
                }
                .viewStateAlert(state: $viewState)
                .onAppear {
                    _ = model.startStudy()
                    scheduleAssistantResponseGeneration()
                }
                .onChange(of: userMessageCount) { _, _ in
                    scheduleAssistantResponseGeneration()
                }
                .onChange(of: model.llmSession.state) { _, newValue in
                    if case .error(let error) = newValue {
                        AppDiagnostics.chat.logError(error, context: "LLM session state")
                    }
                }
                .onDisappear {
                    responseGenerationTask?.cancel()
                }
        }
    }
    
    @ViewBuilder private var chatView: some View {
        @Bindable var llmSession = model.llmSession

        VStack {
            StudyChatProcessingView(model: model)
            ChatView(
                $llmSession.context.chat,
                disableInput: !model.shouldEnableChatInput,
                messagePendingAnimation: .manual(shouldDisplay: model.showTypingIndicator)
            )
        }
        .animation(.easeInOut(duration: 0.4), value: model.isProcessing)
    }
    
    init(model: StudyChatViewModel) {
        self.model = model
    }

    private func scheduleAssistantResponseGeneration() {
        responseGenerationAttempt += 1
        let attempt = responseGenerationAttempt
        responseGenerationTask?.cancel()
        responseGenerationTask = Task {
            await generateAssistantResponse(attempt: attempt)
        }
    }

    private func generateAssistantResponse(attempt: Int) async {
        defer {
            if responseGenerationAttempt == attempt {
                responseGenerationTask = nil
            }
        }
        do {
            _ = try await model.generateAssistantResponse()
        } catch is CancellationError {
            return
        } catch {
            AppDiagnostics.chat.logError(error, context: "Assistant response task")
            present(AnyLocalizedError(error: error))
        }
    }

    /// Shows the error, waiting for any presented sheet to go away first.
    ///
    /// A sheet and an alert cannot be presented at the same time, and a generation that fails while a
    /// sheet is still animating in would otherwise lose its alert.
    private func present(_ error: AnyLocalizedError) {
        guard model.presentedSheet != nil else {
            viewState = .error(error)
            return
        }
        pendingError = error
        model.presentedSheet = nil
    }

    private func presentPendingError() {
        guard let pendingError else {
            return
        }
        self.pendingError = nil
        viewState = .error(pendingError)
    }

    @ViewBuilder
    private func taskInstructionSheet() -> some View {
        if let task = model.currentTask, let taskIdx = model.userDisplayableCurrentTaskIdx {
            TaskInstructionView(task: task, userDisplayableCurrentTaskIdx: taskIdx) {
                model.presentedSheet = nil
            }
        }
    }
}


extension View {
    @ViewBuilder
    func applyTitleConfig(_ config: StudyChatViewModel.NavigationState.TitleConfig) -> some View {
        if #available(iOS 26, *), let subtitle = config.subtitle {
            self.navigationTitle(config.title)
                .navigationSubtitle(subtitle)
        } else {
            self.navigationTitle(config.title)
        }
    }
}
