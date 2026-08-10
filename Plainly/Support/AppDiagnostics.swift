//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog


enum AppDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "edu.stanford.llmonfhir"

    static let configuration = Logger(subsystem: subsystem, category: "Configuration")
    static let healthRecords = Logger(subsystem: subsystem, category: "HealthRecords")
    static let questionnaire = Logger(subsystem: subsystem, category: "Questionnaire")
    static let study = Logger(subsystem: subsystem, category: "Study")
    static let chat = Logger(subsystem: subsystem, category: "Chat")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let firebase = Logger(subsystem: subsystem, category: "Firebase")
    static let report = Logger(subsystem: subsystem, category: "Report")

    static func correlationID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}


extension Logger {
    /// Logs stable error metadata without placing error payloads or localized descriptions in the unified log.
    func logError(_ error: any Error, context: String, correlationID: String? = nil) {
        let nsError = error as NSError
        let typeName = String(reflecting: type(of: error))
        let description = nsError.localizedDescription
        self.error("""
            \(context, privacy: .public) failed; correlation=\(correlationID ?? "none", privacy: .public); \
            type=\(typeName, privacy: .public); domain=\(nsError.domain, privacy: .public); code=\(nsError.code); \
            descriptionHash=\(description, privacy: .private(mask: .hash))
            """)
    }
}
