//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation
public import GroveFHIR
public import GroveLLMOpenAI
private import ModelsR4
private import os


public struct FHIRGetResourceLLMTool: LLMTool {
    private static let logger = Logger(subsystem: "edu.stanford.plainly.fhir", category: "PlainlyFHIRLLM")
    
    /// The name the model calls this tool by, which is also how Plainly's transport recognises a request
    /// as belonging to the participant's chat rather than to one of its own summarizing prompts.
    public static let toolName = "get_resources"

    public let name = Self.toolName
    
    private let fhirStore: FHIRStore
    private let resourceSummarizer: FHIRResourceSummarizer
    private let forceSummaryReload: Bool
    
    @Parameter var resourceCategories: [String]
    
    @MainActor
    public init(
        fhirStore: FHIRStore,
        resourceSummarizer: FHIRResourceSummarizer,
        resourceCountLimit: Int,
        forceSummaryReload: Bool = false
    ) {
        self.fhirStore = fhirStore
        self.resourceSummarizer = resourceSummarizer
        self.forceSummaryReload = forceSummaryReload
        let resourceIdentifiers = Self.resourceIdentifierEnum(
            Array(fhirStore.allResourcesFunctionCallIdentifier),
            limit: resourceCountLimit
        )
        _resourceCategories = Parameter(
            description: """
                Pass in one or more identifiers that you want to access.
                It is possible that multiple titles apply to the users's question (e.g for multiple medications).
                You can also request a larger set of FHIR resources by, e.g., just stating the resource type but this might not include all relevant resources to avoid exceeding the token limit.
                Ensure that you request the most recent information to get a good overview of the user's current health status.
                Today’s date is \(FHIRResource.functionCallIdentifierDateFormatter.string(from: .now)).
                """,
            enum: resourceIdentifiers,
            minItems: 1,
            maxItems: resourceCountLimit,
            uniqueItems: true
        )
    }

    // `nil` intentionally omits the JSON Schema enum, while an empty array produces an invalid schema.
    // swiftlint:disable:next discouraged_optional_collection
    static func resourceIdentifierEnum(_ identifiers: [String], limit: Int) -> [String]? {
        let limitedIdentifiers = Array(identifiers.suffix(limit))
        return limitedIdentifiers.isEmpty ? nil : limitedIdentifiers
    }
    
    
    private static func filterFittingResources(_ fittingResources: some Collection<FHIRResource>) -> [FHIRResource] {
        if fittingResources.count > 64 {
            fittingResources.lazy.sorted(by: { $0.date ?? .distantPast < $1.date ?? .distantPast }).suffix(64)
        } else {
            Array(fittingResources)
        }
    }
    
    
    public func execute() async throws -> String? {
        do {
            let output = try await processResourceCategories(resourceCategories)
            return output.joined(separator: "\n\n")
        } catch {
            let nsError = error as NSError
            let typeName = String(reflecting: type(of: error))
            let description = nsError.localizedDescription
            Self.logger.error("""
                FHIR resource tool call failed; type=\(typeName, privacy: .public); \
                domain=\(nsError.domain, privacy: .public); code=\(nsError.code); \
                descriptionHash=\(description, privacy: .private(mask: .hash))
                """)
            throw error
        }
    }
    
    
    private func processResourceCategories(_ resourceCategories: [String]) async throws -> [String] {
        var functionOutput: [String] = []
        try await withThrowingTaskGroup(of: [String].self) { group in
            for resourceCategory in resourceCategories {
                group.addTask {
                    try await self.processResourceCategory(resourceCategory)
                }
            }
            for try await result in group {
                functionOutput.append(contentsOf: result)
            }
        }
        return functionOutput
    }
    
    
    private func processResourceCategory(_ resourceCategory: String) async throws -> [String] {
        var fittingResources = await Array(fhirStore.llmRelevantResources(filteredBy: resourceCategory))
        guard !fittingResources.isEmpty else {
            return [String(localized: "The medical record does not include any FHIR resources for the search term \(resourceCategory).")]
        }
        fittingResources = Self.filterFittingResources(fittingResources)
        return try await summarizeFHIRResources(fittingResources, resourceCategory: resourceCategory)
    }
    
    
    private func summarizeFHIRResources(_ resources: [FHIRResource], resourceCategory: String) async throws -> [String] {
        var summaries: [String] = []
        try await withThrowingTaskGroup(of: String.self) { group in
            for resource in resources {
                group.addTask {
                    try await self.summarizeFHIRResource(resource, resourceCategory: resourceCategory)
                }
            }
            for try await summary in group {
                summaries.append(summary)
            }
        }
        return summaries
    }
    
    
    private func summarizeFHIRResource(_ resource: FHIRResource, resourceCategory: String) async throws -> String {
        let summary = try await resourceSummarizer.summarize(resource: resource, forceReload: forceSummaryReload)
        return String(localized: "This is the summary of the requested \(resourceCategory):\n\n\(summary.description)")
    }
}


extension FHIRGetResourceLLMTool {
    // swiftlint:disable:next missing_docs
    public var description: String {
        """
            Call this function to request the relevant FHIR health records based on the user's question and conversation context using their FHIR resource identifiers.

            The FHIR resource identifiers are composed of three elements:
            1. The FHIR resource type, e.g., DocumentReference, DiagnosticReport, MedicationRequest, Encounter, Observation, Procedure, Condition, ...
            2. The descriptive title of the FHIR resource.
            3. The date associated with the FHIR resource.

            Use this information to request the most relevant FHIR resources.
            Pass in one or more resource identifiers that you need access to the `resourceCategories` argument.
            You can also request a more extensive set of FHIR resources by only stating the resource type.

            Use the date in the parameter enum cases to identify relevant resources within the correct time window. Aim to request recent FHIR resources.
            Today's date is \(FHIRResource.functionCallIdentifierDateFormatter.string(from: .now)).
            """
    }
}
