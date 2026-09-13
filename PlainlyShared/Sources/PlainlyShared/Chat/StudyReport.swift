//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// periphery:ignore - These objects are used to create a JSON resprestation of the User Study Survey Report

public import Foundation
public import GroveFHIR
public import GroveLLMOpenAI // for LLMOpenAIParameters.ModelType
public import struct ModelsR4.QuestionnaireResponse


/// A report summarizing a user study session, including metadata, FHIR resources, and timeline events.
public struct StudyReport: Encodable, Sendable {
    /// The version of the ``StudyReport`` definition.
    ///
    /// Not used anywhere in the code, but included when the type is encoded, so that any downstream processing code can decode it in a resilient way, if we make changes down the road.
    private let version = 1
    private let metadata: Metadata
    private let initialQuestionnaireResponse: ModelsR4.QuestionnaireResponse?
    private let fhirResources: FHIRResources
    private let timeline: [TimelineEvent]
    
    public init(
        metadata: Metadata,
        initialQuestionnaireResponse: ModelsR4.QuestionnaireResponse?,
        fhirResources: FHIRResources,
        timeline: [TimelineEvent]
    ) {
        self.metadata = metadata
        self.initialQuestionnaireResponse = initialQuestionnaireResponse
        self.fhirResources = fhirResources
        self.timeline = timeline
    }
}


extension StudyReport {
    /// Metadata about the study session.
    public struct Metadata: Encodable, Sendable {
        public struct LLMConfig: Codable, Sendable {
            public let model: LLMOpenAIParameters.ModelType
            public init(model: LLMOpenAIParameters.ModelType) {
                self.model = model
            }
        }
        
        /// Which build of the app produced the report, so the prompts and behaviour it ran with can be traced.
        public struct App: Codable, Sendable {
            public let version: String
            public let build: String

            public init(version: String, build: String) {
                self.version = version
                self.build = build
            }

            /// The running app, as its bundle describes it.
            public static func current(bundle: Bundle = .main) -> App {
                App(
                    version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                )
            }
        }

        private let studyID: String
        private let startTime: Date
        private let endTime: Date
        private let userInfo: [String: String]
        private let llmConfig: LLMConfig
        private let app: App
        private let interactionMode: Study.InteractionMode
        
        public init(
            studyID: String,
            startTime: Date,
            endTime: Date,
            userInfo: [String: String],
            llmConfig: LLMConfig,
            app: App,
            interactionMode: Study.InteractionMode
        ) {
            self.studyID = studyID
            self.startTime = startTime
            self.endTime = endTime
            self.userInfo = userInfo
            self.llmConfig = llmConfig
            self.app = app
            self.interactionMode = interactionMode
        }
    }

    /// FHIR resources associated with the study, split into full and partial representations.
    public struct FHIRResources: Encodable, Sendable {
        private let llmRelevantResources: [FullFHIRResource]
        private let allResources: [PartialFHIRResource]
        
        public init(llmRelevantResources: [FullFHIRResource], allResources: [PartialFHIRResource]) {
            self.llmRelevantResources = llmRelevantResources
            self.allResources = allResources
        }
    }

    /// A wrapper for a full FHIR resource, delegating encoding to the underlying resource.
    public struct FullFHIRResource: Encodable, Sendable {
        private let versionedResource: GroveFHIR.FHIRResource.VersionedFHIRResource
        
        public init(_ versionedResource: GroveFHIR.FHIRResource.VersionedFHIRResource) {
            self.versionedResource = versionedResource
        }
        
        public func encode(to encoder: any Encoder) throws {
            switch versionedResource {
            case .r4(let resource):
                try resource.encode(to: encoder)
            case .dstu2(let resource):
                try resource.encode(to: encoder)
            }
        }
    }

    /// A partial representation of an FHIR resource.
    public struct PartialFHIRResource: Encodable, Sendable {
        private let id: FHIRResource.ID
        private let resourceType: String
        private let displayName: String
        private let dateDescription: String?
        private let summary: String?
        
        public init(id: FHIRResource.ID, resourceType: String, displayName: String, dateDescription: String?, summary: String?) {
            self.id = id
            self.resourceType = resourceType
            self.displayName = displayName
            self.dateDescription = dateDescription
            self.summary = summary
        }
    }

    /// Represents an event in the study timeline, either a chat message or a survey task.
    public enum TimelineEvent: Hashable, Encodable, Sendable {
        case chatMessage(ChatMessage)
        case surveyTask(SurveyTask)
        case voiceTurn(VoiceTurn)

        private enum CodingKeys: String, CodingKey {
            case type
            case data
        }

        private enum EventType: String, Hashable, Sendable {
            case chatMessage
            case surveyTask
            case voiceTurn
        }

