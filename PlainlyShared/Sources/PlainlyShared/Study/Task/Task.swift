//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable function_default_parameter_at_end

public import SpeziQuestionnaire


extension Study {
    /// Represents a group of related questions in a survey
    public struct Task: Hashable, Identifiable, Sendable {
        /// Unique identifier for the task
        public let id: String
        public let title: String?
        /// Optional instructions displayed to the user
        public let instructions: String?
        
        public let assistantMessagesLimit: ClosedRange<Int>?
        
        /// The questions contained in this task
        public let questions: [Questionnaire.Task]
        
        public init(
            id: String,
            title: String? = nil,
            instructions: String?,
            assistantMessagesLimit: ClosedRange<Int>? = nil,
            questions: [Questionnaire.Task]
        ) {
            self.id = id
            self.title = title
            self.instructions = instructions
            self.assistantMessagesLimit = assistantMessagesLimit
            self.questions = questions
        }
    }
}


extension Study.Task {
    /// The identifier ``questionnaire(title:)`` assigns to the question at `index`.
    public static func questionId(at index: Int) -> String {
        "question-\(index)"
    }

    /// The task's questions as a questionnaire.
    ///
    /// Questions are identified by position, so a definition does not have to name each one and the
    /// responses can be read back in the order the study declares them.
    ///
    /// - parameter title: The title the questions are presented under, e.g. the task's position in the
    ///     study. The task's own title becomes the subtitle.
    public func questionnaire(title: String) -> Questionnaire {
        let tasks = questions.enumerated().map { index, question in
            var question = question
            question.id = Self.questionId(at: index)
            return question
        }
        return Questionnaire(
            metadata: .init(id: id, url: nil, title: title, explainer: instructions ?? ""),
            sections: [.init(id: id, title: self.title ?? "", tasks: tasks)]
        )
    }
}
