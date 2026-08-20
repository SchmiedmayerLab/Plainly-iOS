//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import PlainlyShared


/// One participant's run of a ``Study``.
///
/// A reference type on purpose: the chat view model and the intake questionnaire both write into the
/// session that ``FHIRInterpretationModule`` reads back when it rebuilds its schemas.
final class InProgressStudy: Identifiable {
    /// The study being run, which stays fixed for the session.
    let study: Study
    /// Additional key-value pairs associated with this particular study session (e.g., a participant id).
    let userInfo: [String: String]
    /// A summary of the initial questionnaire, appended to the study's prompt for this session only.
    @MainActor var questionnaireSummary: String?
    /// The responses collected for each task of this session.
    @MainActor var responses: [Study.Task.ID: QuestionnaireResponses] = [:]
    
    var id: some Hashable {
        ObjectIdentifier(self)
    }
    
    init(study: Study, userInfo: [String: String]) {
        self.study = study
        self.userInfo = userInfo
    }
}
