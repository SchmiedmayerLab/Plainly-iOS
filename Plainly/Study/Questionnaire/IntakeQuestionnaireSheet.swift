//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLM
import GroveLLMOpenAI
import GroveQuestionnaire
import GroveQuestionnaireFHIR
import GroveViews
import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import SwiftUI


private enum QuestionnaireLoadState {
    case loading
    case loaded(GroveQuestionnaire.Questionnaire)
    case failed
}


struct IntakeQuestionnaireSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(LLMRunner.self) private var llmRunner
    
    private let inProgressStudy: InProgressStudy

    private var study: Study {
        inProgressStudy.study
    }
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
                        try await processQuestionnaireResponses(responses)
                        dismiss()
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
        .task {
            await loadQuestionnaire()
        }
    }
    
    init(inProgressStudy: InProgressStudy, response: Binding<ModelsR4.QuestionnaireResponse?>) {
        self.inProgressStudy = inProgressStudy
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
        } catch is CancellationError {
            return
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Initial questionnaire preparation")
            questionnaireState = .failed
            #if DEBUG
            viewState = .error(AnyLocalizedError(error: error))
            #endif
        }
    }
    
    /// Records the answers, and the summary the study chat opens with.
    ///
    /// Throwing hands the failure back to the questionnaire, which reports it and leaves the participant on
    /// their answers to try again. Swallowing it returned them to the study home with a summary that was
    /// never produced, and nothing said so.
    private func processQuestionnaireResponses(_ groveResponses: GroveQuestionnaire.QuestionnaireResponses) async throws {
        let correlationID = AppDiagnostics.correlationID()
        do {
            // Kept before the summary is requested: a failing summary must not discard answers the
            // participant already gave, which the report carries even when the summary is missing.
            fhirResponse = try ModelsR4.QuestionnaireResponse(groveResponses)
            inProgressStudy.questionnaireSummary = try await groveResponses.summarize(
                using: llmRunner,
                model: study.inferenceModel
            )
        } catch {
            AppDiagnostics.questionnaire.logError(
                error,
                context: "Questionnaire response processing",
                correlationID: correlationID
            )
            throw error
        }
    }
}
