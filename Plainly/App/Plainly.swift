//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import Spezi
import SpeziFoundation
import SwiftUI


@main
struct Plainly: App {
    nonisolated static let mode: AppLaunchMode = {
        let argv = CommandLine.arguments
        return argv.firstIndex(of: "--mode")
            .flatMap { argv[safe: $0 + 1] }
            .flatMap { AppLaunchMode(rawValue: $0) }
        ?? AppConfigFile.current().appLaunchMode
    }()
    
    @UIApplicationDelegateAdaptor(PlainlyDelegate.self) var appDelegate
    @LocalPreference(.onboardingFlowComplete) private var didCompleteOnboarding

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                CreateEnrollmentQRCodeSheet()
            } else {
                RootView()
                    .overlay {
                        OnboardingSheet(didComplete: $didCompleteOnboarding)
                    }
                    .spezi(appDelegate)
            }
        }
    }

    init() {
        let preferences = LocalPreferencesStore.standard
        if FeatureFlags.showOnboarding {
            preferences[.onboardingFlowComplete] = false
        } else if FeatureFlags.skipOnboarding {
            preferences[.onboardingFlowComplete] = true
        }
    }
}
