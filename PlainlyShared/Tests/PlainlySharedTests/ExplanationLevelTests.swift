//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLM
import PlainlyShared
import PlainlyStudyDefinitions
import Testing


struct ExplanationLevelTests {
    @Test("Recording a level adds one instruction the request will carry")
    func recordsTheLevel() {
        var context = LLMContext()
        context.append(userMessage: "What does my last result mean?")

        context.setExplanationLevel(.simple)

        let systemMessages = context.filter { $0.role == .system }
        #expect(systemMessages.count == 1)
        #expect(systemMessages[0].content == ExplanationLevel.simple.instruction)
    }

    @Test("Changing the level rewrites the instruction rather than adding another")
    func rewritesInPlace() {
        var context = LLMContext()
        context.setExplanationLevel(.simple)
        let countAfterFirst = context.count

        context.setExplanationLevel(.detailed)

        // The entity count is what tells the Responses transport that the conversation it submitted still
        // holds, so a change has to leave it alone.
        #expect(context.count == countAfterFirst)
        let systemMessages = context.filter { $0.role == .system }
        #expect(systemMessages.count == 1)
        #expect(systemMessages[0].content == ExplanationLevel.detailed.instruction)
    }

    @Test("The level is recorded without disturbing the conversation")
    func leavesTheConversationAlone() {
        var context = LLMContext()
        context.append(systemMessage: "The study's own instructions.", to: .leadingSystemMessages)
        context.append(userMessage: "First question")

        context.setExplanationLevel(.balanced)

        #expect(context.filter { $0.role == .user }.map(\.content) == ["First question"])
        #expect(context.first?.content == "The study's own instructions.")
    }

    @Test("The instruction is recorded under the identifier the rewrite looks for")
    func recordedUnderItsIdentifier() {
        var context = LLMContext()
        context.setExplanationLevel(.balanced)

        #expect(context.contains { $0.id == ExplanationLevel.instructionID })
    }

    @Test("Levels ask for different things")
    func levelsDiffer() {
        let instructions = Set(ExplanationLevel.allCases.map(\.instruction))
        #expect(instructions.count == ExplanationLevel.allCases.count)
    }

    @Test("Only the study that measures comprehension offers the control")
    func onlySpineAIOffersTheControl() {
        #expect(Study.spineAI.defaultExplanationLevel == nil)
        #expect(Study.spineAI.previews.defaultExplanationLevel == .balanced)
        #expect(Study.spineAI.enablingPreviews().defaultExplanationLevel == .balanced)
        for study in [Study.languageStudy, .gynStudy, .usabilityStudy] {
            #expect(study.defaultExplanationLevel == nil, "\(study.id) offers a control it does not measure.")
        }
    }
}
