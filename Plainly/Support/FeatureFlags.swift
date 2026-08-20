//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


/// A behaviour the Firebase emulator stands in for, so an end-to-end test can drive a path the deployed
/// backend only reaches by failing.
///
/// One scenario at a time: each describes a whole run, and combining two would describe neither.
enum FirebaseMockScenario: String {
    /// The chat function rejects the request before any output.
    case chatError
    /// The chat function fails after its first streamed chunk, leaving a partial answer behind.
    case chatErrorAfterFirstChunk
    /// The gateway refuses streamed Responses requests, so the backend falls back to an unstreamed one.
    case responseStreamingUnsupported
    /// Every turn after the first must continue the one before it rather than replaying the conversation.
    case incrementalResponseState
    /// The model asks for health records before answering, exercising the client-side tool round trip.
    case responseToolCall
}


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

    /// The behaviour the Firebase emulator should stand in for, if any.
    static let firebaseMockScenario: FirebaseMockScenario? = useFirebaseEmulator
        ? value(following: "--firebaseMockScenario").flatMap(FirebaseMockScenario.init(rawValue:))
        : nil

    /// Requests a model other than the one the active study pins.
    ///
    /// Gated on the emulator because the model a study runs on is part of what that study collects. A
    /// development gateway key is rarely entitled to every model a deployment uses, and this is what lets
    /// a study be exercised locally against one it can reach.
    static let llmModelOverride: String? = useFirebaseEmulator ? value(following: "--llmModel") : nil

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

    /// Whether the app answers from the bundled sample patient rather than from Health Records.
    ///
    /// Test mode has no health records to read; the tool-call scenario needs records the model can ask for.
    static var usesSampleHealthRecords: Bool {
        Plainly.mode == .test || firebaseMockScenario == .responseToolCall
    }

    /// The value written after `flag` on the command line, if any.
    private static func value(following flag: String) -> String? {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: flag).flatMap { arguments[safe: $0 + 1] }
    }
}
