//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveFHIR
import GroveFoundation
import GroveLLM
import GroveLLMOpenAI
import GroveLocalStorage
import PlainlyShared
import SwiftUI


@Observable
final class FHIRInterpretationModule: Module, EnvironmentAccessible, @unchecked Sendable {
    @ObservationIgnored @MainActor @Dependency(LocalStorage.self) private var localStorage
    @ObservationIgnored @MainActor @Dependency(LLMRunner.self) private var llmRunner
    @ObservationIgnored @MainActor @Dependency(FHIRStore.self) private var fhirStore
    
    @ObservationIgnored @MainActor @Model private(set) var resourceSummarizer: FHIRResourceSummarizer
    @ObservationIgnored @MainActor @Model private(set) var singleResourceInterpreter: SingleFHIRResourceInterpreter
    @ObservationIgnored @MainActor @Model private(set) var multipleResourceInterpreter: FHIRMultipleResourceInterpreter
    
    @MainActor private var resourceLimit: Int {
        LocalPreferencesStore.standard[.resourceLimit]
    }

    @MainActor var currentStudy: InProgressStudy?

    /// Counts the conversations this module has started.
    ///
    /// A schema update replaces the chat's session and starts its conversation over. Observers need to
    /// know that happened, and cannot tell from the session itself: a replacement can be allocated at the
    /// address the one it replaced just freed, so object identity compares equal across the swap.
    @MainActor private(set) var conversationGeneration = 0

    /// Whether the participant has said anything in the study chat yet.
    ///
    /// The opening turn is Plainly's own input, so it does not count: retrieval, and anything else that
    /// serves a question, has nothing to serve until the participant has asked one.
    @MainActor var hasParticipantInput: Bool {
        multipleResourceInterpreter.llmSession.context.contains(where: \.isParticipantInput)
    }

    @ObservationIgnored private var schemaUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var schemaUpdateGeneration = 0
    @ObservationIgnored @MainActor private var appliedSchemaInputs: SchemaInputs?

    /// The model requested from the Firebase chat function, as pinned by the active study.
    @MainActor private var llmModel: LLMOpenAIParameters.ModelType {
        currentStudy?.study.inferenceModel ?? .gpt5_5
    }

    @MainActor private var singleResourceSchema: LLMOpenAISchema {
        LLMOpenAISchema(parameters: .init(modelType: llmModel), modelParameters: .deterministic(for: llmModel))
    }

    @MainActor private var multipleResourceSchema: LLMOpenAISchema {
        LLMOpenAISchema(
            parameters: .init(modelType: llmModel),
            modelParameters: .deterministic(for: llmModel),
            injectIntoContext: true,
            generatesImages: currentStudy?.study.generatesImages ?? false
        ) {
            FHIRGetResourceLLMTool(
                fhirStore: self.fhirStore,
                resourceSummarizer: self.resourceSummarizer,
                resourceCountLimit: resourceLimit,
                forceSummaryReload: FeatureFlags.firebaseMockScenario == .responseToolCall
            )
        }
    }


    /// The study's interpretation prompt, carrying the participant's questionnaire summary where there is one.
    @MainActor private var multipleResourcePrompt: FHIRPrompt {
        currentStudy.map { inProgressStudy -> FHIRPrompt in
            let prompt = inProgressStudy.study.interpretMultipleResourcesPrompt
            guard let summary = inProgressStudy.questionnaireSummary else {
                return prompt
            }
            return FHIRPrompt(promptText: prompt.promptText + "\n\nInitial User Questionnaire Summary:\n" + summary)
        } ?? .interpretMultipleResourcesDefaultPrompt
    }

    nonisolated init() {}


    @MainActor
    func configure() {
        resourceSummarizer = FHIRResourceSummarizer(
            localStorage: localStorage,
            llmRunner: llmRunner,
            llmSchema: singleResourceSchema
        )
        singleResourceInterpreter = SingleFHIRResourceInterpreter(
            localStorage: localStorage,
            llmRunner: llmRunner,
            llmSchema: singleResourceSchema,
            interpretationPrompt: .interpretSingleFHIRResource
        )
        multipleResourceInterpreter = FHIRMultipleResourceInterpreter(
            localStorage: localStorage,
            llmRunner: llmRunner,
            llmSchema: multipleResourceSchema,
            fhirStore: fhirStore
        )
    }
    
    
    /// Throws away the conversation and starts the study's next one from its instructions alone.
    ///
    /// The interpreter outlives any one presentation of the chat, so leaving its session in place is what let a
    /// discarded conversation reappear. A new session also drops the response the gateway is holding, which the
    /// next turn would otherwise continue from.
    @MainActor
    func startNewConversation() {
        multipleResourceInterpreter.startNewConversation(using: multipleResourcePrompt)
    }

    /// Immediately updates the schemas used by the interpretation module.
    @MainActor
    func updateSchemas() async {
        schemaUpdateTask?.cancel()
        schemaUpdateTask = nil
        schemaUpdateGeneration &+= 1
        await applySchemas(generation: schemaUpdateGeneration)
    }

    @MainActor
    private func applySchemas(generation: Int) async {
        guard isCurrentSchemaUpdate(generation) else {
            return
        }
        let singleResourceSchema = self.singleResourceSchema
        let multipleResourceSchema = self.multipleResourceSchema
        let summarizePrompt = currentStudy?.study.summarizeSingleResourcePrompt ?? .summarizeSingleFHIRResourceDefaultPrompt
        let multipleResourcePrompt = self.multipleResourcePrompt
        await resourceSummarizer.update(llmSchema: singleResourceSchema, summarizationPrompt: summarizePrompt)
        guard isCurrentSchemaUpdate(generation) else {
            return
        }
        await singleResourceInterpreter.update(llmSchema: singleResourceSchema, interpretationPrompt: .interpretSingleFHIRResource)
        guard isCurrentSchemaUpdate(generation) else {
            return
        }
        // Only the participant's own conversation is restarted by a schema change, so it is the one that
        // has to be left alone when the schema would come out the same.
        let inputs = SchemaInputs(
            model: llmModel,
            resourceLimit: resourceLimit,
            resourceIdentifiers: Set(fhirStore.allResourcesFunctionCallIdentifier),
            summarizePrompt: summarizePrompt.promptText,
            interpretationPrompt: multipleResourcePrompt.promptText
        )
        guard inputs != appliedSchemaInputs else {
            return
        }
        appliedSchemaInputs = inputs
        multipleResourceInterpreter.changeLLMSchema(
            to: multipleResourceSchema,
            using: multipleResourcePrompt
        )
        conversationGeneration &+= 1
    }

    @MainActor
    private func isCurrentSchemaUpdate(_ generation: Int) -> Bool {
        !Task.isCancelled && schemaUpdateGeneration == generation
    }
}


extension FHIRInterpretationModule {
    /// Everything the interpretation schemas are built from.
    ///
    /// Applying a schema restarts the participant's conversation, so an update that would rebuild the same
    /// schema has to be recognised as one and skipped: two updates race whenever a study is opened — one
    /// from the home screen appearing, one from the session being started — and the loser used to wipe the
    /// answer the participant was already reading.
    fileprivate struct SchemaInputs: Equatable {
        // The stored values are read only through the synthesized Equatable conformance.
        // periphery:ignore
        let model: LLMOpenAIParameters.ModelType
        // periphery:ignore
        let resourceLimit: Int
        // periphery:ignore
        let resourceIdentifiers: Set<String>
        // periphery:ignore
        let summarizePrompt: String
        // periphery:ignore
        let interpretationPrompt: String
    }
}
