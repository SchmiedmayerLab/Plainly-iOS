//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveQuestionnaire


/// What a study's screening questionnaire decided about a participant.
///
/// The three codes form the `screening-outcome` code system under ``PlainlyFHIR``. A questionnaire computes one
/// of them into a hidden item tagged with ``itemCode``, and ``GroveQuestionnaire/QuestionnaireResponses/screeningOutcome()``
/// reads it back, so each study keeps its own rules in FHIR and the app only learns the result.
public enum ScreeningOutcome: String, CaseIterable, Codable, Hashable, Sendable {
    /// The participant takes part.
    case eligible
    /// The study is not for this participant.
    case ineligible
    /// The participant's answers need a clinician's attention before the study can go on.
    case needsAttention = "needs-attention"
}


extension ScreeningOutcome {
    /// The code system the outcome codes belong to.
    public static let codeSystem = PlainlyFHIR.codeSystem("screening-outcome")

    /// The `item.code` that marks the questionnaire item carrying the outcome.
    public static let itemCode = Questionnaire.Task.Code(
        system: PlainlyFHIR.codeSystem("questionnaire-item"),
        code: "screening-outcome",
        display: "Screening outcome"
    )

    /// The outcome as an answer option's coding.
    public var coding: Questionnaire.Task.Kind.ChoiceConfig.Option.FHIRCoding {
        .init(system: Self.codeSystem, code: rawValue)
    }

    /// Whether the study stops here instead of going on.
    public var stopsTheStudy: Bool {
        self != .eligible
    }

    /// The outcome a coding stands for, if it is one of ours.
    public init?(coding: Questionnaire.Task.Kind.ChoiceConfig.Option.FHIRCoding) {
        guard coding.system == Self.codeSystem else {
            return nil
        }
        self.init(rawValue: coding.code)
    }
}


extension Questionnaire {
    /// The task carrying the screening outcome, tagged with ``ScreeningOutcome/itemCode``.
    ///
    /// `nil` for a questionnaire that does not screen.
    public var screeningOutcomeTask: Task? {
        sections.lazy.flatMap(\.tasks).first { task in
            task.codes.contains { $0.system == ScreeningOutcome.itemCode.system && $0.code == ScreeningOutcome.itemCode.code }
        }
    }
}


extension QuestionnaireResponses {
    /// What the screening decided.
    ///
    /// `nil` while the questionnaire has no outcome task or the task has not produced a value yet, which is
    /// the case until the answers the outcome's expression reads have been given.
    ///
    /// - Throws: ``ScreeningError`` when the outcome task holds something other than one of the
    ///   ``ScreeningOutcome`` codings.
    public func screeningOutcome() throws(ScreeningError) -> ScreeningOutcome? {
        guard let task = questionnaire.screeningOutcomeTask else {
            return nil
        }
        guard case .choice(let config) = task.kind.variant else {
            throw .outcomeIsNotAChoice(taskId: task.id)
        }
        guard case .choice(let choice) = responses[task.id].value else {
            return nil
        }
        let selected = Array(choice.selectedOptions)
        guard let optionId = selected.first else {
            return nil
        }
        guard selected.count == 1 else {
            throw .severalOutcomes
        }
        guard let coding = config.options.first(where: { $0.id == optionId })?.fhirCoding,
              let outcome = ScreeningOutcome(coding: coding) else {
            throw .unknownOutcome(optionId: optionId)
        }
        return outcome
    }
}
