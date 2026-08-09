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
import SpeziQuestionnaire
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

    /// The closing questionnaires have no chat, so the app presents them without returning to it.
    @Test
    func gynStudyClosesWithoutChat() {
        let tasks = Study.gynStudy.tasks
        let chatlessTasks = tasks.filter { !$0.hasChat }
        let chatlessWithoutQuestions = chatlessTasks.filter(\.questions.isEmpty)

        #expect(chatlessTasks.map(\.id) == ["6", "7"])
        // A chatless task with no questions would leave the participant on an empty chat.
        #expect(chatlessWithoutQuestions.isEmpty)
        #expect(tasks.filter(\.hasChat).map(\.id) == ["0", "1", "2", "3", "4", "5"])
    }

    /// A task that limits the chat to no messages is not a chat task either.
    @Test
    func aTaskWithoutMessagesHasNoChat() {
        let questions: [Questionnaire.Task] = [.freeText("Why?")]
        let chatless = [
            Study.Task(id: "a", instructions: nil, questions: questions),
            Study.Task(id: "b", instructions: "", assistantMessagesLimit: 0...0, questions: questions)
        ]
        let chatting = [
            Study.Task(id: "c", instructions: "Ask about your labs", questions: questions),
            Study.Task(id: "d", instructions: nil, assistantMessagesLimit: 1...5, questions: questions)
        ]

        #expect(chatless.map(\.hasChat) == [false, false])
        #expect(chatting.map(\.hasChat) == [true, true])
    }

    /// The recommendation question reports the number picked, so its range stays comparable.
    @Test
    func recommendationQuestionReportsTheScore() throws {
        let questions = Study.gynStudy.tasks.flatMap(\.questions)
        let question = try #require(questions.first { $0.title.hasPrefix("On a scale of 0-10") })

        guard case let .choice(config) = question.kind.variant else {
            Issue.record("The recommendation question is no longer a choice question.")
            return
        }
        #expect(config.options.map(\.id) == (0...10).map { "\($0)" })
        #expect(config.options.first?.title == "0 (Would not recommend)")
        #expect(config.options.last?.title == "10 (Would recommend)")
    }
}
