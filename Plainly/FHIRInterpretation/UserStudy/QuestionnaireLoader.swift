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
            return questionnaire
        }

        try Task.checkCancellation()
        do {
            let data = try Data(contentsOf: url)
            let fhirQuestionnaire = try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: data)
            try Task.checkCancellation()
            let questionnaire = try SpeziQuestionnaire.Questionnaire(fhirQuestionnaire)
            cache[url] = questionnaire
            return questionnaire
        } catch let error as CancellationError {
            throw error
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Questionnaire loading")
            throw error
        }
    }
}
