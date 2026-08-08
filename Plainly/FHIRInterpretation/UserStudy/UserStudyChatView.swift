//
// This source file is part of the Stanford Spezi project
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


struct UserStudyChatView: View {
    @Environment(\.dismiss) private var dismiss
    
    @LocalPreference(.enableTextToSpeech) private var enableTextToSpeechPrefValue
    
    @State private var model: UserStudyChatViewModel
    @State private var viewState: ViewState = .idle
    @State private var responseGenerationTask: Task<Void, Never>?
    @State private var responseGenerationAttempt = 0
    
    private var enableTextToSpeech: Binding<Bool> {
        Binding<Bool> { [weak model] in
            guard let model else {
                return false
            }
            return model.study.isUnguided ? enableTextToSpeechPrefValue : false
        } set: { newValue in
            enableTextToSpeechPrefValue = newValue
        }
    }

    private var userMessageCount: Int {
        model.llmSession.context.count(where: { $0.role == .user })
    }

    private var assistantMessageCount: Int {
        model.llmSession.context.count(where: { $0.role == .assistant() })
    }
    
    var body: some View {
        @Bindable var model = model
        NavigationStack { // swiftlint:disable:this closure_body_length
            chatView
                .applyTitleConfig(model.navigationState.titleConfig(in: model.study))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    UserStudyChatToolbar(
                        model: model,
                        isTextToSpeechEnabled: enableTextToSpeech,
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
                    case .uploadingReport:
                        uploadSheet()
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
                    AppDiagnostics.chat.notice("""
                        Chat view appeared; study=\(model.study.id, privacy: .public); \
                        contextCount=\(model.llmSession.context.count); userCount=\(userMessageCount); \
                        assistantCount=\(assistantMessageCount); sessionState=\(model.llmSession.state.description, privacy: .public)
                        """)
                    model.didUploadHandler = {
                        dismiss()
                    }
                    _ = model.startStudy()
                    scheduleAssistantResponseGeneration()
                }
                .onChange(of: userMessageCount) { oldValue, newValue in
                    AppDiagnostics.chat.notice("""
                        User message count changed; old=\(oldValue); new=\(newValue); \
                        contextCount=\(model.llmSession.context.count); inputEnabled=\(model.shouldEnableChatInput)
                        """)
                    scheduleAssistantResponseGeneration()
                }
                .onChange(of: model.llmSession.context.count) { oldValue, newValue in
                    AppDiagnostics.chat.notice("""
                        Chat context count changed; old=\(oldValue); new=\(newValue); userCount=\(userMessageCount); \
                        assistantCount=\(assistantMessageCount); lastIsUser=\(model.llmSession.context.last?.role == .user)
                        """)
                }
                .onChange(of: model.llmSession.state) { oldValue, newValue in
                    AppDiagnostics.chat.notice("""
                        LLM session state changed; old=\(oldValue.description, privacy: .public); \
                        new=\(newValue.description, privacy: .public); contextCount=\(model.llmSession.context.count)
                        """)
                    if case .error(let error) = newValue {
                        AppDiagnostics.chat.logError(error, context: "LLM session state")
                    }
                }
                .onChange(of: model.processingState) { oldValue, newValue in
                    AppDiagnostics.chat.info("""
                        Chat processing state changed; old=\(oldValue.statusDescription, privacy: .public); \
                        new=\(newValue.statusDescription, privacy: .public)
                        """)
                }
                .onDisappear {
                    AppDiagnostics.chat.notice("""
                        Chat view disappeared; cancellingGeneration=\(responseGenerationTask != nil); \
                        contextCount=\(model.llmSession.context.count)
                        """)
                    responseGenerationTask?.cancel()
                }
        }
    }
    
    @ViewBuilder private var chatView: some View {
        @Bindable var llmSession = model.llmSession

        VStack {
            UserStudyChatProcessingView(model: model)
            ChatView(
                $llmSession.context.chat,
                disableInput: !model.shouldEnableChatInput,
                speechToText: model.study.isUnguided,
                messagePendingAnimation: .manual(shouldDisplay: model.showTypingIndicator)
            )
            .speak(llmSession.context.chat, muted: !enableTextToSpeech.wrappedValue)
        }
        .animation(.easeInOut(duration: 0.4), value: model.isProcessing)
    }
    
    init(model: UserStudyChatViewModel) {
        self.model = model
    }

    private func scheduleAssistantResponseGeneration() {
        responseGenerationAttempt += 1
        let attempt = responseGenerationAttempt
        AppDiagnostics.chat.notice("""
            Scheduling assistant response; attempt=\(attempt); replacingTask=\(responseGenerationTask != nil); \
            contextCount=\(model.llmSession.context.count); userCount=\(userMessageCount); \
            assistantCount=\(assistantMessageCount)
            """)
        responseGenerationTask?.cancel()
        responseGenerationTask = Task {
            await generateAssistantResponse(attempt: attempt)
        }
    }

    private func generateAssistantResponse(attempt: Int) async {
        defer {
            if responseGenerationAttempt == attempt {
                responseGenerationTask = nil
                AppDiagnostics.chat.debug("Assistant response task cleared; attempt=\(attempt)")
            }
        }
        do {
            _ = try await model.generateAssistantResponse()
            AppDiagnostics.chat.notice(
                "Assistant response task returned; attempt=\(attempt); contextCount=\(model.llmSession.context.count)"
            )
        } catch is CancellationError {
            AppDiagnostics.chat.notice("Assistant response task cancelled; attempt=\(attempt)")
            return
        } catch {
            AppDiagnostics.chat.logError(error, context: "Assistant response task")
            model.presentedSheet = nil
            do {
                try await Task.sleep(for: .seconds(0.5))
            } catch {
                return
            }
            viewState = .error(AnyLocalizedError(error: error))
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
    
    @ViewBuilder
    private func uploadSheet() -> some View {
        BottomSheet {
            VStack {
                Spacer()
                ProgressView("Submitting Results…")
                    .progressViewStyle(.circular)
                    .padding()
                    .interactiveDismissDisabled()
                Spacer()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}


extension View {
    @ViewBuilder
    func applyTitleConfig(_ config: UserStudyChatViewModel.NavigationState.TitleConfig) -> some View {
        if #available(iOS 26, *), let subtitle = config.subtitle {
            self.navigationTitle(config.title)
                .navigationSubtitle(subtitle)
        } else {
            self.navigationTitle(config.title)
        }
    }
}
