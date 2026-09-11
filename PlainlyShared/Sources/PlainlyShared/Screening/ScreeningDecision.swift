//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// What screening decided for one study, kept so the decision outlives the session that made it.
public struct ScreeningDecision: Codable, Hashable, Sendable {
    /// The study the decision belongs to.
    public let studyId: String
    /// The outcome.
    public let outcome: ScreeningOutcome
    /// When the questionnaire was completed.
    public let date: Date

    public init(studyId: String, outcome: ScreeningOutcome, date: Date = .now) {
        self.studyId = studyId
        self.outcome = outcome
        self.date = date
    }
}
