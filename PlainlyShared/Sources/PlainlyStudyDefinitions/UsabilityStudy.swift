//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length

public import PlainlyShared


extension Study {
    /// Plainly's usability study
    public static var usabilityStudy: Study {
        Study(
            id: "edu.stanford.plainly.usabilityStudy",
            title: "Plainly User Study",
            explainer: "During this study, you’ll complete a survey about your experiences navigating the healthcare system and have the opportunity to ask the chat questions about your health.",
            llmModel: .gpt5_5,
            ragEnabled: false,
            summarizeSingleResourcePrompt: nil,
            interpretMultipleResourcesPrompt: nil,
            chatTitleConfig: .default,
            initialQuestionnaire: nil,
            tasks: [
                Task(
                    id: "Welcome",
                    title: "Welcome",
                    instructions: "Plainly will have a health summary automatically generated on the home screen. Please review this before answering any questions.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        .scale("How clear and understandable was the summary provided by the app?", options: .clarityScale)
                    ]
                ),
                Task(
                    id: "2",
                    title: nil,
                    instructions: "Ask a clarifying question about the most recent diagnosis from your last medical visit.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        .scale("How effective is this feature for interpreting and evaluating your medical information?", options: .effectivenessScale)
                    ]
                ),
                Task(
                    id: "3",
                    title: nil,
                    instructions: "Ask the app for a personalized health recommendation. Feel free to ask about any health concerns.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        .scale("How effective are these recommendations in helping you make decisions about your health?", options: .effectivenessScale)
                    ]
                ),
                Task(
                    id: "4",
                    title: nil,
                    instructions: "Before we end our session, feel free to ask the app any medical questions you might have related to your health.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        .scale("How effective was the LLM in helping to answer your health question?", options: .effectivenessScale, isOptional: true),
                        .freeText("What surprised you about the LLM's answer, either positively or negatively?", isOptional: true)
                    ]
                ),
                Task(
                    id: "5",
                    title: nil,
                    instructions: "Please feel free to ask any other questions you have. When you're done, please complete the next task.",
                    assistantMessagesLimit: nil,
                    questions: [
                        .scale("Compared to other sources of health information (e.g., websites, doctors), how do you rate the LLM's responses?", options: .comparisonScale),
                        .freeText("What were the most and least useful features of the LLM? Do you have any suggestions to share?", isOptional: true),
                        .freeText("How has the LLM impacted your ability to manage your health?", isOptional: true),
                        .netPromoterScore("On a scale of 0-10, how likely are you to recommend this tool to a friend or colleague?", range: 0...10)
                    ]
                ),
                Task(
                    id: "6",
                    title: nil,
                    instructions: "Please hit the arrow at the top of your screen to complete the final task.",
                    assistantMessagesLimit: nil,
                    questions: [
                        .scale("How easy would it be to access or obtain information about your medical condition?", options: .balancedEaseScale),
                        .scale("How frequently do you anticipate having problems learning about your medical condition because of difficulty understanding written information?", options: .frequencyOptions),
                        .scale("How confident would you be in filling out medical forms by yourself?", options: .confidentnessScale),
                        .scale("How often do you think you would have someone help you read hospital materials?", options: .frequencyOptions)
                    ]
                )
            ]
        )
    }
}
