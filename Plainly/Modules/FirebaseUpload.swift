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

    /// Retained so an upload can wait for the anonymous sign-in instead of racing it.
    private var authenticationTask: Task<Void, Never>?

    func configure() {
        // Clearing the session synchronously guarantees that no user exists once the retained reports
        // are retried, which is the gap the delay below then holds open.
        if FeatureFlags.useSlowFirebaseAuth {
            try? Auth.auth().signOut()
        }
        authenticationTask = Task {
            do {
                if FeatureFlags.useFirebaseEmulator {
                    try? await accountService.logout()
                }
                if FeatureFlags.useSlowFirebaseAuth {
                    try? await Task.sleep(for: .seconds(5))
                }
                try await accountService.signUpAnonymously()
            } catch {
                AppDiagnostics.firebase.logError(error, context: "Firebase anonymous authentication")
            }
        }
    }
    
    func uploadReport(at url: URL, for study: Study) async throws {
        let correlationID = AppDiagnostics.correlationID()
        // A report retained from an earlier launch is retried during configuration, which would
        // otherwise run before the anonymous sign-in that the upload depends on.
        await authenticationTask?.value
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
