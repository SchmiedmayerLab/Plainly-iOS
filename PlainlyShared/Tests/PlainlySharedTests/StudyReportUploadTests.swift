//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import PlainlyShared
import Testing


struct StudyReportUploadTests {
    @Test(arguments: ["P042", " \tP042\n"])
    func namesReportFromItsParticipantID(participantID: String) throws {
        let path = try storagePath(userInfo: ["pid": participantID])

        #expect(path == "studies/edu.stanford.plainly.spineAI/edu.stanford.plainly.spineAI_pid-P042_1970-01-01T00-16-40.125Z_a8f39c21.json")
    }

    @Test(arguments: [nil, "", " \t\n"] as [String?])
    func omitsUnavailableParticipantID(participantID: String?) throws {
        var userInfo = ["other": "unrelated metadata"]
        userInfo["pid"] = participantID
        let path = try storagePath(userInfo: userInfo)

        #expect(path == "studies/edu.stanford.plainly.spineAI/edu.stanford.plainly.spineAI_1970-01-01T00-16-40.125Z_a8f39c21.json")
    }

    @Test(arguments: [
        ("A/B", "A%2FB"),
        ("A%2FB", "A%252FB"),
        ("A_B", "A%5FB"),
        ("A-B", "A-B"),
        ("ä", "%C3%A4"),
        ("a", "a")
    ])
    func escapesIdentifiersWithoutLosingTheirIdentity(identifier: String, escaped: String) throws {
        let path = try storagePath(userInfo: ["pid": identifier], studyID: identifier)

        #expect(path == "studies/\(escaped)/\(escaped)_pid-\(escaped)_1970-01-01T00-16-40.125Z_a8f39c21.json")
        #expect(path.split(separator: "/").count == 3)
    }

    @Test
    func sameTimeUploadsCanHaveDistinctSuffixes() throws {
        let firstPath = try storagePath(userInfo: ["pid": "P042"], identifier: "A8F39C21-1111-2222-3333-444444444444")
        let secondPath = try storagePath(userInfo: ["pid": "P042"], identifier: "B9E40D32-1111-2222-3333-444444444444")

        #expect(firstPath != secondPath)
        #expect(firstPath.hasSuffix("_a8f39c21.json"))
        #expect(secondPath.hasSuffix("_b9e40d32.json"))
    }

    @Test
    func rejectsMalformedReportJSON() {
        #expect(throws: DecodingError.self) {
            try StudyReportUpload.storagePath(studyID: "study", reportData: Data("not json".utf8))
        }
    }

    @Test
    @MainActor
    func namesRetainedReportFromItsSavedMetadata() async throws {
        let studyID = "edu.stanford.plainly.spineAI"
        let reportData = try encodedReport(userInfo: ["pid": "P042"], studyID: studyID)
        let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try reportData.write(to: reportURL)
        defer { try? FileManager.default.removeItem(at: reportURL) }

        let path = try await StudyReportUpload.storagePath(
            studyID: studyID,
            reportAt: reportURL,
            uploadedAt: Date(timeIntervalSince1970: 1_000.125),
            identifier: #require(UUID(uuidString: "A8F39C21-1111-2222-3333-444444444444"))
        )

        #expect(path == "studies/edu.stanford.plainly.spineAI/edu.stanford.plainly.spineAI_pid-P042_1970-01-01T00-16-40.125Z_a8f39c21.json")
        #expect(try Data(contentsOf: reportURL) == reportData)
    }

    @Test
    func propagatesReportFileReadFailure() async {
        let missingReportURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")

        await #expect(throws: CocoaError.self) {
            try await StudyReportUpload.storagePath(studyID: "study", reportAt: missingReportURL)
        }
    }

    @Test
    func rejectsCancelledUploadBeforeReadingReport() async {
        let missingReportURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StudyReportUpload.storagePath(studyID: "study", reportAt: missingReportURL)
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func storagePath(
        userInfo: [String: String],
        studyID: String = "edu.stanford.plainly.spineAI",
        identifier: String = "A8F39C21-1111-2222-3333-444444444444"
    ) throws -> String {
        try StudyReportUpload.storagePath(
            studyID: studyID,
            reportData: encodedReport(userInfo: userInfo, studyID: studyID),
            uploadedAt: Date(timeIntervalSince1970: 1_000.125),
            identifier: #require(UUID(uuidString: identifier))
        )
    }

    private func encodedReport(userInfo: [String: String], studyID: String) throws -> Data {
        let report = StudyReport(
            metadata: .init(
                studyID: studyID,
                startTime: Date(timeIntervalSince1970: 100),
                endTime: Date(timeIntervalSince1970: 200),
                userInfo: userInfo,
                llmConfig: .init(model: .gpt4o)
            ),
            initialQuestionnaireResponse: nil,
            fhirResources: .init(llmRelevantResources: [], allResources: []),
            timeline: []
        )
        return try JSONEncoder().encode(report)
    }
}
