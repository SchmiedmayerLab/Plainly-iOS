//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
public import Observation
private import os
public import SpeziFHIR
public import SpeziLLM
public import SpeziLocalStorage


private enum FHIRMultipleResourceInterpreterConstants {
    static let context = "FHIRMultipleResourceInterpreter.context"
}


/// Used to interpret multiple FHIR resources via a chat-based interface with an LLM.
///
/// This class facilitates conversations with a large language model about FHIR healthcare data.
/// It manages the conversation context, handles generating responses based on available FHIR resources,
/// and persists conversation state between sessions.
@Observable
@MainActor
public final class FHIRMultipleResourceInterpreter: Sendable {
    private static let logger = Logger(subsystem: "edu.stanford.spezi.fhir", category: "SpeziFHIRLLM")
    private static let signposter = OSSignposter(subsystem: "edu.stanford.spezi.fhir", category: "SpeziFHIRLLM")
    
    private let localStorage: LocalStorage?
    private let llmRunner: LLMRunner
    private var llmSchema: any LLMSchema
    public let fhirStore: FHIRStore
    
    private var currentGenerationTask: Task<LLMContextEntity?, any Error>?
    private var currentGenerationIdentifier = 0
    
    /// The current LLM session managing the conversation context with the language model.
    ///
    /// This property holds the active conversation session, including system prompts,
    /// user inputs, and assistant responses. Changes to this property will be reflected in the UI.
    public private(set) var llmSession: any LLMSession
    
    
    /// Initializes a new FHIR resource interpreter with the provided dependencies.
    ///
    /// This initializer sets up a new interpreter, either restoring a previous conversation
    /// from persistent storage or creating a new conversation with system prompts.
    ///
    /// - Parameters:
    ///   - localStorage: Storage provider for persisting conversation between sessions
    ///   - llmRunner: Factory for creating LLM sessions
    ///   - llmSchema: Configuration that defines how the LLM responds
    ///   - fhirStore: Provider of FHIR resources to be interpreted
    public init(
        localStorage: LocalStorage?,
        llmRunner: LLMRunner,
        llmSchema: any LLMSchema,
        fhirStore: FHIRStore
    ) {
        self.localStorage = localStorage
        self.llmRunner = llmRunner
        self.llmSchema = llmSchema
        self.fhirStore = fhirStore
        self.llmSession = llmRunner(with: llmSchema)
        
        if let storedContext: LLMContext = try? localStorage?.load(.init(FHIRMultipleResourceInterpreterConstants.context)) {
            llmSession.context = storedContext
            Self.logger.notice("Restored conversation context; contextCount=\(storedContext.count)")
        } else {
            llmSession.context = createInterpretationContext(using: .interpretMultipleResourcesDefaultPrompt)
            Self.logger.notice("Created new conversation context; contextCount=\(self.llmSession.context.count)")
        }
    }

    private static func logError(_ error: any Error, context: String, generation: Int? = nil) {
        let nsError = error as NSError
        let typeName = String(reflecting: type(of: error))
        let description = nsError.localizedDescription
        logger.error("""
            \(context, privacy: .public) failed; generation=\(generation ?? 0); type=\(typeName, privacy: .public); \
            domain=\(nsError.domain, privacy: .public); code=\(nsError.code); \
            descriptionHash=\(description, privacy: .private(mask: .hash))
            """)
    }
    
    /// Starts a new conversation by creating a fresh LLM session.
    ///
    /// This  creates an entirely new session and replaces the current one.
    public func startNewConversation(using prompt: FHIRPrompt) {
        Self.logger.notice("""
            Starting new conversation; previousContextCount=\(self.llmSession.context.count); \
            replacingGeneration=\(self.currentGenerationTask != nil)
            """)
        let newLLMSession = llmRunner(with: llmSchema)
        newLLMSession.context = createInterpretationContext(using: prompt)
        if let localStorage {
            do {
                try localStorage.delete(.init(FHIRMultipleResourceInterpreterConstants.context))
            } catch {
                Self.logError(error, context: "Deleting stored conversation context")
            }
        }
        llmSession = newLLMSession
        Self.logger.notice("New conversation ready; contextCount=\(self.llmSession.context.count)")
    }
    