        public struct ChatMessage: Hashable, Codable, Sendable {
            fileprivate let timestamp: Date
            private let role: String
            private let content: String
            /// Where the message's content came from, for an answer the assistant sourced.
            private let citations: [Citation]

            public init(timestamp: Date, role: String, content: String, citations: [Citation] = []) {
                self.timestamp = timestamp
                self.role = role
                self.content = content
                self.citations = citations
            }

            /// Reads a message, tolerating one written before sources were part of the report.
            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.timestamp = try container.decode(Date.self, forKey: .timestamp)
                self.role = try container.decode(String.self, forKey: .role)
                self.content = try container.decode(String.self, forKey: .content)
                self.citations = try container.decodeIfPresent([Citation].self, forKey: .citations) ?? []
            }

            /// Writes a message, leaving the key out entirely when there are no sources.
            ///
            /// Most messages in a report — every system prompt, question, tool call and tool result — can never have
            /// one, and an empty array on each of them would be noise in a file people also read by hand.
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(timestamp, forKey: .timestamp)
                try container.encode(role, forKey: .role)
                try container.encode(content, forKey: .content)
                if !citations.isEmpty {
                    try container.encode(citations, forKey: .citations)
                }
            }
        }

        public struct SurveyTask: Hashable, Encodable, Sendable {
            private let taskId: String
            private let startedAt: Date
            fileprivate let completedAt: Date
            private let duration: TimeInterval
            private let questions: [SurveyQuestion]
            
            public init(taskId: String, startedAt: Date, completedAt: Date, duration: TimeInterval, questions: [SurveyQuestion]) {
                self.taskId = taskId
                self.startedAt = startedAt
                self.completedAt = completedAt
                self.duration = duration
                self.questions = questions
            }
        }

        public struct VoiceToolCall: Hashable, Encodable, Sendable {
            private let name: String
            private let arguments: String

            public init(name: String, arguments: String) {
                self.name = name
                self.arguments = arguments
            }
        }

        /// One spoken participant turn: what was heard, what the realtime model asked for, and what came back.
        public struct VoiceTurn: Hashable, Encodable, Sendable {
            fileprivate let startedAt: Date
            private let transcript: String
            /// `transcript` when the words are the participant's own, `paraphrase` when only the model's rendering arrived.
            private let transcriptSource: String
            private let toolCall: VoiceToolCall
            private let answer: String?
            private let spokenTranscript: String?

            public init(
                startedAt: Date,
                transcript: String,
                transcriptSource: String,
                toolCall: VoiceToolCall,
                answer: String?,
                spokenTranscript: String?
            ) {
                self.startedAt = startedAt
                self.transcript = transcript
                self.transcriptSource = transcriptSource
                self.toolCall = toolCall
                self.answer = answer
                self.spokenTranscript = spokenTranscript
            }
        }

        public struct SurveyQuestion: Hashable, Encodable, Sendable {
            private let questionText: String
            private let answer: String
            private let isOptional: Bool
            
            public init(questionText: String, answer: String, isOptional: Bool) {
                self.questionText = questionText
                self.answer = answer
                self.isOptional = isOptional
            }
        }

        var timestamp: Date {
            switch self {
            case .chatMessage(let message):
                message.timestamp
            case .surveyTask(let task):
                task.completedAt
            case .voiceTurn(let turn):
                turn.startedAt
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .chatMessage(let message):
                try container.encode(EventType.chatMessage.rawValue, forKey: .type)
                try container.encode(message, forKey: .data)
            case .surveyTask(let task):
                try container.encode(EventType.surveyTask.rawValue, forKey: .type)
                try container.encode(task, forKey: .data)
            case .voiceTurn(let turn):
                try container.encode(EventType.voiceTurn.rawValue, forKey: .type)
                try container.encode(turn, forKey: .data)
            }
        }
    }
}


extension StudyReport.TimelineEvent.ChatMessage {
    /// One source an assistant message drew on.
    ///
    /// A flattened stand-in for Grove's `LLMCitation` rather than the type itself: that type carries a freshly
    /// generated `id`, which would make an otherwise identical report encode differently on every run, and its
    /// source is an enum with associated values, which encodes as a nested `{"web": {"_0": …}}` rather than as
    /// something a downstream reader can pick apart. Exactly one of `url` and `file` is ever set, so a reader
    /// tells the two kinds apart the same way the app's own sources list does.
    public struct Citation: Hashable, Codable, Sendable {
        private let title: String
        private let url: URL?
        private let file: String?

        /// - Parameters:
        ///   - title: The source's title, as the provider reported it.
        ///   - url: The page the source points at, for a source on the web.
        ///   - file: The name of the document, for a source the model was given.
        public init(title: String, url: URL?, file: String?) {
            self.title = title
            self.url = url
            self.file = file
        }
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case timestamp
        case role
        case content
        case citations
    }
}


extension StudyReport.TimelineEvent: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}
