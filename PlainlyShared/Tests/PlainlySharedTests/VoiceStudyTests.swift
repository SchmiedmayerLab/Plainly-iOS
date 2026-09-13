//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import PlainlyShared
import Testing


struct VoiceStudyTests {
    @Test
    func amendingAppendsToEveryDefault() {
        let prompts = VoicePrompts.amending(
            instructions: "Study.",
            greeting: "Hello.",
            handoff: "Back.",
            bridge: "Wait.",
            reassurance: "Still."
        )

        #expect(prompts.instructions == VoicePrompts.Defaults.instructions + "\n\nStudy.")
        #expect(prompts.greeting == VoicePrompts.Defaults.greeting + "\n\nHello.")
        #expect(prompts.handoff == VoicePrompts.Defaults.handoff + "\n\nBack.")
        #expect(prompts.bridge == VoicePrompts.Defaults.bridge + "\n\nWait.")
        #expect(prompts.reassurance == VoicePrompts.Defaults.reassurance + "\n\nStill.")
    }

    @Test
    func amendingASilencedPromptMakesTheAdditionThePrompt() {
        let prompts = VoicePrompts(greeting: nil, reassurance: nil).amended(greeting: "Hello.")

        #expect(prompts.greeting == "Hello.")
        #expect(prompts.reassurance == nil)
        #expect(VoicePrompts.default.amended() == .default)
    }

    @Test
    func sessionInstructionsAttachOnlyTheContextThereIs() {
        let prompts = VoicePrompts.default
        #expect(prompts.sessionInstructions(studyPrompt: nil) == prompts.instructions)
        #expect(prompts.sessionInstructions(studyPrompt: "", conversationSoFar: "") == prompts.instructions)

        let instructions = prompts.sessionInstructions(studyPrompt: "Explain spines.", conversationSoFar: "Participant: Hi")

        #expect(instructions.hasPrefix(prompts.instructions))
        #expect(instructions.contains("<study_prompt>\nExplain spines.\n</study_prompt>"))
        #expect(instructions.contains("<conversation>\nParticipant: Hi\n</conversation>"))
    }

    @Test
    func reportMetadataRecordsTheAppAndInteractionMode() throws {
        let metadata = StudyReport.Metadata(
            studyID: "study",
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 1),
            userInfo: [:],
            llmConfig: .init(model: .gpt4o),
            app: .init(version: "1.2", build: "34"),
            interactionMode: .voice
        )

        let json = try #require(String(data: JSONEncoder().encode(metadata), encoding: .utf8))

        #expect(json.contains(#""interactionMode":"voice""#))
        #expect(json.contains(#""version":"1.2""#))
        #expect(json.contains(#""build":"34""#))
    }
}
