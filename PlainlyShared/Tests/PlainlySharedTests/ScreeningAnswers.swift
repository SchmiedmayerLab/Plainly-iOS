//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import Testing


/// Answers a questionnaire the way a participant would, from outside Grove.
///
/// Grove only lets its own package write responses directly, so the tests hand it a draft, the same shape it
/// stores an unfinished questionnaire in, and let it resume from that.
enum ScreeningAnswers {
    struct UnsupportedCondition: Error {}

    /// Responses with the given choice answers, keyed by linkId, each a list of option ids (`system|code`).
    static func responses(
        to questionnaire: GroveQuestionnaire.Questionnaire,
        choosing answers: [String: [String]]
    ) throws -> QuestionnaireResponses {
        let entries = answers.filter { !$0.value.isEmpty }.mapValues { options -> [String: Any] in
            ["value": ["choice": ["selectedOptions": options]], "nestedResponses": [:]]
        }
        let draft: [String: Any] = [
            "responsesId": UUID().uuidString,
            "questionnaireId": questionnaire.id,
            "questionnaireVersion": questionnaire.metadata.version ?? NSNull(),
            "savedAt": 0,
            "responses": ["entries": entries]
        ]
        let data = try JSONSerialization.data(withJSONObject: draft)
        let decoded = try JSONDecoder().decode(QuestionnaireResponses.Draft.self, from: data)
        return try QuestionnaireResponses(questionnaire: questionnaire, resuming: decoded)
    }

    /// Whether the questionnaire would show a task, judged by the conditions its group and it carry.
    static func isEnabled(_ task: GroveQuestionnaire.Questionnaire.Task, in responses: QuestionnaireResponses) throws -> Bool {
        try holds(task.enabledCondition, for: task, in: responses)
    }

    private static func holds(
        _ condition: GroveQuestionnaire.Questionnaire.Condition,
        for task: GroveQuestionnaire.Questionnaire.Task,
        in responses: QuestionnaireResponses
    ) throws -> Bool {
        switch condition {
        case .all(let conditions):
            return try conditions.allSatisfy { try holds($0, for: task, in: responses) }
        case .any(let conditions):
            return try conditions.contains { try holds($0, for: task, in: responses) }
        case .not(let nested):
            return try !holds(nested, for: task, in: responses)
        case .expression(let expression):
            let engine = try #require(responses.questionnaire.expressionEngine)
            return try engine.evaluateBoolean(expression, scope: .item(task.id), in: responses) == .true
        case let .responseValueComparison(taskId, .equal, .bool(expected)):
            // The gate on a hidden flag, which its expression computed into the responses.
            return responses.responses[taskId].value == .bool(expected)
        default:
            throw UnsupportedCondition()
        }
    }
}
