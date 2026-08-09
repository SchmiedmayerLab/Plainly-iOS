//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import PlainlyStudyDefinitions
import SpeziLLMOpenAI
import Testing


struct StudyTests {
    @Test
    func initialQuestionnairePresence() {
        let studiesWithQuestionnaires = Study.allStudies.filter(\.hasInitialQuestionnaire).map(\.id)

        #expect(studiesWithQuestionnaires == [Study.spineAI.id])
    }

    /// Each study pins the model it was evaluated with; changing one silently would invalidate its results.
    @Test(arguments: [
        (Study.gynStudy.id, LLMOpenAIParameters.ModelType.gpt4o, false),
        (Study.usabilityStudy.id, .gpt5_5, false),
        (Study.languageStudy.id, .gpt5_5, false),
        (Study.spineAI.id, .gpt5_5, true)
    ])
    func inferenceConfiguration(studyId: Study.ID, model: LLMOpenAIParameters.ModelType, ragEnabled: Bool) throws {
        let study = try #require(Study.withId(studyId))

        #expect(study.llmModel == model)
        #expect(study.ragEnabled == ragEnabled)
    }

    /// Retrieval is opt-in, so a new study cannot inherit it by accident.
    @Test
    func retrievalIsOptIn() {
        #expect(Study.allStudies.filter(\.ragEnabled).map(\.id) == [Study.spineAI.id])
    }

    /// The same validation the `export-config` tool runs before writing a `UserStudyConfig.plist`.
    @Test
    func studyDefinitionsAreValid() {
        #expect(Study.validateAllStudies().isEmpty)
    }

    /// Studies are built fresh on every lookup, so they have to compare by what they define.
    @Test
    func studiesCompareByValue() throws {
        let study = try #require(Study.withId(Study.gynStudy.id))

        #expect(study == Study.gynStudy)
        #expect(Set(Study.allStudies + Study.allStudies).count == Study.allStudies.count)
    }
}
