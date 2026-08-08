//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import PlainlyStudyDefinitions
import Testing


struct StudyTests {
    @Test
    func initialQuestionnairePresence() {
        let studiesWithQuestionnaires = Study.allStudies.filter(\.hasInitialQuestionnaire).map(\.id)

        #expect(studiesWithQuestionnaires == [Study.spineAI.id])
    }
}
