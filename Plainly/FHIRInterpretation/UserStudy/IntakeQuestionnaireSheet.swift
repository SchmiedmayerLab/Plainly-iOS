//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import SpeziLLM
import SpeziLLMOpenAI
import SpeziQuestionnaire
import SpeziQuestionnaireFHIR
import SpeziViews
import SwiftUI


private enum QuestionnaireLoadState {
    case loading
    case loaded(SpeziQuestionnaire.Questionnaire)
    case failed
}


struct IntakeQuestionnaireSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(LLMRunner.self) private var llmRunner
    
    private let study: Study
    @Binding private var fhirResponse: ModelsR4.QuestionnaireResponse?
    
    @State private var questionnaireState: QuestionnaireLoadState = .loading
    @State private var viewState: ViewState = .idle
    
    var body: some View {
        Group {
            switch questionnaireState {
            case .loaded(let questionnaire):
                QuestionnaireSheet(questionnaire, completionStepConfig: .disable) { result in
                    switch result {
                    case .completed(let responses):
                        await processQuestionnaireResponses(responses)
                    case .cancelled:
                        dismiss()
                    }
                }
            case .failed:
                ContentUnavailableView("Unable to load questionnaire", systemImage: "document.badge.gearshape")
                Button("Dismiss") {
                    dismiss()
                }
            case .loading:
                ProgressView("Loading Questionnaire…")
                    .accessibilityIdentifier("QuestionnaireLoadingIndicator")
            }
        }
        .viewStateAlert(state: $viewState)
        .onAppear {
            AppDiagnostics.questionnaire.notice(
                "Initial questionnaire sheet appeared; study=\(study.id, privacy: .public)"
            )
        }
        .onChange(of: viewState) { oldValue, newValue in
            if oldValue.isError && newValue == .idle {
                // we were displaying an error but it got dismissed and we're now back in the idle state.
                // in this case we simply want to dismiss the view
                dismiss()
            }
        }
        .task {
            await loadQuestionnaire()
        }
    }
    
    init(study: Study, response: Binding<ModelsR4.QuestionnaireResponse?>) {
        self.study = study
        self._fhirResponse = response
    }

    private func loadQuestionnaire() async {
        questionnaireState = .loading
        do {
            guard let url = try study.initialQuestionnaireURL(in: .main) else {
                AppDiagnostics.questionnaire.fault(
                    "Study requires an initial questionnaire but has no questionnaire URL; study=\(study.id, privacy: .public)"
                )
                questionnaireState = .failed
                return
            }
            questionnaireState = .loaded(try await QuestionnaireLoader.shared.questionnaire(from: url))
            AppDiagnostics.questionnaire.notice(
                "Initial questionnaire became ready; study=\(study.id, privacy: .public)"
            )
        } catch is CancellationError {
            AppDiagnostics.questionnaire.notice(
                "Initial questionnaire load cancelled; study=\(study.id, privacy: .public)"
            )
            return
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Initial questionnaire preparation")
            questionnaireState = .failed
            #if DEBUG
            viewState = .error(AnyLocalizedError(error: error))
            #endif
        }
    }
    
    private func processQuestionnaireResponses(_ speziResponses: SpeziQuestionnaire.QuestionnaireResponses) async {
        let correlationID = AppDiagnostics.correlationID()
        AppDiagnostics.questionnaire.notice("""
            Questionnaire response processing started; correlation=\(correlationID, privacy: .public); \
            study=\(study.id, privacy: .public)
            """)
        viewState = .processing
        do {
            let fhirResponse = try ModelsR4.QuestionnaireResponse(speziResponses)
            let summary = try await speziResponses.summarize(using: llmRunner)
            study.interpretMultipleResourcesPrompt = """
                \(study.interpretMultipleResourcesPrompt.promptText)
                
                Initial User Questionnaire Summary:
                \(summary)
                """
            self.fhirResponse = fhirResponse
            AppDiagnostics.questionnaire.notice("""
                Questionnaire response processing completed; correlation=\(correlationID, privacy: .public); \
                study=\(study.id, privacy: .public)
                """)
            dismiss()
        } catch {
            AppDiagnostics.questionnaire.logError(
                error,
                context: "Questionnaire response processing",
                correlationID: correlationID
            )
            // the view will get dismissed when the user dismisses the alert, via the `onChange(of: viewState)` above.
            viewState = .error(AnyLocalizedError(error: error))
            return
        }
    }
}


extension ViewState {
    var isError: Bool {
        switch self {
        case .error:
            true
        case .idle, .processing:
            false
        }
    }
}
