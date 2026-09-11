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


/// The SpineAI intake decides on its own, in FHIR, whether the study goes on: a cauda equina symptom or severe
/// leg weakness stops it, while an injury, a cancer or an infection flag only adds a page of advice.
@Suite
struct SpineAIScreeningTests {
    private static let snomed = "http://snomed.info/sct"
    private static let yes = "\(snomed)|373066001"
    private static let answeredNo = "\(snomed)|373067005"
    private static let symptoms = "https://spineai.stanford.edu/CodeSystem/primary-symptom"
    private static let emergencies = "https://spineai.stanford.edu/CodeSystem/neurologic-emergency"
    private static let weakness = "https://spineai.stanford.edu/CodeSystem/radic-weakness"

    /// The questionnaire as the app ships it.
    private static func questionnaire() throws -> GroveQuestionnaire.Questionnaire {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        url.append(path: "Plainly/Resources/Questionnaires/SpineAI_InitialSurvey.json")
        let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(contentsOf: url))
        return try GroveQuestionnaire.Questionnaire(resource)
    }

    /// Answers the triage questions with nothing that flags, then applies the overrides.
    private static func responses(_ overrides: [String: [String]] = [:]) throws -> QuestionnaireResponses {
        var answers: [String: [String]] = [
            "1.1": ["\(symptoms)|low-back-only"],
            "1.3": [answeredNo],
            "1.4": [answeredNo],
            "1.5": [answeredNo],
            "1.6": ["\(emergencies)|none"],
            "1.9": [answeredNo]
        ]
        answers.merge(overrides) { _, override in override }
        return try ScreeningAnswers.responses(to: questionnaire(), choosing: answers)
    }

    private static func section(_ linkId: String, in responses: QuestionnaireResponses) throws -> GroveQuestionnaire.Questionnaire.Section {
        try #require(responses.questionnaire.sections.first { $0.id == linkId })
    }

    /// Whether a group opens, judged by its first visible task, which carries the group's own condition.
    private static func isShown(_ linkId: String, in responses: QuestionnaireResponses) throws -> Bool {
        let first = try #require(section(linkId, in: responses).tasks.first { !$0.isHidden })
        return try ScreeningAnswers.isEnabled(first, in: responses)
    }

    private static func expectShown(_ shown: [String], hidden: [String], in responses: QuestionnaireResponses) throws {
        for linkId in shown {
            #expect(try Self.isShown(linkId, in: responses), "group \(linkId) opens")
        }
        for linkId in hidden {
            #expect(try !Self.isShown(linkId, in: responses), "group \(linkId) stays closed")
        }
    }

    @Test
    func carriesTheOutcomeItem() throws {
        let questionnaire = try Self.questionnaire()
        let task = try #require(questionnaire.screeningOutcomeTask)
        #expect(task.isHidden)
        #expect(task.calculatedExpression?.contains("'needs-attention'") == true)
    }

    @Test
    func aClearIntakeIsEligible() throws {
        let responses = try Self.responses()
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["2", "3", "4", "5", "7"], in: responses)
    }

    @Test(arguments: ["retention", "bladder-bowel", "perineal-numbness", "leg-weakness", "bilateral-weakness", "bilateral-numbness"])
    func aCaudaEquinaSymptomStopsTheStudy(symptom: String) throws {
        // An injury flag alongside it changes nothing: the emergency page is the only one that opens.
        let responses = try Self.responses(["1.6": ["\(Self.emergencies)|\(symptom)"], "1.3": [Self.yes], "1.3a": [Self.yes]])
        #expect(try responses.screeningOutcome() == .needsAttention)
        try Self.expectShown(["5"], hidden: ["2", "3", "4", "6", "7"], in: responses)
    }

    @Test
    func severeLegWeaknessStopsTheStudy() throws {
        let responses = try Self.responses(["1.1": ["\(Self.symptoms)|leg-pain"], "7.5": ["\(Self.weakness)|severe"]])
        #expect(try responses.screeningOutcome() == .needsAttention)
        // The leg module stays open: it is where the answer was given.
        try Self.expectShown(["7", "8"], hidden: ["5", "6"], in: responses)
    }

    @Test(arguments: [
        ("1.3", "1.3a", "2"),
        ("1.4", "1.4b", "3"),
        ("1.5", "1.5c", "4")
    ])
    func aFlagOnlyAddsAdvice(question: String, followUp: String, pathway: String) throws {
        let responses = try Self.responses([question: [Self.yes], followUp: [Self.yes]])
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown([pathway, "6"], hidden: ["5"], in: responses)
    }

    @Test(arguments: ["1.3", "1.4", "1.5"])
    func aHistoryWithoutSymptomsIsNoFlag(question: String) throws {
        let responses = try Self.responses([question: [Self.yes]])
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["2", "3", "4", "5"], in: responses)
    }

    /// A follow-up answered and then closed again, by a change of mind on its question, no longer counts:
    /// the answers to a question the page does not ask stay on record.
    @Test(arguments: [
        ("1.3", "1.3a", "2"),
        ("1.4", "1.4b", "3"),
        ("1.5", "1.5c", "4")
    ])
    func aFollowUpBehindAnAnsweredNoIsNoFlag(question: String, followUp: String, pathway: String) throws {
        let responses = try Self.responses([question: [Self.answeredNo], followUp: [Self.yes]])
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: [pathway, "5"], in: responses)
    }

    /// Trouble walking because of the legs is a leg presentation: the leg module asks, and its weakness question counts.
    @Test
    func troubleWalkingOpensTheLegModule() throws {
        let responses = try Self.responses(["1.1": ["\(Self.symptoms)|trouble-walking"], "7.5": ["\(Self.weakness)|severe"]])
        #expect(try responses.screeningOutcome() == .needsAttention)
        try Self.expectShown(["7", "8"], hidden: ["5", "6"], in: responses)
    }

    /// Severe leg weakness counts only where the leg module asked about it.
    @Test
    func legWeaknessOnAPageNotShownIsNoStop() throws {
        let backOnly = try Self.responses(["7.5": ["\(Self.weakness)|severe"]])
        #expect(try backOnly.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["7", "8"], in: backOnly)
        let caudaEquina = try Self.responses([
            "1.1": ["\(Self.symptoms)|leg-pain"], "1.6": ["\(Self.emergencies)|retention"], "7.5": ["\(Self.weakness)|severe"]
        ])
        try Self.expectShown(["5"], hidden: ["7", "8"], in: caudaEquina)
    }

    @Test
    func onlyTheMostUrgentAdviceIsShown() throws {
        let allThree = try Self.responses([
            "1.3": [Self.yes], "1.3b": [Self.yes],
            "1.4": [Self.yes], "1.4a": [Self.yes],
            "1.5": [Self.yes], "1.5b": [Self.yes]
        ])
        try Self.expectShown(["2", "6"], hidden: ["3", "4", "5"], in: allThree)
        let cancerAndInfection = try Self.responses(["1.4": [Self.yes], "1.4d": [Self.yes], "1.5": [Self.yes], "1.5a": [Self.yes]])
        try Self.expectShown(["3", "6"], hidden: ["2", "4", "5"], in: cancerAndInfection)
    }
}
