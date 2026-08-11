//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation


/// A collection of feature flags for the Plainly app.
enum FeatureFlags {
    /// Skips the onboarding flow to enable easier development of features in the application and to allow UI tests to skip the onboarding flow.
    static let skipOnboarding = CommandLine.arguments.contains("--skipOnboarding")
    
    /// Always show the onboarding when the application is launched. Makes it easy to modify and test the onboarding flow without the need to manually remove the application or reset the simulator.
    static let showOnboarding = CommandLine.arguments.contains("--showOnboarding")
    
    /// Export the raw JSON for all FHIR resources in the export for the user study
    static let exportRawJSONFHIRResources = CommandLine.arguments.contains("--exportRawJSONFHIRResources")
    
    /// Whether the app should use a local firebase emulator
    static let useFirebaseEmulator = CommandLine.arguments.contains("--useFirebaseEmulator")

    /// Makes the Firebase emulator return a production-shaped chat error for end-to-end UI testing.
    static let useFirebaseMockChatError = useFirebaseEmulator && CommandLine.arguments.contains("--useFirebaseMockChatError")

    /// Makes the Firebase emulator fail after its first chat chunk to test terminal result validation.
    static let useFirebaseMockChatErrorAfterChunk =
        useFirebaseEmulator && CommandLine.arguments.contains("--useFirebaseMockChatErrorAfterChunk")

    /// Fails study report uploads so end-to-end tests can exercise the retry on a later launch.
    static let useFirebaseMockUploadError =
        useFirebaseEmulator && CommandLine.arguments.contains("--useFirebaseMockUploadError")

    /// Delays the anonymous sign-in so tests can prove uploads wait for it rather than racing it.
    static let useSlowFirebaseAuth =
        useFirebaseEmulator && CommandLine.arguments.contains("--useSlowFirebaseAuth")

    /// Discards retained study reports at launch so each end-to-end test starts without earlier sessions.
    ///
    /// Gated on the emulator because retained reports hold the only copy of a participant's answers.
    static let resetRetainedReports =
        useFirebaseEmulator && CommandLine.arguments.contains("--resetRetainedReports")

    /// Disables clinical health record access for tests that do not exercise Health Records.
    static let disableHealthRecords = CommandLine.arguments.contains("--disableHealthRecords")

    /// Whether the app disable its firebase integration.
    ///
    /// - Note: if present, this option will take precedence over ``useFirebaseEmulator``.
    static let disableFirebase = CommandLine.arguments.contains("--disableFirebase")
}
