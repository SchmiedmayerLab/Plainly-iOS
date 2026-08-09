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
/// Each task is its own ``Questionnaire``, so the chat runs between presentations rather than inside one.
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
                    submit(responses, for: task)
                case .cancelled:
                    model.presentedSheet = nil
                }
            }
        }
    }

    init(model: StudyChatViewModel) {
        self.model = model
    }

    private func submit(_ responses: QuestionnaireResponses, for task: Study.Task) {
        model.presentedSheet = nil
        model.submitSurveyResponses(responses, for: task)
    }
}
