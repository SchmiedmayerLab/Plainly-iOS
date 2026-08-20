//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable missing_docs

public import GroveFHIR
public import GroveLLM
public import GroveLocalStorage


public actor FHIRResourceProcessor<Content: Codable & LosslessStringConvertible> {
    public typealias Results = [FHIRResource.ID: Content]
    
    private let localStorage: LocalStorage?
    private let llmRunner: LLMRunner
    private let storageKey: String
    /// The prompt used to summarize a FHIR resource
    private(set) var summarizationPrompt: FHIRPrompt
    
    public private(set) var results: Results = [:] {
        didSet {
            try? localStorage?.store(results, for: .init(storageKey))
        }
    }
    
    private(set) var llmSchema: any LLMSchema
    
    public init(
        localStorage: LocalStorage?,
        llmRunner: LLMRunner,
        llmSchema: any LLMSchema,
        storageKey: String,
        summarizationPrompt: FHIRPrompt = .summarizeSingleFHIRResourceDefaultPrompt
    ) {
        self.localStorage = localStorage
        self.llmRunner = llmRunner
        self.llmSchema = llmSchema
        self.storageKey = storageKey
        self.summarizationPrompt = summarizationPrompt
        self.results = (try? localStorage?.load(.init(storageKey))) ?? [:]
    }

    nonisolated static func inferenceContext(prompt: String) -> LLMContext {
        var context = LLMContext()
        context.append(systemMessage: prompt, to: .leadingSystemMessages)
        context.append(userMessage: InternalInput.resourceSummaryRequest)
        return context
    }
    
    
    public func update(llmSchema schema: any LLMSchema, summarizationPrompt: FHIRPrompt) {
        self.llmSchema = schema
        self.summarizationPrompt = summarizationPrompt
    }
    
    @discardableResult
    public func process(resource: FHIRResource, forceReload: Bool = false) async throws -> Content {
        if let result = results[resource.id], !result.description.isEmpty, !forceReload {
            return result
        }
        let prompt = summarizationPrompt.prompt(withFHIRResource: resource.jsonDescription)
        let chatStreamResult: String = try await llmRunner.oneShot(
            with: llmSchema,
            context: Self.inferenceContext(prompt: prompt)
        )
        guard let content = Content(chatStreamResult) else {
            throw FHIRResourceProcessorError.notParsableAsAString
        }
        results[resource.id] = content
        return content
    }
}
