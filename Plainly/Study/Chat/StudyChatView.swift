//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveChat
import GroveFoundation
import GroveLLM
import GroveViews
import PlainlyShared
import SwiftUI


struct StudyChatView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var model: StudyChatViewModel
    @State private var responseGenerationTask: Task<Void, Never>?
    @State private var responseGenerationAttempt = 0
    /// A failed generation, shown inline under the conversation with a retry.
    @State private var generationError: AnyLocalizedError?

    /// Only what the participant actually sent counts: the internal opening input is not a message they wrote.
    private var userMessageCount: Int {
        model.llmSession.context.count(where: \.isParticipantInput)
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
                .sheet(item: $model.presentedSheet) { sheet in
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
                // `task` rather than `onAppear`: the opening answer is the whole screen, and a missed
                // `onAppear` leaves the participant looking at an empty chat with nothing to retry.
                // The work itself is an unstructured task, so it still outlives this one.
                .task {
                    _ = model.startStudy()
                    scheduleAssistantResponseGeneration()
                }
                .onChange(of: userMessageCount) { _, _ in
                    scheduleAssistantResponseGeneration()
                }
                // A schema update that lands after the chat opened starts the conversation over, which
                // leaves the answer being generated attached to a session nobody is reading any more.
                .onChange(of: model.conversationGeneration) { _, _ in
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

        ChatView(
            $llmSession.context.chat,
            disableInput: !model.shouldEnableChatInput,
            messagePendingAnimation: .manual(shouldDisplay: model.showTypingIndicator),
            messagesVisibility: .init(
                hiddenMessages: .all,
                toolCalls: .hidden,
                thinking: .hidden
            )
        )
        .chatHiddenMessages([InternalInput.conversationStarterID])
        .chatAttachments([])
        // Reported inside the conversation rather than as an alert: the failure belongs to the answer
        // the participant is waiting for, and the retry sits right where they are looking.
        .chatError(generationError) {
            generationError = nil
            scheduleAssistantResponseGeneration()
        }
        // Laid over the conversation rather than above it: taking space away as the bar appears moves
        // every message down, and the scroll the answer is arriving into with them.
        .overlay(alignment: .top) {
            StudyChatProcessingView(model: model)
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.4), value: model.isProcessing)
    }
    
    init(model: StudyChatViewModel) {
        self.model = model
    }

    private func scheduleAssistantResponseGeneration() {
        generationError = nil
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
            // Abandoning an answer leaves the chat looking like one that is still coming, so it is worth
            // being able to tell the two apart in a report.
            AppDiagnostics.chat.notice("Assistant response abandoned; attempt=\(attempt)")
            return
        } catch {
            AppDiagnostics.chat.logError(error, context: "Assistant response task")
            generationError = AnyLocalizedError(error: error)
        }
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
