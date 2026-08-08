//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable redundant_string_enum_value

public import Foundation
public import struct ModelsR4.Questionnaire
public import SpeziLLMOpenAI


/// Manages a collection of survey tasks and their responses.
public final class Study: Identifiable {
    public enum ChatTitleConfig: String, Hashable, Codable, Sendable {
        case `default`
        case studyTitle
    }

    /// The Firebase function that serves chat completions unless a study opts into another one.
    public static let defaultChatFunctionName = "chat"
    
    /// The survey's unique identifier.
    public let id: String
    /// The survey's title.
    public let title: String
    /// A brief explainer detailing what the survey does.
    public let explainer: String
    /// The identifier of the model used to generate the study's chat responses.
    ///
    /// The inference backend resolves the provider and endpoint from this identifier, so it is not
    /// restricted to models served by OpenAI itself.
    public let llmModel: LLMOpenAIParameters.ModelType
    /// Whether responses should be augmented with retrieval over the study's knowledge base.
    public let ragEnabled: Bool
    /// The name of the Firebase function that generates the study's chat completions.
    ///
    /// May carry query items, e.g. `chat?verbose=true`; they are merged into the callable's name.
    public let chatFunctionName: String

    public let summarizeSingleResourcePrompt: FHIRPrompt
    public var interpretMultipleResourcesPrompt: FHIRPrompt
    
    public let chatTitleConfig: ChatTitleConfig
    
    /// Initial Questionnaire that should be asked before the user enters the chat view.
    private let _initialQuestionnaire: String?

    /// Whether the study presents an initial questionnaire before starting a session.
    public var hasInitialQuestionnaire: Bool {
        _initialQuestionnaire != nil
    }
    
    /// The tasks that make up this survey
    public private(set) var tasks: [Task]
    
    
    /// Creates a new survey.
    public init(
        id: String,
        title: String,
        explainer: String,
        llmModel: LLMOpenAIParameters.ModelType,
        ragEnabled: Bool,
        summarizeSingleResourcePrompt: FHIRPrompt?,
        interpretMultipleResourcesPrompt: FHIRPrompt?,
        chatTitleConfig: ChatTitleConfig,
        initialQuestionnaire: String?,
        tasks: [Task],
        chatFunctionName: String = Study.defaultChatFunctionName
    ) {
        self.id = id
        self.title = title
        self.explainer = explainer
        self.llmModel = llmModel
        self.ragEnabled = ragEnabled
        self.chatFunctionName = chatFunctionName
        self.summarizeSingleResourcePrompt = summarizeSingleResourcePrompt ?? .summarizeSingleFHIRResourceDefaultPrompt
        self.interpretMultipleResourcesPrompt = interpretMultipleResourcesPrompt ?? .interpretMultipleResourcesDefaultPrompt
        self.chatTitleConfig = chatTitleConfig
        self._initialQuestionnaire = initialQuestionnaire
        self.tasks = tasks
    }
    
    
    /// Resolves the initial questionnaire resource without loading or decoding it.
    public func initialQuestionnaireURL(in bundle: Bundle) throws -> URL? {
        guard let initialQuestionnaire = _initialQuestionnaire else {
            return nil
        }

        guard let url = bundle.url(forResource: initialQuestionnaire, withExtension: "json") else {
            throw NSError(domain: "edu.stanford.plainly.shared", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unable to find resource '\(initialQuestionnaire).json'"
            ])
        }
        return url
    }

    /// Loads and decodes the initial questionnaire, if one is configured for the study.
    public func initialQuestionnaire(from bundle: Bundle) throws -> Questionnaire? {
        guard let url = try initialQuestionnaireURL(in: bundle) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Questionnaire.self, from: data)
    }
}


extension Study: Hashable {
    public static func == (lhs: Study, rhs: Study) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}


extension Study {
    /// Submits an answer for a specific question in a specific task
    /// - Parameters:
    ///   - answer: The answer to submit
    ///   - taskId: The ID of the task containing the question
    ///   - questionIndex: The index of the question within the task
    /// - Throws: `StudyError` if the task or question cannot be found or the answer is invalid
    public func submitAnswer(_ answer: Task.Question.Answer, forTaskId taskId: Task.ID, questionIndex: Int) throws(StudyError) {
        guard let groupIndex = tasks.firstIndex(where: { $0.id == taskId }) else {
            throw .taskNotFound
        }
        try tasks[groupIndex].updateAnswer(answer, forQuestionIndex: questionIndex)
    }

