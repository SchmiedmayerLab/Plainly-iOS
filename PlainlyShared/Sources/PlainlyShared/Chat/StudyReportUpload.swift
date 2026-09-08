//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Names uploaded reports using their study, optional participant ID, and upload time.
public enum StudyReportUpload {
    private struct Metadata: Decodable {
        let userInfo: [String: String]
    }

    private struct Report: Decodable {
        let metadata: Metadata
    }

    /// Places all participants' reports directly in their study's folder.
    ///
    /// Reads the participant ID from the report itself so retained reports keep their enrollment
    /// information when retried. The timestamp describes this upload attempt, in UTC; the suffix
    /// distinguishes reports uploaded in the same millisecond.
    public static func storagePath(
        studyID: String,
        reportData: Data,
        uploadedAt: Date = .now,
        identifier: UUID = UUID()
    ) throws -> String {
        let report = try JSONDecoder().decode(Report.self, from: reportData)
        let studyComponent = filenameComponent(studyID)
        var components = [studyComponent]
        if let participantID = report.metadata.userInfo["pid"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !participantID.isEmpty {
            components.append("pid-\(filenameComponent(participantID))")
        }
        let timestamp = uploadedAt.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "-")
        components.append(timestamp)
        components.append(String(identifier.uuidString.prefix(8)).lowercased())
        return "studies/\(studyComponent)/\(components.joined(separator: "_")).json"
    }

    private static func filenameComponent(_ value: String) -> String {
        // Preserve ASCII letters, digits, dots, and hyphens. Escape every other UTF-8 byte,
        // including separators and percent signs, without merging distinct identifiers.
        let encodedBytes = value.utf8.map { byte in
            switch byte {
            case 45, 46, 48...57, 65...90, 97...122:
                String(UnicodeScalar(byte))
            default:
                String(format: "%%%02X", byte)
            }
        }
        return encodedBytes.joined()
    }
}
