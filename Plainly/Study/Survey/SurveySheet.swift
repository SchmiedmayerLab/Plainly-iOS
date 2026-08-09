//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import SpeziQuestionnaire
import SwiftUI


/// Presents the questions of the current study task.
///
/// Each task is its own ``Questionnaire``. When the next task has no chat, the sheet stays up and
/// carries straight on with that task's questions, so consecutive questionnaires read as one flow.
struct SurveySheet: View {
    private var model: StudyChatViewModel

    var body: some View {
        if let task = model.currentTask {
            QuestionnaireSheet(
                task.questionnaire(title: model.currentTaskTitle ?? ""),
                completionStepConfig: .disable
            ) { result in
                switch result {
                case .completed(let responses):
                    // Advancing decides what to present next, so the sheet is never dismissed here:
                    // clearing it first would cancel out the next task's presentation.
                    model.submitSurveyResponses(responses, for: task)
                case .cancelled:
                    model.presentedSheet = nil
                }
            }
            // A questionnaire keeps its own answers, so the next task needs one of its own.
            .id(task.id)
        }
    }

    init(model: StudyChatViewModel) {
        self.model = model
    }
}
