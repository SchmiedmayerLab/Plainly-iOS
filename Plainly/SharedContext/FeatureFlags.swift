//
// This source file is part of the Plainly iOS project
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

    /// Disables clinical health record access for tests that do not exercise Health Records.
    static let disableHealthRecords = CommandLine.arguments.contains("--disableHealthRecords")

    /// Whether the app disable its firebase integration.
    ///
    /// - Note: if present, this option will take precedence over ``useFirebaseEmulator``.
    static let disableFirebase = CommandLine.arguments.contains("--disableFirebase")
}
