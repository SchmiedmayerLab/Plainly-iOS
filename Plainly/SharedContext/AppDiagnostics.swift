//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog


enum AppDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "edu.stanford.llmonfhir"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let configuration = Logger(subsystem: subsystem, category: "Configuration")
    static let healthRecords = Logger(subsystem: subsystem, category: "HealthRecords")
    static let questionnaire = Logger(subsystem: subsystem, category: "Questionnaire")
    static let study = Logger(subsystem: subsystem, category: "Study")
    static let chat = Logger(subsystem: subsystem, category: "Chat")
    static let chatTranscript = Logger(subsystem: subsystem, category: "ChatTranscript")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let firebase = Logger(subsystem: subsystem, category: "Firebase")
    static let report = Logger(subsystem: subsystem, category: "Report")

    static let chatSignposter = OSSignposter(subsystem: subsystem, category: "Chat")
    static let networkSignposter = OSSignposter(subsystem: subsystem, category: "Network")

    static func correlationID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    /// Temporarily logs complete diagnostic payloads in chunks small enough to remain readable in Console.
    ///
    /// - Important: The payload is intentionally public and may contain study or health information.
    static func logPublicPayload(_ payload: String, context: String, correlationID: String) {
        let chunks = payload.chunks(maximumCharacterCount: 700)
        if chunks.isEmpty {
            chatTranscript.notice("""
                \(context, privacy: .public); correlation=\(correlationID, privacy: .public); \
                part=0/0; characters=0; payload=<empty>
                """)
            return
        }

        for (index, chunk) in chunks.enumerated() {
            chatTranscript.notice("""
                \(context, privacy: .public); correlation=\(correlationID, privacy: .public); \
                part=\(index + 1)/\(chunks.count); characters=\(chunk.count); payload=\(chunk, privacy: .public)
                """)
        }
    }
}


extension String {
    fileprivate func chunks(maximumCharacterCount: Int) -> [String] {
        var chunks: [String] = []
        var startIndex = startIndex
        while startIndex < endIndex {
            let chunkEndIndex = index(
                startIndex,
                offsetBy: maximumCharacterCount,
                limitedBy: self.endIndex
            ) ?? self.endIndex
            chunks.append(String(self[startIndex..<chunkEndIndex]))
            startIndex = chunkEndIndex
        }
        return chunks
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
