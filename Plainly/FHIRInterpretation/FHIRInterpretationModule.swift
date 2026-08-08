//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import Spezi
import SpeziFHIR
import SpeziFoundation
import SpeziLLM
import SpeziLLMOpenAI
import SpeziLocalStorage
import SwiftUI


@Observable
final class FHIRInterpretationModule: Module, EnvironmentAccessible, @unchecked Sendable {
    @ObservationIgnored @MainActor @Dependency(LocalStorage.self) private var localStorage
    @ObservationIgnored @MainActor @Dependency(LLMRunner.self) private var llmRunner
    @ObservationIgnored @MainActor @Dependency(FHIRStore.self) private var fhirStore
    
    @ObservationIgnored @MainActor @Model private(set) var resourceSummarizer: FHIRResourceSummarizer
    @ObservationIgnored @MainActor @Model private(set) var singleResourceInterpreter: SingleFHIRResourceInterpreter
    @ObservationIgnored @MainActor @Model private(set) var multipleResourceInterpreter: FHIRMultipleResourceInterpreter
    
    @MainActor var openAIModel: LLMOpenAIParameters.ModelType {
        LocalPreferencesStore.standard[.openAIModel]
    }
    @MainActor var openAIModelTemperature: Double {
        LocalPreferencesStore.standard[.openAIModelTemperature]
    }
    @MainActor private var resourceLimit: Int {
        LocalPreferencesStore.standard[.resourceLimit]
    }
    
    @MainActor var currentStudy: InProgressStudy?
    
    @ObservationIgnored private var schemaUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var schemaUpdateGeneration = 0
    
    @MainActor private var singleResourceSchema: LLMOpenAISchema {
        LLMOpenAISchema(
            parameters: .init(modelType: openAIModel),
            modelParameters: .init(temperature: openAIModelTemperature)
        )
    }
    
    @MainActor private var multipleResourceSchema: LLMOpenAISchema {
        LLMOpenAISchema(
            parameters: .init(modelType: openAIModel),
            modelParameters: .init(temperature: openAIModelTemperature)
        ) {
            FHIRGetResourceLLMFunction(
                fhirStore: self.fhirStore,
                resourceSummarizer: self.resourceSummarizer,
                resourceCountLimit: resourceLimit
            )
        }
    }
    
    
    nonisolated init() {}
    
    
    @MainActor
    func configure() {
        AppDiagnostics.configuration.notice("FHIR interpretation module configuration started")
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
        AppDiagnostics.configuration.notice("FHIR interpretation module configuration completed")
    }
    
    
    /// Schedules a schema update, coalescing rapid preference changes into a single update.
    @MainActor
    func scheduleSchemaUpdate() {
        if schemaUpdateTask != nil {
            AppDiagnostics.configuration.info("Replacing a pending schema update task")
        }
        schemaUpdateTask?.cancel()
        schemaUpdateGeneration &+= 1
        let generation = schemaUpdateGeneration
        schemaUpdateTask = Task { [weak self] in
            defer {
                if let self, self.schemaUpdateGeneration == generation {
                    self.schemaUpdateTask = nil
                }
            }
            do {
                try await Task.sleep(for: .seconds(0.1))
                try Task.checkCancellation()
            } catch is CancellationError {
                AppDiagnostics.configuration.info("Scheduled schema update cancelled")
                return
            } catch {
                AppDiagnostics.configuration.logError(error, context: "Waiting to apply schema update")
                return
            }
            guard let self else {
                AppDiagnostics.configuration.warning("Scheduled schema update lost its interpretation module")
                return
            }
            guard self.isCurrentSchemaUpdate(generation) else {
                AppDiagnostics.configuration.info("Discarding a stale scheduled schema update; generation=\(generation)")
                return
            }
            await self.applySchemas(generation: generation)
        }
    }

    /// Immediately updates the schemas used by the interpretation module.
    @MainActor
    func updateSchemas() async {
        AppDiagnostics.configuration.notice("Immediate schema update requested")
        schemaUpdateTask?.cancel()
        schemaUpdateTask = nil
        schemaUpdateGeneration &+= 1
        await applySchemas(generation: schemaUpdateGeneration)
    }

    @MainActor
    private func applySchemas(generation: Int) async {
        guard isCurrentSchemaUpdate(generation) else {
            AppDiagnostics.configuration.info("Skipping a stale schema update; generation=\(generation)")
            return
        }
        let studyID = currentStudy?.study.id
        let singleResourceSchema = self.singleResourceSchema
        let multipleResourceSchema = self.multipleResourceSchema
        let summarizePrompt = currentStudy?.study.summarizeSingleResourcePrompt ?? .summarizeSingleFHIRResourceDefaultPrompt
        let multipleResourcePrompt = currentStudy?.study.interpretMultipleResourcesPrompt
            ?? .interpretMultipleResourcesDefaultPrompt
        AppDiagnostics.configuration.notice("""
            Applying inference schemas; generation=\(generation); hasStudy=\(studyID != nil); \
            study=\(studyID ?? "none", privacy: .public); model=\(String(describing: self.openAIModel), privacy: .public)
            """)
        await resourceSummarizer.update(llmSchema: singleResourceSchema, summarizationPrompt: summarizePrompt)
        guard isCurrentSchemaUpdate(generation) else {
            AppDiagnostics.configuration.info("Schema update superseded after resource summarizer update; generation=\(generation)")
            return
        }
        await singleResourceInterpreter.update(llmSchema: singleResourceSchema, interpretationPrompt: .interpretSingleFHIRResource)
        guard isCurrentSchemaUpdate(generation) else {
            AppDiagnostics.configuration.info("Schema update superseded after resource interpreter update; generation=\(generation)")
            return
        }
        multipleResourceInterpreter.changeLLMSchema(
            to: multipleResourceSchema,
            using: multipleResourcePrompt
        )
        AppDiagnostics.configuration.notice(
            "Inference schemas applied; generation=\(generation); study=\(studyID ?? "none", privacy: .public)"
        )
    }

    @MainActor
    private func isCurrentSchemaUpdate(_ generation: Int) -> Bool {
        !Task.isCancelled && schemaUpdateGeneration == generation
    }
}
