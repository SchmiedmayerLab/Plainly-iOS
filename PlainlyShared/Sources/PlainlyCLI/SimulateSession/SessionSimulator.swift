//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import ArgumentParser
import Foundation
@_spi(APISupport) import Grove
import GroveFHIR
import GroveHealthKit
import GroveLLM
import GroveLLMOpenAI
import OpenAPIRuntime
import PlainlyShared


struct SessionSimulator: ~Copyable {
    private let config: SimulatedSessionConfig
    private let runIdx: Int
    private let grove: Grove
    private let fhirStore: FHIRStore
    private let coordinator: SessionCoordinator
    private let interpreter: FHIRMultipleResourceInterpreter
    private let resourceSummarizer: FHIRResourceSummarizer

    var sessionDesc: String {
        "\(config.study.id) / \(config.bundle.singlePatient?.fullName ?? config.bundleInputName) @ \(config.model) (\(runIdx + 1)/\(config.numberOfRuns))"
    }

    @MainActor
    init(config: SimulatedSessionConfig, runIdx: Int) throws {
        self.config = config
        self.runIdx = runIdx
        grove = try Grove(from: Self.groveConfig(for: config))
        coordinator = grove.module(SessionCoordinator.self)! // swiftlint:disable:this force_unwrapping
        fhirStore = coordinator.fhirStore
        interpreter = coordinator.multipleResourceInterpreter
        resourceSummarizer = coordinator.resourceSummarizer
    }
    
    @concurrent
    consuming func run() async throws -> StudyReport {
        // start (& stop) service modules
        let groveService = Task { [grove] in
            await grove.run()
        }
        defer {
            groveService.cancel()
        }
        return try await _run()
    }
    
    private consuming func _run() async throws -> StudyReport {
        let startTime = Date()
        await fhirStore.removeAllResources()
        await fhirStore.load(bundle: config.bundle)
        await coordinator.prepareForUse()
        for question in config.userQuestions {
            await MainActor.run {
                interpreter.llmSession.context.append(userMessage: question)
            }
            _ = try await interpreter.generateAssistantResponse()
        }
        let endTime = Date()
        var userInfo = ["bundle": self.config.bundleInputName]
        if let comment = config.comment {
            userInfo["comment"] = comment
        }
        return StudyReport(
            metadata: .init(
                studyID: config.study.id,
                startTime: startTime,
                endTime: endTime,
                userInfo: userInfo,
                llmConfig: .init(model: config.model)
            ),
            initialQuestionnaireResponse: nil, // (obviously) not supported
            fhirResources: await studyReportFHIRResources(),
            timeline: await studyReportTimeline()
        )
    }
    
    @MainActor
    private func studyReportFHIRResources() async -> StudyReport.FHIRResources {
        let llmRelevantResources = fhirStore.llmRelevantResources
            .map { StudyReport.FullFHIRResource($0.versionedResource) }
        let allResources = await fhirStore.allResources.mapAsync { [resourceSummarizer] resource in
            let summary = await resourceSummarizer.cachedSummary(forResource: resource)
            return StudyReport.PartialFHIRResource(
                id: resource.id,
                resourceType: resource.resourceType,
                displayName: resource.displayName,
                dateDescription: resource.date?.description,
                summary: summary?.description
            )
        }
        return .init(
            llmRelevantResources: llmRelevantResources,
            allResources: allResources
        )
    }
    
    @MainActor
    private func studyReportTimeline() -> [StudyReport.TimelineEvent] {
        interpreter.llmSession.context.compactMap { entity in
            guard let message = entity.studyReportChatMessage else {
                return nil
            }
            return .chatMessage(message)
        }
    }
}


extension SessionSimulator {
    private actor FakeStandard: Standard, HealthKitConstraint {
        func handleNewSamples<Sample>(
            _ addedSamples: some Collection<Sample> & Sendable,
            ofType sampleType: SampleType<Sample>
        ) {}
        
        func handleDeletedObjects<Sample>(
            _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
            ofType sampleType: SampleType<Sample>
        ) {}
    }
    
