//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import FirebaseAuth
import FirebaseStorage
import Foundation
import PlainlyShared
import Spezi
import SpeziFirebaseAccount


@MainActor
final class FirebaseUpload: Module, EnvironmentAccessible, Sendable {
    @Dependency(FirebaseAccountService.self) private var accountService
    
    func configure() {
        Task {
            do {
                if FeatureFlags.useFirebaseEmulator {
                    try? await accountService.logout()
                }
                try await accountService.signUpAnonymously()
            } catch {
                AppDiagnostics.firebase.logError(error, context: "Firebase anonymous authentication")
            }
        }
    }
    
    func uploadReport(at url: URL, for study: Study) async throws {
        let correlationID = AppDiagnostics.correlationID()
        guard !FeatureFlags.useFirebaseMockUploadError else {
            throw NSError(domain: "edu.stanford.plainly", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Simulated report upload failure"
            ])
        }
        guard let userId = Auth.auth().currentUser?.uid else {
            AppDiagnostics.report.fault("""
                Report upload cannot start because Firebase has no authenticated user; \
                correlation=\(correlationID, privacy: .public); study=\(study.id, privacy: .public)
                """)
            throw NSError(domain: "edu.stanford.plainly", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unable to upload: failed to find user"
            ])
        }
        let storageRef = Storage.storage().reference(withPath: "/studies/\(study.id)/users/\(userId)/\(UUID().uuidString).json")
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        do {
            _ = try await storageRef.putFileAsync(from: url, metadata: metadata)
        } catch {
            AppDiagnostics.report.logError(error, context: "Report upload", correlationID: correlationID)
            throw error
        }
    }
}
