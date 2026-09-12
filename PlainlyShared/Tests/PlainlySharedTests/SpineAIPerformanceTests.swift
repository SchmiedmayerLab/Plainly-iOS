//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import GroveQuestionnaireFHIR
import ModelsR4
@testable import PlainlyShared
import Testing


/// The intake as shipped stays within a frame: its rules are computed once into hidden flags and the engine answers a
/// render from what it remembers, so an answer and the page that follows never hold the main thread past a refresh.
@Suite
struct SpineAIPerformanceTests {
    private static let snomed = "http://snomed.info/sct"
    private static let yes = "\(snomed)|373066001"
    private static let answeredNo = "\(snomed)|373067005"
    /// A frame on a ProMotion display, the shortest the main thread gets between two renders.
    private static let frame = Swift.Duration.milliseconds(1000.0 / 120)
    /// The triage answered with nothing that flags, then one more answer per step, the way a participant goes on.
    private static let steps: [[String: [String]]] = [
        ["1.1": ["https://spineai.stanford.edu/CodeSystem/primary-symptom|low-back-only"]],
        ["1.3": [answeredNo]],
        ["1.4": [answeredNo]],
        ["1.5": [answeredNo]],
        ["1.6": ["https://spineai.stanford.edu/CodeSystem/neurologic-emergency|none"]],
        ["1.9": [yes]]
    ]

    private static func questionnaire() throws -> GroveQuestionnaire.Questionnaire {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        url.append(path: "Plainly/Resources/Questionnaires/SpineAI_InitialSurvey.json")
        let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(contentsOf: url))
        return try GroveQuestionnaire.Questionnaire(resource)
    }


    /// One pass over every task, the way a page asks on each render; a condition the helper cannot judge counts as hidden.
    @discardableResult
    private static func pass(over responses: QuestionnaireResponses) -> Int {
        responses.questionnaire.sections.flatMap(\.tasks).count { (try? ScreeningAnswers.isEnabled($0, in: responses)) ?? false }
    }

    @Test
    func aRenderPassIsQuick() throws {
        let questionnaire = try Self.questionnaire()
        let responses = try ScreeningAnswers.responses(to: questionnaire, choosing: Self.steps[0])
        Self.pass(over: responses)
        let steady = ContinuousClock().measure {
            for _ in 0..<20 {
                Self.pass(over: responses)
            }
        } / 20
        #expect(steady < Self.frame / 4, "a render pass took \(steady)")
    }

    /// Every step restores the answers so far plus one, which recomputes every flag and the outcome, and renders once.
    /// The quickest of five tries counts, so tests running alongside do not read as a regression.
    @Test
    func anAnswerReachesTheNextRenderWithinAFrame() throws {
        let questionnaire = try Self.questionnaire()
        var answers: [String: [String]] = [:]
        Self.pass(over: try ScreeningAnswers.responses(to: questionnaire, choosing: answers))
        for step in Self.steps {
            answers.merge(step) { _, new in new }
            var perAnswer = Swift.Duration.seconds(1)
            for _ in 0..<5 {
                let measured = try ContinuousClock().measure {
                    Self.pass(over: try ScreeningAnswers.responses(to: questionnaire, choosing: answers))
                }
                perAnswer = min(perAnswer, measured)
            }
            #expect(perAnswer < Self.frame, "answering \(step.keys.sorted()) and rendering took \(perAnswer)")
        }
    }
}
