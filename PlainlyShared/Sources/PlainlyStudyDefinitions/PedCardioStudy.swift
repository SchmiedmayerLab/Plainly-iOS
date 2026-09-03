//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable line_length

import GroveQuestionnaire
public import PlainlyShared


extension Study {
    /// Plainly's pediatric cardiology study
    public static var pedCardioStudy: Study {
        let effectivenessQuestion: Questionnaire.Task = .scale(
            "How effective was the LLM in helping to answer your questions concerning your child’s health?",
            options: .effectivenessScale
        )
        return Study(
            id: "edu.stanford.plainly.pedCardioStudy",
            title: "Plainly Pediatric Cardiology Study",
            explainer: "Welcome and thank you for participating in our study assessing the health literacy in parents of pediatric cardiology patients",
            llmModel: .gpt5_5,
            ragEnabled: false,
            summarizeSingleResourcePrompt: nil,
            interpretMultipleResourcesPrompt: nil,
            chatTitleConfig: .studyTitle,
            initialQuestionnaire: nil,
            tasks: [
                Task(
                    id: "0",
                    title: nil,
                    instructions: "Ask a clarifying question about the most recent diagnosis from your last medical visit or any other questions you might have regarding your health?",
                    assistantMessagesLimit: 2...5,
                    questions: [
                        effectivenessQuestion
                    ]
                ),
                Task(
                    id: "1",
                    title: nil,
                    instructions: "Ask if the patient is allowed to play competitive sports or participate in gym class.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        effectivenessQuestion
                    ]
                ),
                Task(
                    id: "2",
                    title: nil,
                    instructions: "Ask the app for a personalized health recommendation.",
                    assistantMessagesLimit: 1...5,
                    questions: [
                        effectivenessQuestion
                    ]
                ),
                Task(
                    id: "3",
                    title: nil,
                    instructions: "Before we end our session, feel free to ask the app any medical questions you might have related to your health",
                    assistantMessagesLimit: 1...10,
                    questions: [effectivenessQuestion] + sessionFeedbackQuestions
                ),
                Task(
                    id: "4",
                    title: nil,
                    instructions: nil,
                    assistantMessagesLimit: nil,
                    questions: futureUseQuestions
                ),
                Task(
                    id: "5",
                    title: nil,
                    instructions: nil,
                    assistantMessagesLimit: nil,
                    questions: postInterventionQuestions
                )
            ]
        )
    }
}


private let sessionFeedbackQuestions: [Questionnaire.Task] = [
    .freeText(
        "What surprised you about the LLM’s answer, either positively or negatively",
        isOptional: true
    ),
    .scale(
        "Compared to other sources of health information (e.g. websites, doctors), how do you rate the LLM’s responses?",
        options: .comparisonScale
    ),
    .freeText(
        "What were the most and least useful features of the LLM? Do you have any suggestions to share?",
        isOptional: true
    ),
    .freeText(
        "How has the LLM impacted your ability to manage your child’s health?"
    ),
    .scale(
        "On a scale of 0-10 how likely are you to recommend this tool to a friend, colleague or other parents in general?",
        range: 0...10,
        labels: [0: "Would not recommend", 10: "Would recommend"]
    )
]


private let futureUseQuestions: [Questionnaire.Task] = [
    .instructional(
        "In the future if you had Plainly available…"
    ),
    .scale(
        "How easy would it be to access or obtain information about your child’s medical condition?",
        options: .balancedEaseScale
    ),
    .scale(
        "How frequently do you anticipate having problems learning about your child’s medical condition because of difficulty understanding written information?",
        options: .frequencyOptions
    ),
    .scale(
        "How confident would you be in filling out medical forms for your child by yourself?",
        options: .confidentnessScale
    ),
    .scale(
        "How often do you think you would have someone help you read hospital materials?",
        options: .frequencyOptions
    ),
    .scale(
        "How often would you turn to Plainly with small questions before reaching out to a healthcare professional?",
        options: .frequencyOptions
    )
]


