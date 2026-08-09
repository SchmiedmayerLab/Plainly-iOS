//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import SpeziQuestionnaire


extension Questionnaire.Task {
    /// The identifier a question carries until its task assigns one.
    ///
    /// Identifiers are positional and assigned by ``Study/Task/questionnaire``, so a study definition
    /// does not have to invent one per question.
    static let unassignedId = ""

    /// A question that only presents text and collects no answer.
    public static func instructional(_ text: String) -> Self {
        Self(id: unassignedId, title: text, kind: .instructional(text), isOptional: true)
    }

    /// A question answered with free text.
    public static func freeText(_ text: String, isOptional: Bool = false) -> Self {
        Self(
            id: unassignedId,
            title: text,
            // Validation matches the whole string, so this rejects an answer that is only whitespace.
            kind: .freeText(.init(regex: try? NSRegularExpression(pattern: "(?s).*\\S.*"))),
            isOptional: isOptional
        )
    }

    /// A question answered by picking one of an ordered set of labelled options.
    ///
    /// Options are identified by their one-based position, which is the value the study reports.
    public static func scale(_ text: String, options: Study.Task.AnswerOptions, isOptional: Bool = false) -> Self {
        let choices = options.enumerated().map { index, option in
            Kind.ChoiceConfig.Option(id: "\(index + 1)", title: option)
        }
        return choice(text, options: choices, isOptional: isOptional)
    }

    /// A Net Promoter Score question.
    ///
    /// Presented as the same labelled scale as any other choice question, with the score as the option
    /// identifier so that it is what the study reports.
    public static func netPromoterScore(_ text: String, range: ClosedRange<Int>, isOptional: Bool = false) -> Self {
        choice(text, options: range.map { .init(id: "\($0)", title: "\($0)") }, isOptional: isOptional)
    }

    private static func choice(
        _ text: String,
        options: [Kind.ChoiceConfig.Option],
        isOptional: Bool
    ) -> Self {
        Self(
            id: unassignedId,
            title: text,
            kind: .choice(.init(options: options, allowsMultipleSelection: false)),
            isOptional: isOptional
        )
    }
}
