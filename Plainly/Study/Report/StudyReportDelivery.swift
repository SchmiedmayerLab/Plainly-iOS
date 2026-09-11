//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import PlainlyShared


/// Hands a written report to Firebase, and keeps it for a later launch when that fails.
@MainActor
struct StudyReportDelivery {
    private let uploader: FirebaseUpload?
    private let pendingReports: PendingReportStore?

    init(uploader: FirebaseUpload?, pendingReports: PendingReportStore?) {
        self.uploader = uploader
        self.pendingReports = pendingReports
    }

    /// Uploads the report at `url`.
    ///
    /// - Returns: Whether the report reached Firebase. When it did not, the file is retained for a retry;
    ///   when even that fails, it stays where it is, since it holds the only copy of the session's answers.
    func deliver(reportAt url: URL, for study: Study) async -> Bool {
        guard let uploader else {
            return false
        }
        do {
            try await uploader.uploadReport(at: url, for: study)
            try? FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppDiagnostics.report.logError(error, context: "Study report upload")
            do {
                try pendingReports?.retainForRetry(reportAt: url, for: study)
            } catch {
                AppDiagnostics.report.logError(error, context: "Retaining study report for a later upload")
            }
            return false
        }
    }
}
