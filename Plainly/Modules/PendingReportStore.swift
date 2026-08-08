//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import PlainlyShared
import PlainlyStudyDefinitions
import Spezi


/// Keeps study reports that could not be uploaded and retries them on later launches.
///
/// A session's answers only exist in its report, so a failed upload must not discard it. Reports are
/// written to Application Support, grouped by study, and removed once they reach Firebase Storage.
@MainActor
@Observable
final class PendingReportStore: Module, EnvironmentAccessible, Sendable {
    @ObservationIgnored @Dependency(FirebaseUpload.self) private var uploader

    /// The number of reports still waiting to be uploaded.
    private(set) var pendingCount = 0
    /// Whether an upload attempt is currently running.
    private(set) var isUploading = false

    @ObservationIgnored private let directory = URL.applicationSupportDirectory
        .appending(path: "PendingStudyReports", directoryHint: .isDirectory)


    func configure() {
        pendingCount = pendingReports().count
        Task {
            await uploadPendingReports()
        }
    }

    /// Keeps a report that could not be uploaded, so that a later launch can retry it.
    ///
    /// Reports are stored under a fresh identifier: sessions of the same study share a file name, so
    /// reusing it would let a second failed session overwrite the first.
    func retainForRetry(reportAt url: URL, for study: Study) {
        let destination = directory
            .appending(path: study.id, directoryHint: .isDirectory)
            .appending(path: "\(UUID().uuidString).json", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
            pendingCount = pendingReports().count
        } catch {
            AppDiagnostics.report.logError(error, context: "Retaining study report for a later upload")
        }
    }

    /// Uploads every retained report, keeping the ones that still fail.
    func uploadPendingReports() async {
        let reports = pendingReports()
        guard !reports.isEmpty, !isUploading else {
            pendingCount = reports.count
            return
        }
        isUploading = true
        defer {
            isUploading = false
            pendingCount = pendingReports().count
        }
        for report in reports {
            do {
                try await uploader.uploadReport(at: report.url, for: report.study)
                try FileManager.default.removeItem(at: report.url)
            } catch {
                AppDiagnostics.report.logError(error, context: "Retrying a retained study report")
            }
        }
    }


    /// The retained reports whose study is still known to the app.
    private func pendingReports() -> [(study: Study, url: URL)] {
        guard let studyDirectories = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return studyDirectories.flatMap { studyDirectory -> [(study: Study, url: URL)] in
            guard let study = Study.withId(studyDirectory.lastPathComponent) else {
                AppDiagnostics.report.error(
                    "Retained reports reference the unknown study '\(studyDirectory.lastPathComponent, privacy: .public)'"
                )
                return []
            }
            let reports = (try? FileManager.default.contentsOfDirectory(at: studyDirectory, includingPropertiesForKeys: nil)) ?? []
            return reports.map { (study, $0) }
        }
    }
}
