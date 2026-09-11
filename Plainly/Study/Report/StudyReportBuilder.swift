//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import struct ModelsR4.QuestionnaireResponse
import PlainlyShared


/// Assembles a session's report from what the app knows: the study, its answers, and the health records.
///
/// Both ends of a session use it. A chat that finishes adds its timeline; a screening that stops the study
/// before the chat reports the questionnaire alone, with an empty timeline.
@MainActor
struct StudyReportBuilder {
    private let interpretationModule: FHIRInterpretationModule

    init(interpretationModule: FHIRInterpretationModule) {
        self.interpretationModule = interpretationModule
    }

    /// Writes the report to a temporary file whose name is the study's, ready for upload.
    func writeReport(
        for inProgressStudy: InProgressStudy,
        initialQuestionnaireResponse: QuestionnaireResponse?,
        startTime: Date,
        endTime: Date = .now,
        timeline: [StudyReport.TimelineEvent] = []
    ) async throws -> URL {
        let study = inProgressStudy.study
        let report = StudyReport(
            metadata: .init(
                studyID: study.id,
                startTime: startTime,
                endTime: endTime,
                userInfo: inProgressStudy.userInfo,
                llmConfig: .init(model: study.llmModel)
            ),
            initialQuestionnaireResponse: initialQuestionnaireResponse,
            fhirResources: await fhirResources(),
            timeline: timeline
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("survey_report_\(study.id.lowercased()).json")
        try data.write(to: url)
        return url
    }

    private func fhirResources() async -> StudyReport.FHIRResources {
        let interpreter = interpretationModule.multipleResourceInterpreter
        let summarizer = interpretationModule.resourceSummarizer
        let llmRelevantResources = interpreter.fhirStore.llmRelevantResources
            .map { resource in
                StudyReport.FullFHIRResource(resource.versionedResource)
            }
        let allResources = await interpreter.fhirStore.allResources.mapAsync { resource in
            let summary = await summarizer.cachedSummary(forResource: resource)
            return StudyReport.PartialFHIRResource(
                id: resource.id,
                resourceType: resource.resourceType,
                displayName: resource.displayName,
                dateDescription: resource.date?.description,
                summary: summary?.description
            )
        }
        return StudyReport.FHIRResources(
            llmRelevantResources: FeatureFlags.exportRawJSONFHIRResources ? llmRelevantResources : [],
            allResources: allResources
        )
    }
}
