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


/// The SpineAI intake decides on its own, in FHIR, whether the study goes on. A new bladder, bowel or groin symptom that
/// came with new severe back or leg pain, or new dense weakness or numbness, stops it unless a spine physician has
/// already evaluated it urgently; on its own it is a symptom. An injury flag, which takes two of its three follow-ups,
/// a cancer or an infection flag only adds a page of advice.
@Suite
struct SpineAIScreeningTests {
    private static let snomed = "http://snomed.info/sct"
    private static let yes = "\(snomed)|373066001"
    private static let answeredNo = "\(snomed)|373067005"
    private static let symptoms = "https://spineai.stanford.edu/CodeSystem/primary-symptom"
    private static let emergencies = "https://spineai.stanford.edu/CodeSystem/neurologic-emergency"
    private static let weakness = "https://spineai.stanford.edu/CodeSystem/radic-weakness"
    private static let bladderSymptoms = ["retention", "bladder-bowel", "perineal-numbness"]
    private static let denseSymptoms = ["leg-weakness", "bilateral-weakness", "diffuse-numbness"]
    private static let caudaEquinaSymptoms = bladderSymptoms + denseSymptoms
    /// New, with or after new severe pain, and not yet evaluated: the answers that turn a symptom into a stop.
    private static let urgentCaudaEquina = ["1.6a": [yes], "1.6b": [yes], "1.6c": [answeredNo]]
    private static let urgentLegWeakness = ["7.5": ["\(weakness)|severe"], "7.5a": [yes], "7.5b": [answeredNo]]

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

    /// A question answered as given, with each of its follow-ups answered yes.
    private static func answers(_ question: String, _ answer: String, followUps: [String]) -> [String: [String]] {
        var answers = [question: [answer]]
        for followUp in followUps {
            answers[followUp] = [yes]
        }
        return answers
    }

    private static func section(_ linkId: String, in responses: QuestionnaireResponses) throws -> GroveQuestionnaire.Questionnaire.Section {
        try #require(responses.questionnaire.sections.first { $0.id == linkId })
    }

    /// Whether a group opens, judged by its first visible task, which carries the group's own condition.
    private static func isShown(_ linkId: String, in responses: QuestionnaireResponses) throws -> Bool {
        let first = try #require(section(linkId, in: responses).tasks.first { !$0.isHidden })
        return try ScreeningAnswers.isEnabled(first, in: responses)
    }

    private static func isAsked(_ linkId: String, in responses: QuestionnaireResponses) throws -> Bool {
        let task = try #require(responses.questionnaire.sections.flatMap(\.tasks).first { $0.id == linkId })
        return try ScreeningAnswers.isEnabled(task, in: responses)
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

    @Test(arguments: caudaEquinaSymptoms)
    func aNewSevereUnevaluatedCaudaEquinaSymptomStopsTheStudy(symptom: String) throws {
        // An injury flag alongside it changes nothing: the emergency page is the only one that opens.
        let answers = ["1.6": ["\(Self.emergencies)|\(symptom)"], "1.3": [Self.yes], "1.3a": [Self.yes], "1.3b": [Self.yes]]
        let responses = try Self.responses(answers.merging(Self.urgentCaudaEquina) { _, new in new })
        #expect(try responses.screeningOutcome() == .needsAttention)
        try Self.expectShown(["5"], hidden: ["2", "3", "4", "6", "7"], in: responses)
    }

    /// New dense weakness or numbness needs no link to the pain: the pain question is not asked.
    @Test(arguments: denseSymptoms)
    func aNewDenseSymptomStopsTheStudyWithoutThePain(symptom: String) throws {
        let responses = try Self.responses(["1.6": ["\(Self.emergencies)|\(symptom)"], "1.6a": [Self.yes], "1.6c": [Self.answeredNo]])
        #expect(try !Self.isAsked("1.6b", in: responses))
        #expect(try Self.isAsked("1.6c", in: responses))
        #expect(try responses.screeningOutcome() == .needsAttention)
        try Self.expectShown(["5"], hidden: ["6"], in: responses)
    }

    /// A new bladder, bowel or groin symptom stops only with new severe pain; without it, not even the last follow-up is asked.
    @Test(arguments: bladderSymptoms)
    func aNewBladderSymptomWithoutNewSeverePainIsNoStop(symptom: String) throws {
        let responses = try Self.responses(["1.6": ["\(Self.emergencies)|\(symptom)"], "1.6a": [Self.yes], "1.6b": [Self.answeredNo]])
        #expect(try Self.isAsked("1.6b", in: responses))
        #expect(try !Self.isAsked("1.6c", in: responses))
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["5"], in: responses)
    }

    /// A dense symptom alongside a bladder symptom stops the study even when the pain question says no.
    @Test
    func aDenseSymptomStopsAlongsideABladderSymptomWithoutPain() throws {
        let responses = try Self.responses([
            "1.6": ["\(Self.emergencies)|retention", "\(Self.emergencies)|leg-weakness"],
            "1.6a": [Self.yes], "1.6b": [Self.answeredNo], "1.6c": [Self.answeredNo]
        ])
        #expect(try responses.screeningOutcome() == .needsAttention)
    }

