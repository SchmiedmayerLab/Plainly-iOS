//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SpeziFHIR
public import SpeziLLM
public import SpeziLocalStorage


/// Responsible for interpreting a single FHIR resource (at a time).
@Observable
public final class SingleFHIRResourceInterpreter: Sendable {
    private let resourceProcessor: FHIRResourceProcessor<String>
    
    /// - Parameters:
    ///   - localStorage: Storage used to cache interpretations.
    ///   - llmRunner: Runner used to create the interpretation session.
    ///   - llmSchema: Schema used to generate interpretations.
    ///   - interpretationPrompt: Prompt used to interpret the resource.
    public init(
        localStorage: LocalStorage?,
        llmRunner: LLMRunner,
        llmSchema: any LLMSchema,
        interpretationPrompt: FHIRPrompt = .interpretSingleFHIRResource
    ) {
        self.resourceProcessor = FHIRResourceProcessor(
            localStorage: localStorage,
            llmRunner: llmRunner,
            llmSchema: llmSchema,
            storageKey: "FHIRResourceInterpreter.Interpretations",
            summarizationPrompt: interpretationPrompt
        )
    }
    
    
    /// Interprets a given FHIR resource. Returns a human-readable interpretation.
    ///
    /// - Parameters:
    ///   - resource: The `FHIRResource` to be interpreted.
    ///   - forceReload: A boolean value that indicates whether to reload and reprocess the resource.
    /// - Returns: An asynchronous `String` representing the interpretation of the resource.
    @discardableResult
    public func interpret(resource: FHIRResource, forceReload: Bool = false) async throws -> String {
        try await resourceProcessor.process(
            resource: resource,
            forceReload: forceReload
        )
    }
    
    /// Retrieve the cached interpretation of a given FHIR resource. Returns a human-readable interpretation or `nil` if it is not present.
    ///
    /// - Parameter resource: The resource where the cached interpretation should be loaded from.
    /// - Returns: The cached interpretation. Returns `nil` if the resource is not present.
    public func cachedInterpretation(
        isolation: isolated (any Actor)? = #isolation,
        forResource resource: FHIRResource
    ) async -> String? {
        await resourceProcessor.results[resource.id]
    }
    
    /// Adjust the LLM schema and prompt used by the interpreter.
    ///
    /// - Parameters:
    ///    - schema: The `LLMSchema` to use.
    ///    - interpretationPrompt: The prompt used to interpret the resource.
    public func update(llmSchema schema: any LLMSchema, interpretationPrompt: FHIRPrompt) async {
        await resourceProcessor.update(llmSchema: schema, summarizationPrompt: interpretationPrompt)
    }
}