    /// Generates an assistant response based on the current conversation context.
    ///
    /// - Returns: The last `LLMContextEntity` representing the completed assistant response,
    ///   or `nil` if generation was cancelled or encountered an error.
    public func generateAssistantResponse() async throws -> LLMContextEntity? {
        if currentGenerationTask != nil {
            Self.logger.warning("Replacing an existing response generation task")
        }
        currentGenerationTask?.cancel()
        currentGenerationIdentifier &+= 1
        let generationIdentifier = currentGenerationIdentifier
        Self.logger.notice("""
            Response generation scheduled; generation=\(generationIdentifier); contextCount=\(self.llmSession.context.count); \
            sessionState=\(self.llmSession.state.description, privacy: .public)
            """)
        let task = Task<LLMContextEntity?, any Error> { [weak self] in
            guard let self else {
                Self.logger.fault("Response generation lost its interpreter; generation=\(generationIdentifier)")
                return nil
            }
            return try await self.performGeneration(generationIdentifier: generationIdentifier)
        }
        currentGenerationTask = task
        let logger = Self.logger
        return try await withTaskCancellationHandler {
            defer {
                if currentGenerationIdentifier == generationIdentifier {
                    currentGenerationTask = nil
                    Self.logger.info("Cleared response generation task; generation=\(generationIdentifier)")
                } else {
                    Self.logger.info("""
                        Preserved newer response generation task; completedGeneration=\(generationIdentifier); \
                        currentGeneration=\(self.currentGenerationIdentifier)
                        """)
                }
            }
            return try await task.value
        } onCancel: {
            logger.notice("Response generation parent cancelled; generation=\(generationIdentifier)")
            task.cancel()
        }
    }

    private func performGeneration(generationIdentifier: Int) async throws -> LLMContextEntity? {
        let signpostID = Self.signposter.makeSignpostID()
        let interval = Self.signposter.beginInterval(
            "FHIRAssistantResponseGeneration",
            id: signpostID,
            "generation=\(generationIdentifier)"
        )
        defer {
            Self.signposter.endInterval("FHIRAssistantResponseGeneration", interval)
        }
        do {
            Self.logger.notice("Opening LLM response stream; generation=\(generationIdentifier)")
            let stream = try await llmSession.generate()
            var chunkCount = 0
            var byteCount = 0
            for try await token in stream {
                try Task.checkCancellation()
                if chunkCount == 0 {
                    Self.logger.notice("First LLM response chunk received; generation=\(generationIdentifier)")
                }
                chunkCount += 1
                byteCount += token.utf8.count
                llmSession.context.append(assistantOutput: token)
            }
            try Task.checkCancellation()
            Self.logger.notice("""
                LLM response stream ended; generation=\(generationIdentifier); chunks=\(chunkCount); bytes=\(byteCount); \
                contextCountBeforeCompletion=\(self.llmSession.context.count)
                """)
            llmSession.context.completeAssistantStreaming()
            if let localStorage {
                try localStorage.store(llmSession.context, for: .init(FHIRMultipleResourceInterpreterConstants.context))
                Self.logger.info(
                    "Stored updated conversation context; generation=\(generationIdentifier); contextCount=\(self.llmSession.context.count)"
                )
            }
            Self.logger.notice("""
                Response generation completed; generation=\(generationIdentifier); contextCount=\(self.llmSession.context.count); \
                hasLastMessage=\(self.llmSession.context.last != nil)
                """)
            return llmSession.context.last
        } catch is CancellationError {
            Self.logger.notice("Response generation cancelled; generation=\(generationIdentifier)")
            return nil
        } catch {
            Self.logError(error, context: "Generating assistant response", generation: generationIdentifier)
            throw error
        }
    }
    
    /// Updates the LLM schema used by the interpreter.
    ///
    /// This method changes the underlying LLM schema, which affects how future
    /// responses are generated. It creates a new session with the updated schema
    /// and initializes it with basic system prompts.
    ///
    /// - Parameter newSchema: The new schema to use for future conversations.
    ///                       This must conform to the `LLMSchema` protocol.
    ///
    /// After calling this method, any new responses will be generated using the new schema,
    /// but the conversation will start fresh with only system messages.
    public func changeLLMSchema(to newSchema: some LLMSchema, using prompt: FHIRPrompt) {
        Self.logger.notice("Changing LLM schema and resetting conversation")
        self.llmSchema = newSchema
        startNewConversation(using: prompt)
    }
    
    /// Cancels any ongoing response generation.
    ///
    /// This method immediately stops the current generation task if one is in progress.
    /// Use this when you need to interrupt response generation.
    public func cancel() {
        Self.logger.notice("Explicit response generation cancellation requested; hasTask=\(self.currentGenerationTask != nil)")
        currentGenerationTask?.cancel()
    }
    
    private func createInterpretationContext(using prompt: FHIRPrompt) -> LLMContext {
        var context = LLMContext()
        context.append(systemMessage: prompt.promptText)
        return context
    }
}