    /// Any of these symptoms, when it is not new, is a symptom and not a stop.
    @Test(arguments: caudaEquinaSymptoms)
    func aCaudaEquinaSymptomAloneIsNoStop(symptom: String) throws {
        let responses = try Self.responses(["1.6": ["\(Self.emergencies)|\(symptom)"], "1.6a": [Self.answeredNo]])
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["5"], in: responses)
    }

    /// Every one of the follow-ups has to point to an urgent evaluation: old, without new severe pain, or already
    /// seen by a spine physician, and the study goes on.
    @Test(arguments: [
        ["1.6a": "no"],
        ["1.6a": "yes", "1.6b": "no"],
        ["1.6a": "yes", "1.6b": "yes", "1.6c": "yes"]
    ])
    func aFollowUpAgainstUrgencyIsNoStop(followUps: [String: String]) throws {
        var answers = ["1.6": ["\(Self.emergencies)|retention", "\(Self.emergencies)|perineal-numbness"]]
        for (linkId, answer) in followUps {
            answers[linkId] = [answer == "yes" ? Self.yes : Self.answeredNo]
        }
        let responses = try Self.responses(answers)
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["5"], in: responses)
    }

    /// Follow-ups answered and then closed again, by "None of the above", no longer count.
    @Test
    func followUpsBehindNoSymptomAreNoStop() throws {
        let responses = try Self.responses(Self.urgentCaudaEquina)
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["5"], in: responses)
    }

    @Test
    func severeLegWeaknessStopsTheStudy() throws {
        let answers = ["1.1": ["\(Self.symptoms)|leg-pain"]].merging(Self.urgentLegWeakness) { _, new in new }
        let responses = try Self.responses(answers)
        #expect(try responses.screeningOutcome() == .needsAttention)
        // The leg module stays open: it is where the answer was given.
        try Self.expectShown(["7", "8"], hidden: ["5", "6"], in: responses)
    }

    /// Severe weakness that is old or already evaluated is recorded and the study goes on.
    @Test(arguments: [
        ["7.5a": "no"],
        ["7.5a": "yes", "7.5b": "yes"]
    ])
    func severeLegWeaknessAgainstUrgencyIsNoStop(followUps: [String: String]) throws {
        var answers = ["1.1": ["\(Self.symptoms)|leg-pain"], "7.5": ["\(Self.weakness)|severe"]]
        for (linkId, answer) in followUps {
            answers[linkId] = [answer == "yes" ? Self.yes : Self.answeredNo]
        }
        let responses = try Self.responses(answers)
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["7"], hidden: ["5", "8"], in: responses)
    }

    @Test(arguments: [
        ("1.3", ["1.3a", "1.3c"], "2"),
        ("1.4", ["1.4b"], "3"),
        ("1.5", ["1.5c"], "4")
    ])
    func aFlagOnlyAddsAdvice(question: String, followUps: [String], pathway: String) throws {
        let responses = try Self.responses(Self.answers(question, Self.yes, followUps: followUps))
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown([pathway, "6"], hidden: ["5"], in: responses)
    }

    /// A fracture is suspected on two of the three injury follow-ups; one alone is no flag.
    @Test(arguments: ["1.3a", "1.3b", "1.3c"])
    func oneInjuryFollowUpIsNoFlag(followUp: String) throws {
        let responses = try Self.responses(["1.3": [Self.yes], followUp: [Self.yes]])
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["2", "5"], in: responses)
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
        ("1.3", ["1.3a", "1.3c"], "2"),
        ("1.4", ["1.4b"], "3"),
        ("1.5", ["1.5c"], "4")
    ])
    func aFollowUpBehindAnAnsweredNoIsNoFlag(question: String, followUps: [String], pathway: String) throws {
        let responses = try Self.responses(Self.answers(question, Self.answeredNo, followUps: followUps))
        #expect(try responses.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: [pathway, "5"], in: responses)
    }

    /// Trouble walking because of the legs is a leg presentation: the leg module asks, and its weakness question counts.
    @Test
    func troubleWalkingOpensTheLegModule() throws {
        let walking = try Self.responses(["1.1": ["\(Self.symptoms)|trouble-walking"]])
        #expect(try walking.screeningOutcome() == .eligible, "trouble walking is a symptom, not a red flag")
        try Self.expectShown(["7"], hidden: ["5", "6", "8"], in: walking)
        let answers = ["1.1": ["\(Self.symptoms)|trouble-walking"]].merging(Self.urgentLegWeakness) { _, new in new }
        let responses = try Self.responses(answers)
        #expect(try responses.screeningOutcome() == .needsAttention)
        try Self.expectShown(["7", "8"], hidden: ["5", "6"], in: responses)
    }

    /// Severe leg weakness counts only where the leg module asked about it.
    @Test
    func legWeaknessOnAPageNotShownIsNoStop() throws {
        let backOnly = try Self.responses(Self.urgentLegWeakness)
        #expect(try backOnly.screeningOutcome() == .eligible)
        try Self.expectShown(["6"], hidden: ["7", "8"], in: backOnly)
        let answers = ["1.1": ["\(Self.symptoms)|leg-pain"], "1.6": ["\(Self.emergencies)|retention"]]
            .merging(Self.urgentCaudaEquina) { _, new in new }
            .merging(Self.urgentLegWeakness) { _, new in new }
        let caudaEquina = try Self.responses(answers)
        try Self.expectShown(["5"], hidden: ["7", "8"], in: caudaEquina)
    }

    @Test
    func onlyTheMostUrgentAdviceIsShown() throws {
        let allThree = try Self.responses([
            "1.3": [Self.yes], "1.3b": [Self.yes], "1.3c": [Self.yes],
            "1.4": [Self.yes], "1.4a": [Self.yes],
            "1.5": [Self.yes], "1.5b": [Self.yes]
        ])
        try Self.expectShown(["2", "6"], hidden: ["3", "4", "5"], in: allThree)
        let cancerAndInfection = try Self.responses(["1.4": [Self.yes], "1.4d": [Self.yes], "1.5": [Self.yes], "1.5a": [Self.yes]])
        try Self.expectShown(["3", "6"], hidden: ["2", "4", "5"], in: cancerAndInfection)
    }
}