private let postInterventionQuestions: [Questionnaire.Task] = [
    .instructional(
        """
        Please complete the survey below.
        Thank you!

        Below are some statements that people sometimes make when they talk about their health. Please indicate how much you agree or disagree with each statement as it applies to you personally by circling your answer. Your answers should be what is true for you and not just what you think others want you to say.

        If the statement does not apply to you, select N/A. (All questions are assessed with Always, Often, Sometimes, Never)

        Please answer these questions based on how you feel **with access to an application** like Plainly.
        """
    ),
    .scale(
        "When all is said and done, I am the person who is responsible for taking care of my / my child’s health",
        options: .frequencyOptions
    ),
    .scale(
        "Taking an active role in my/ my child’s health care is the most important thing that affects my health and ability to function",
        options: .frequencyOptions
    ),
    .scale(
        "I know what each of my/ my child’s prescribed medications do and what the major or common side effects are",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I can tell my/ my child’s health care provider/ doctor concerns I have even when he or she does not ask",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I can tell whether I/ my child need to go get medical care to go to the doctor or whether I can take care of a health problem",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident I can help prevent or reduce problems associated with my/ my child’s health",
        options: .frequencyOptions
    ),
    .scale(
        "I know the lifestyle changes like diet and exercise that are recommended for my/ my child’s health condition",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I/ my child can follow through on medical treatments I/ my child may need to do at home",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I can take actions that will help prevent or minimize some symptoms or problems associated with my/ my child’s health condition",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I/ my child can follow through on medical recommendations my/ my child’s health care provider makes, such as changing my diet or doing regular exercise",
        options: .frequencyOptions
    ),
    .scale(
        "I understand the nature and causes of my/ my child’s health condition(s)",
        options: .frequencyOptions
    ),
    .scale(
        "I know the different medical treatment options available for my/ my child’s health condition",
        options: .frequencyOptions
    ),
    .scale(
        "I have / My child has been able to maintain (keep up with) lifestyle changes that I have/ my child has made for my/ my child’s health, like eating right or exercising",
        options: .frequencyOptions
    ),
    .scale(
        "I know how to prevent further problems with my/ my child’s health",
        options: .frequencyOptions
    ),
    .scale(
        "I know about the self-treatments for my/ my child’s health condition",
        options: .frequencyOptions
    ),
    .scale(
        "I have made the changes in my/ my child’s lifestyle like diet and exercise that are recommended for my/ my child’s health condition",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident I can figure out solutions when new problems arise with my/ my child’s health",
        options: .frequencyOptions
    ),
    .scale(
        "I am able to handle symptoms of my/ my child’s health condition on my own at home",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident that I/ my child can maintain lifestyle changes, like eating right and exercising, even during times of stress",
        options: .frequencyOptions
    ),
    .scale(
        "I am able to handle problems of my/ my child’s health condition on my own at home",
        options: .frequencyOptions
    ),
    .scale(
        "I am confident I can keep my/ my child’s health problems from interfering with the things I/ my child want(s) to do",
        options: .frequencyOptions
    ),
    .scale(
        "Maintaining the lifestyle changes that are recommended for my/ my child’s health condition is too hard on a daily basis",
        options: .frequencyOptions
    ),
    .scale(
        "I understand the trajectory of my child’s condition and why they need lifelong cardiology care.",
        options: .frequencyOptions
    ),
    .scale(
        "I know what symptoms for which I should call my child’s cardiologist immediately.",
        options: .frequencyOptions
    ),
    .scale(
        "I understand why my child needs or needed surgery to correct their heart lesion",
        options: .frequencyOptions
    ),
    .scale(
        "I understand what future surgeries/interventions, if any, may be required.",
        options: .frequencyOptions
    ),
    .scale(
        #"I now find the language and abbreviations (e.g., "VSD," "echo," "cath") used in my child's medical chart easier to navigate"#,
        options: .frequencyOptions
    ),
    .scale(
        "I can confidently describe my child’s heart lesion",
        options: .frequencyOptions
    )
]
