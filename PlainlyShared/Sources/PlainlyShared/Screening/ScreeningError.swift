//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import GroveQuestionnaire


/// Why a questionnaire's outcome could not be read; an authoring mistake, never a participant's.
public enum ScreeningError: Error, Hashable, Sendable {
    /// The outcome item is not a choice over ``ScreeningOutcome`` codings.
    case outcomeIsNotAChoice(taskId: Questionnaire.Task.ID)
    /// The outcome item selected an option outside the `screening-outcome` code system.
    case unknownOutcome(optionId: String)
    /// The outcome item selected more than one option.
    case severalOutcomes
    /// The questionnaire was completed, but its outcome item never produced a value.
    case undecided(taskId: Questionnaire.Task.ID)
}
