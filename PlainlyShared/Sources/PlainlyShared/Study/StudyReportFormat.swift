//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SpeziQuestionnaire


/// How a study's survey answers are represented in its report.
public enum StudyReportFormat: Hashable, Sendable {
    /// The flat question/answer list Plainly emitted before adopting `SpeziQuestionnaire`.
    ///
    /// Kept for studies that are already collecting, so their downstream analysis is unaffected.
    case surveyAnswers
    /// A FHIR `QuestionnaireResponse` per task, matching how the initial questionnaire is already reported.
    case questionnaireResponse
}


extension Questionnaire.Task {
    /// The value the flat report format uses for a question that was not answered.
    public static let legacyUnansweredValue = "unanswered"

    /// The answer as the flat report format records it.
    ///
    /// Scales and Net Promoter Score questions identify their options by the value the study reports,
    /// so the selected identifier is the answer.
    public func legacyAnswer(from value: QuestionnaireResponses.Response.Value) -> String {
        switch value {
        case .string(let text):
            text
        case .choice(let choice):
            choice.selectedOptions.first ?? Self.legacyUnansweredValue
        case .number(let number):
            "\(Int(number))"
        case .bool(let flag):
            "\(flag)"
        case .none, .date, .attachments, .custom:
            Self.legacyUnansweredValue
        }
    }
}
