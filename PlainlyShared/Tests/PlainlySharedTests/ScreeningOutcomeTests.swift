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


@Suite
struct ScreeningOutcomeTests {
    private static let symptoms = "https://example.org/CodeSystem/symptoms"

    /// A questionnaire that screens on one symptom question: chest pain needs attention, a cough makes the
    /// participant ineligible, anything else lets them take part. A second group only opens for the eligible.
    private static let screeningFixture = """
        {
          "resourceType": "Questionnaire",
          "id": "screening-test",
          "status": "active",
          "item": [
            {
              "linkId": "intake",
              "type": "group",
              "text": "Intake",
              "item": [
                {
                  "linkId": "symptoms",
                  "type": "choice",
                  "text": "Which of these do you have?",
                  "answerOption": [
                    { "valueCoding": { "system": "https://example.org/CodeSystem/symptoms", "code": "chest-pain" } },
                    { "valueCoding": { "system": "https://example.org/CodeSystem/symptoms", "code": "cough" } },
                    { "valueCoding": { "system": "https://example.org/CodeSystem/symptoms", "code": "none" } }
                  ]
                },
                {
                  "linkId": "screening-outcome",
                  "type": "choice",
                  "code": [{ "system": "https://plainly.stanford.edu/fhir/CodeSystem/questionnaire-item", "code": "screening-outcome" }],
                  "extension": [
                    { "url": "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden", "valueBoolean": true },
                    {
                      "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                      "valueExpression": {
                        "language": "text/fhirpath",
                        "expression": "iif(%resource.descendants().where(linkId='symptoms').answer.value.where(code='chest-pain').exists(), 'needs-attention', iif(%resource.descendants().where(linkId='symptoms').answer.value.where(code='cough').exists(), 'ineligible', 'eligible'))"
                      }
                    }
                  ],
                  "answerOption": [
                    { "valueCoding": { "system": "https://plainly.stanford.edu/fhir/CodeSystem/screening-outcome", "code": "eligible" } },
                    { "valueCoding": { "system": "https://plainly.stanford.edu/fhir/CodeSystem/screening-outcome", "code": "ineligible" } },
                    { "valueCoding": { "system": "https://plainly.stanford.edu/fhir/CodeSystem/screening-outcome", "code": "needs-attention" } }
                  ]
                }
              ]
            },
            {
              "linkId": "study",
              "type": "group",
              "text": "Study",
              "extension": [
                {
                  "url": "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
                  "valueExpression": {
                    "language": "text/fhirpath",
                    "expression": "%resource.descendants().where(linkId='screening-outcome').answer.value.code = 'eligible'"
                  }
                }
              ],
              "item": [
                { "linkId": "study.1", "type": "boolean", "text": "Do you agree to take part?" }
              ]
            }
          ]
        }
        """

    private static func screeningQuestionnaire() throws -> GroveQuestionnaire.Questionnaire {
        let resource = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(screeningFixture.utf8))
        return try GroveQuestionnaire.Questionnaire(resource)
    }

    private static func responses(selecting code: String?) throws -> QuestionnaireResponses {
        try ScreeningAnswers.responses(
            to: screeningQuestionnaire(),
            choosing: code.map { ["symptoms": ["https://example.org/CodeSystem/symptoms|\($0)"]] } ?? [:]
        )
    }

    @Test
    func findsTheTaggedOutcomeTask() throws {
        let questionnaire = try Self.screeningQuestionnaire()
        let task = try #require(questionnaire.screeningOutcomeTask)
        #expect(task.id == "screening-outcome")
        #expect(task.isHidden)
    }

    @Test(arguments: [("chest-pain", ScreeningOutcome.needsAttention), ("cough", .ineligible), ("none", .eligible)])
    func readsTheOutcomeTheQuestionnaireComputed(code: String, outcome: ScreeningOutcome) throws {
        let responses = try Self.responses(selecting: code)
        #expect(try responses.screeningOutcome() == outcome)
    }

    @Test
    func decidesEligibleBeforeAnyAnswerIsGiven() throws {
        // The expression's conditions are empty without answers, so the default branch applies.
        let responses = try Self.responses(selecting: nil)
        #expect(try responses.screeningOutcome() == .eligible)
    }

    @Test
    func gatesLaterGroupsOnTheOutcome() throws {
        let stopped = try Self.responses(selecting: "chest-pain")
        let studyTask = try #require(stopped.questionnaire.sections.last?.tasks.first)
        #expect(try !ScreeningAnswers.isEnabled(studyTask, in: stopped))

        let eligible = try Self.responses(selecting: "none")
        #expect(try ScreeningAnswers.isEnabled(studyTask, in: eligible))
    }

    @Test
    func aQuestionnaireWithoutAnOutcomeHasNone() throws {
        let json = """
        { "resourceType": "Questionnaire", "id": "plain-test", "status": "active", "item": [
          { "linkId": "g", "type": "group", "text": "G", "item": [{ "linkId": "q", "type": "boolean", "text": "Q" }] }
        ] }
        """
        let questionnaire = try GroveQuestionnaire.Questionnaire(JSONDecoder().decode(ModelsR4.Questionnaire.self, from: Data(json.utf8)))
        #expect(questionnaire.screeningOutcomeTask == nil)
        #expect(try ScreeningAnswers.responses(to: questionnaire, choosing: [:]).screeningOutcome() == nil)
    }

    @Test
    func outcomesMapToTheirCodings() throws {
        for outcome in ScreeningOutcome.allCases {
            #expect(outcome.coding.system == ScreeningOutcome.codeSystem)
            #expect(outcome.coding.code == outcome.rawValue)
            #expect(ScreeningOutcome(coding: outcome.coding) == outcome)
        }
        let foreign = try #require(URL(string: Self.symptoms))
        #expect(ScreeningOutcome(coding: .init(system: foreign, code: "eligible")) == nil)
        #expect(!ScreeningOutcome.eligible.stopsTheStudy)
        #expect(ScreeningOutcome.ineligible.stopsTheStudy)
        #expect(ScreeningOutcome.needsAttention.stopsTheStudy)
        #expect(ScreeningOutcome.codeSystem.absoluteString == "https://plainly.stanford.edu/fhir/CodeSystem/screening-outcome")
    }
}
