//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Grove
import GroveLocalStorage
import Observation
import PlainlyShared


/// Keeps what each study's screening decided, on the device.
///
/// A study that stops after screening has to stay stopped: on the next launch the participant must not land
/// in the chat or be asked the questionnaire again, so the decision is stored and read back before the study
/// home shows anything.
@Observable
final class Screening: Module, DefaultInitializable, EnvironmentAccessible, @unchecked Sendable {
    private static let storageKey = LocalStorageKey<[String: ScreeningDecision]>("edu.stanford.plainly.screening.decisions")

    @ObservationIgnored @Dependency(LocalStorage.self) private var localStorage

    /// Every decision on the device, by study id.
    private(set) var decisions: [String: ScreeningDecision] = [:]

    init() {}

    func configure() {
        if FeatureFlags.resetPreferences {
            try? localStorage.delete(Self.storageKey)
        }
        do {
            decisions = try localStorage.load(Self.storageKey) ?? [:]
        } catch {
            AppDiagnostics.study.logError(error, context: "Loading the screening decisions")
        }
    }

    /// The decision for a study, if its screening has decided.
    func decision(for studyId: String) -> ScreeningDecision? {
        decisions[studyId]
    }

    /// Records what screening decided for a study, replacing an earlier decision.
    @discardableResult
    func record(_ outcome: ScreeningOutcome, for studyId: String, at date: Date = .now) throws -> ScreeningDecision {
        let decision = ScreeningDecision(studyId: studyId, outcome: outcome, date: date)
        var decisions = decisions
        decisions[studyId] = decision
        try localStorage.store(decisions, for: Self.storageKey)
        self.decisions = decisions
        return decision
    }
}
