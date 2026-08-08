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
                AppDiagnostics.firebase.notice("""
                    Firebase anonymous authentication starting; emulator=\(FeatureFlags.useFirebaseEmulator); \
                    hadExistingUser=\(Auth.auth().currentUser != nil)
                    """)
                if FeatureFlags.useFirebaseEmulator {
                    try? await accountService.logout()
                    AppDiagnostics.firebase.info(
                        "Firebase emulator logout completed; hasCurrentUser=\(Auth.auth().currentUser != nil)"
                    )
                }
                try await accountService.signUpAnonymously()
                AppDiagnostics.firebase.notice(
                    "Firebase anonymous authentication completed; hasCurrentUser=\(Auth.auth().currentUser != nil)"
                )
            } catch {
                AppDiagnostics.firebase.logError(error, context: "Firebase anonymous authentication")
            }
        }
    }
    
    func uploadReport(at url: URL, for study: Study) async throws {
        let correlationID = AppDiagnostics.correlationID()
        guard let userId = Auth.auth().currentUser?.uid else {
            AppDiagnostics.report.fault("""
                Report upload cannot start because Firebase has no authenticated user; \
                correlation=\(correlationID, privacy: .public); study=\(study.id, privacy: .public)
                """)
            throw NSError(domain: "edu.stanford.plainly", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Unable to upload: failed to find user"
            ])
        }
        AppDiagnostics.report.notice("""
            Report upload starting; correlation=\(correlationID, privacy: .public); study=\(study.id, privacy: .public); \
            fileExists=\(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            """)
        let storageRef = Storage.storage().reference(withPath: "/studies/\(study.id)/users/\(userId)/\(UUID().uuidString).json")
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        do {
            _ = try await storageRef.putFileAsync(from: url, metadata: metadata)
            AppDiagnostics.report.notice(
                "Report upload completed; correlation=\(correlationID, privacy: .public); study=\(study.id, privacy: .public)"
            )
        } catch {
            AppDiagnostics.report.logError(error, context: "Report upload", correlationID: correlationID)
            throw error
        }
    }
}
