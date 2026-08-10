//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import struct ModelsR4.Questionnaire
public import SpeziLLMOpenAI


/// The definition of a study: its tasks, the prompts that frame them, and how it is reported.
public struct Study: Identifiable, Hashable, Sendable {
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
    /// How the study's survey answers are represented in its report.
    public let reportFormat: StudyReportFormat
    /// The name of the Firebase function that generates the study's chat completions.
    ///
    /// May carry query items, e.g. `chat?verbose=true`; they are merged into the callable's name.
    public let chatFunctionName: String

    public let summarizeSingleResourcePrompt: FHIRPrompt
    public let interpretMultipleResourcesPrompt: FHIRPrompt
    
    public let chatTitleConfig: ChatTitleConfig
    
    /// Initial Questionnaire that should be asked before the user enters the chat view.
    private let _initialQuestionnaire: String?

    /// Whether the study presents an initial questionnaire before starting a session.
    public var hasInitialQuestionnaire: Bool {
        _initialQuestionnaire != nil
    }
    
    /// The tasks that make up this survey
    public let tasks: [Task]
    
    
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
        chatFunctionName: String = Study.defaultChatFunctionName,
        reportFormat: StudyReportFormat = .questionnaireResponse
    ) {
        self.id = id
        self.title = title
        self.explainer = explainer
        self.llmModel = llmModel
        self.ragEnabled = ragEnabled
        self.reportFormat = reportFormat
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
