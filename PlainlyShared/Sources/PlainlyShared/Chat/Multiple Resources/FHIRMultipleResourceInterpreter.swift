//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
public import GroveFHIR
public import GroveLLM
public import GroveLocalStorage
public import Observation
private import os


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
    private static let logger = Logger(subsystem: "edu.stanford.plainly.fhir", category: "PlainlyFHIRLLM")
    
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
        } else {
            llmSession.context = createInterpretationContext(using: .interpretMultipleResourcesDefaultPrompt)
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
        if currentGenerationTask != nil {
            currentGenerationIdentifier &+= 1
            currentGenerationTask?.cancel()
            currentGenerationTask = nil
        }
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
    }
    
    /// Generates an assistant response based on the current conversation context.
    ///
    /// - Returns: The last `LLMContextEntity` representing the completed assistant response,
    ///   or `nil` if generation was cancelled or encountered an error.
    public func generateAssistantResponse() async throws -> LLMContextEntity? {
        currentGenerationTask?.cancel()
        currentGenerationIdentifier &+= 1
        let generationIdentifier = currentGenerationIdentifier
        let task = Task<LLMContextEntity?, any Error> { [weak self] in
            guard let self else {
                return nil
            }
            return try await self.performGeneration(generationIdentifier: generationIdentifier)
        }
        currentGenerationTask = task
        return try await withTaskCancellationHandler {
            defer {
                if currentGenerationIdentifier == generationIdentifier {
                    currentGenerationTask = nil
                }
            }
            return try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performGeneration(generationIdentifier: Int) async throws -> LLMContextEntity? {
        do {
            let stream = try await llmSession.generate()
            for try await _ in stream {
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            if let localStorage {
                try localStorage.store(llmSession.context, for: .init(FHIRMultipleResourceInterpreterConstants.context))
            }
            return llmSession.context.last
        } catch is CancellationError {
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
        self.llmSchema = newSchema
        startNewConversation(using: prompt)
    }
    
    /// Cancels any ongoing response generation.
    ///
    /// This method immediately stops the current generation task if one is in progress.
    /// Use this when you need to interrupt response generation.
    public func cancel() {
        currentGenerationTask?.cancel()
    }
    
    private func createInterpretationContext(using prompt: FHIRPrompt) -> LLMContext {
        var context = LLMContext()
        context.append(systemMessage: prompt.promptText, to: .leadingSystemMessages)
        return context
    }
}