    @MainActor
    private static func groveConfig(for config: SimulatedSessionConfig) throws -> GroveConfiguration {
        let middlewares: [any ClientMiddleware]
        switch config.service {
        case .firebase:
            guard let firebaseConfig = firebaseConfigFromEnvironment() else {
                throw ValidationError("GOOGLE_CREDENTIALS_PLIST environment variable must be set when using the 'Firebase' service.")
            }
            middlewares = [
                FirebaseChatInterceptor(firebaseConfig: firebaseConfig, study: config.study)
            ]
        case .firebaseEmulator:
            middlewares = [
                FirebaseChatInterceptor(
                    firebaseConfig: emulatorConfigFromEnvironment(),
                    study: config.study
                )
            ]
        }
        return GroveConfiguration(standard: FakeStandard()) {
            FHIRStore()
            SessionCoordinator(config: .init(
                model: config.model,
                resourceLimit: 1000,
                summarizeSingleResourcePrompt: config.summarizeSingleResourcePrompt,
                systemPrompt: config.systemPrompt
            ))
            LLMRunner {
                // The interceptor reroutes every request to the Firebase chat function, which holds
                // the inference credentials, so the platform itself never authenticates.
                LLMOpenAIPlatform(configuration: .init(
                    authToken: .none,
                    apiMode: .fixed(.responses),
                    streamingFallback: false,
                    concurrentStreams: 100,
                    retryPolicy: .attempts(3),
                    middlewares: middlewares
                ))
            }
        }
    }

    /// Loads a `FirebaseConfig` from the `GOOGLE_CREDENTIALS_PLIST` environment variable.
    /// Returns `nil` when the variable is unset or the file cannot be parsed.
    private static func firebaseConfigFromEnvironment() -> FirebaseConfig? {
        guard let plistPath = ProcessInfo.processInfo.environment["GOOGLE_CREDENTIALS_PLIST"] else {
            return nil
        }
        let region = ProcessInfo.processInfo.environment["FIREBASE_REGION"]
        return try? FirebaseConfig(contentsOfFile: plistPath, region: region)
    }

    /// Builds a `FirebaseConfig` that routes all traffic to the local Firebase emulator suite.
    ///
    /// Reads the following environment variables:
    /// - `FIREBASE_AUTH_EMULATOR_HOST` — auth emulator address (default: `localhost:9099`)
    /// - `FIREBASE_FUNCTIONS_EMULATOR_HOST` — functions emulator address (default: `localhost:5001`)
    /// - `FIREBASE_REGION` — Firebase region (default: `us-central1`)
    /// - `FIREBASE_PROJECT_ID` — project ID override used when `GOOGLE_CREDENTIALS_PLIST` is not
    ///   set (default: `demo-project`)
    ///
    /// If `GOOGLE_CREDENTIALS_PLIST` is set, the real project credentials (API key and project ID)
    /// are used; otherwise placeholder values are substituted so the emulator can be used without
    /// any credentials file.
    private static func emulatorConfigFromEnvironment() -> FirebaseConfig {
        let env = ProcessInfo.processInfo.environment
        let base = firebaseConfigFromEnvironment()
        let projectID = base?.projectID ?? env["FIREBASE_PROJECT_ID"] ?? "demo-project"
        return FirebaseConfig(
            apiKey: base?.apiKey ?? "A00000000000000000000000000000000000000",
            projectID: projectID,
            region: env["FIREBASE_REGION"],
            authEmulatorAddress: env["FIREBASE_AUTH_EMULATOR_HOST"] ?? "localhost:9099",
            functionsEmulatorAddress: env["FIREBASE_FUNCTIONS_EMULATOR_HOST"] ?? "localhost:5001"
        )
    }
}
