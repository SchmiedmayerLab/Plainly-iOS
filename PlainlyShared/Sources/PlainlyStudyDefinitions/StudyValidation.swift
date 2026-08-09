//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import PlainlyShared
import SpeziLLMOpenAI


extension Study {
    /// A problem in a study definition that would surface as incorrect behaviour at runtime.
    public enum ValidationIssue: Hashable, Sendable, CustomStringConvertible {
        /// Two studies share an identifier, so `Study.withId(_:)` can only ever resolve one of them.
        case duplicateStudyId(Study.ID)
        /// Two tasks within a study share an identifier, so answers cannot be routed unambiguously.
        case duplicateTaskId(study: Study.ID, task: Study.Task.ID)
        /// The study pins a model that Plainly does not support.
        case unsupportedModel(study: Study.ID, model: String)

        public var description: String {
            switch self {
            case .duplicateStudyId(let id):
                "Multiple studies use the id '\(id)'."
            case let .duplicateTaskId(study, task):
                "Study '\(study)' uses the task id '\(task)' more than once."
            case let .unsupportedModel(study, model):
                "Study '\(study)' uses the unsupported model '\(model)'."
            }
        }
    }

    /// Checks every bundled study for problems that the type system cannot rule out.
    ///
    /// Run by the test suite and by the `export-config` tool, so a malformed study definition fails
    /// before it can be shipped in a `UserStudyConfig.plist`.
    public static func validateAllStudies() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seenStudyIds: Set<Study.ID> = []

        for study in allStudies {
            if !seenStudyIds.insert(study.id).inserted {
                issues.append(.duplicateStudyId(study.id))
            }
            if !OpenAIPlatformDefinition.ModelType.plainlySupportedModels.contains(study.llmModel) {
                issues.append(.unsupportedModel(study: study.id, model: study.llmModel.rawValue))
            }
            var seenTaskIds: Set<Study.Task.ID> = []
            for task in study.tasks where !seenTaskIds.insert(task.id).inserted {
                issues.append(.duplicateTaskId(study: study.id, task: task.id))
            }
        }
        return issues
    }
}
