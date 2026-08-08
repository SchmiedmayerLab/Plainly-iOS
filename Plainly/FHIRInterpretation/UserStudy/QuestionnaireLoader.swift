//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import struct ModelsR4.Questionnaire
import SpeziQuestionnaire
import SpeziQuestionnaireFHIR


actor QuestionnaireLoader {
    static let shared = QuestionnaireLoader()

    private var cache: [URL: SpeziQuestionnaire.Questionnaire] = [:]

    func questionnaire(from url: URL) throws -> SpeziQuestionnaire.Questionnaire {
        if let questionnaire = cache[url] {
            AppDiagnostics.questionnaire.info(
                "Questionnaire cache hit; resource=\(url.lastPathComponent, privacy: .public)"
            )
            return questionnaire
        }

        AppDiagnostics.questionnaire.notice(
            "Questionnaire load started; resource=\(url.lastPathComponent, privacy: .public)"
        )
        try Task.checkCancellation()
        do {
            let data = try Data(contentsOf: url)
            AppDiagnostics.questionnaire.info(
                "Questionnaire resource read; resource=\(url.lastPathComponent, privacy: .public); bytes=\(data.count)"
            )
            let fhirQuestionnaire = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
            try Task.checkCancellation()
            let questionnaire = try SpeziQuestionnaire.Questionnaire(fhirQuestionnaire)
            cache[url] = questionnaire
            AppDiagnostics.questionnaire.notice(
                "Questionnaire load completed; resource=\(url.lastPathComponent, privacy: .public)"
            )
            return questionnaire
        } catch let error as CancellationError {
            AppDiagnostics.questionnaire.info(
                "Questionnaire load cancelled; resource=\(url.lastPathComponent, privacy: .public)"
            )
            throw error
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Questionnaire loading")
            throw error
        }
    }
}
