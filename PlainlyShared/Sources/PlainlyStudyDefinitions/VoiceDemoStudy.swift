//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import PlainlyShared


extension Study {
    /// Shows off the realtime voice conversation over sample records; it carries no clinical meaning.
    public static var voiceDemo: Study {
        Study(
            id: "edu.stanford.plainly.voiceDemo",
            title: "Voice Demo",
            explainer: "Talk to Plainly about the sample health records. This demo shows the voice conversation and has no clinical purpose.",
            llmModel: .gpt5_5,
            ragEnabled: false,
            summarizeSingleResourcePrompt: nil,
            interpretMultipleResourcesPrompt: nil,
            chatTitleConfig: .studyTitle,
            initialQuestionnaire: nil,
            tasks: [
                Task(
                    id: "conversation",
                    title: nil,
                    instructions: "Ask Plainly about any of the sample records, for example a recent lab result, and follow up as you like.",
                    assistantMessagesLimit: nil,
                    questions: []
                )
            ],
            interactionMode: .voice,
            voicePrompts: .amending(
                greeting: "Also say that this is a demo over sample health records with no clinical purpose."
            )
        )
    }
}