    /// Resets all answers in the survey to unanswered
    public func resetAllAnswers() {
        tasks = tasks.map { task in
            var newTask = task
            for index in newTask.questions.indices {
                try? newTask.updateAnswer(.unanswered, forQuestionIndex: index)
            }
            return newTask
        }
    }
}


// MARK: Survey + Codable

extension Study: Codable {
    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case title = "title"
        case explainer = "explainer"
        case llmModel = "llm_model"
        case ragEnabled = "rag_enabled"
        case chatFunctionName = "chat_function_name"
        case tasks = "tasks"
        case summarizeSingleResourcePrompt = "prompt_summarize_single_resource"
        case interpretMultipleResourcesPrompt = "prompt_interpret_multiple_resources"
        case chatTitleConfig = "chat_title_config"
        case initialQuestionnaire = "initial_questionnaire"
    }
    
    public convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            explainer: try container.decode(String.self, forKey: .explainer),
            llmModel: try container.decode(LLMOpenAIParameters.ModelType.self, forKey: .llmModel),
            ragEnabled: try container.decode(Bool.self, forKey: .ragEnabled),
            summarizeSingleResourcePrompt: try container.decodeIfPresent(String.self, forKey: .summarizeSingleResourcePrompt)
                .flatMap { $0.isEmpty ? nil : FHIRPrompt(promptText: $0) },
            interpretMultipleResourcesPrompt: try container.decodeIfPresent(String.self, forKey: .interpretMultipleResourcesPrompt)
                .flatMap { $0.isEmpty ? nil : FHIRPrompt(promptText: $0) },
            chatTitleConfig: try container.decode(ChatTitleConfig.self, forKey: .chatTitleConfig),
            initialQuestionnaire: try container.decodeIfPresent(String.self, forKey: .initialQuestionnaire),
            tasks: try container.decode([Task].self, forKey: .tasks),
            chatFunctionName: try container.decodeIfPresent(String.self, forKey: .chatFunctionName)
                ?? Study.defaultChatFunctionName
        )
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(explainer, forKey: .explainer)
        try container.encode(llmModel, forKey: .llmModel)
        try container.encode(ragEnabled, forKey: .ragEnabled)
        try container.encode(chatFunctionName, forKey: .chatFunctionName)
        if summarizeSingleResourcePrompt != .summarizeSingleFHIRResourceDefaultPrompt {
            try container.encode(summarizeSingleResourcePrompt.promptText, forKey: .summarizeSingleResourcePrompt)
        } else {
            try container.encode("", forKey: .summarizeSingleResourcePrompt)
        }
        if interpretMultipleResourcesPrompt != .interpretMultipleResourcesDefaultPrompt {
            try container.encode(interpretMultipleResourcesPrompt.promptText, forKey: .interpretMultipleResourcesPrompt)
        } else {
            try container.encode("", forKey: .interpretMultipleResourcesPrompt)
        }
        try container.encode(chatTitleConfig, forKey: .chatTitleConfig)
        try container.encodeIfPresent(_initialQuestionnaire, forKey: .initialQuestionnaire)
        try container.encode(tasks, forKey: .tasks)
    }
}


extension Study.Task: Codable {
    private enum CodingKeys: String, CodingKey {
        case id = "id"
        case title = "title"
        case instructions = "instructions"
        case assistantMessagesLimit = "assistantMessagesLimit"
        case questions = "questions"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            instructions: try container.decodeIfPresent(String.self, forKey: .instructions),
            assistantMessagesLimit: try { () -> ClosedRange<Int>? in
                guard let string = try container.decodeIfPresent(String.self, forKey: .assistantMessagesLimit) else {
                    return nil
                }
                if let val = ClosedRange<Int>(plainlyStringValue: string) {
                    return val
                } else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid input '\(string)'"))
                }
            }(),
            questions: try container.decode([Question].self, forKey: .questions)
        )
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .id)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(assistantMessagesLimit?.plainlyStringValue, forKey: .assistantMessagesLimit)
        try container.encode(questions, forKey: .questions)
    }
}
