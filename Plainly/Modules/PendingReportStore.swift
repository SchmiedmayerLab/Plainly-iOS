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
import SpeziFoundation


/// Keeps study reports that could not be uploaded and retries them on later launches.
///
/// A session's answers only exist in its report, so a failed upload must not discard it. Reports are
/// written to Application Support, grouped by study, and removed once they reach Firebase Storage.
@MainActor
@Observable
final class PendingReportStore: Module, EnvironmentAccessible, Sendable {
    /// How long one attempt may run before it is abandoned.
    ///
    /// Without it a stalled upload would hold ``isUploading`` forever and block every later retry.
    private static let uploadTimeout: Duration = .seconds(120)

    @ObservationIgnored @Dependency(FirebaseUpload.self) private var uploader

    /// The number of reports still waiting to be uploaded.
    private(set) var pendingCount = 0
    /// Whether an upload attempt is currently running.
    private(set) var isUploading = false

    @ObservationIgnored private let directory = URL.applicationSupportDirectory
        .appending(path: "PendingStudyReports", directoryHint: .isDirectory)
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    func configure() {
        pendingCount = pendingReports().count
        retryPendingUploads()
    }

    /// Starts an upload attempt unless one is already running.
    ///
    /// An attempt that is in flight is left alone rather than cancelled and restarted: restarting
    /// would discard the progress of an upload that is simply slow, and two attempts reading the same
    /// directory could upload a report twice. A stalled attempt is bounded by ``uploadTimeout``
    /// instead, after which the next trigger starts a fresh one.
    func retryPendingUploads() {
        guard !isUploading else {
            return
        }
        isUploading = true
        let task = Task {
            defer {
                isUploading = false
                pendingCount = pendingReports().count
                uploadTask = nil
            }
            await uploadPendingReports()
        }
        uploadTask = task
        Task {
            // Cancelling a task that already finished is a no-op, so the watchdog needs no result check.
            await withTimeout(of: Self.uploadTimeout) {
                task.cancel()
            }
        }
    }

    /// Cancels an upload attempt that is still running; the reports it did not reach stay retained.
    func cancelPendingUploads() {
        uploadTask?.cancel()
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
    private func uploadPendingReports() async {
        for report in pendingReports() {
            guard !Task.isCancelled else {
                return
            }
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
