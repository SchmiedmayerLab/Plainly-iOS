//
// This source file is part of the Stanford AI Health Literacy iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import AIHealthLiteracyShared
import Spezi
import SwiftUI


@main
struct AIHealthLiteracy: App {
    nonisolated static let mode: AppLaunchMode = {
        let argv = CommandLine.arguments
        return argv.firstIndex(of: "--mode")
            .flatMap { argv[safe: $0 + 1] }
            .flatMap { AppLaunchMode(rawValue: $0) }
        ?? AppConfigFile.current().appLaunchMode
    }()
    
    @UIApplicationDelegateAdaptor(AIHealthLiteracyDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                CreateEnrollmentQRCodeSheet()
            } else {
                RootView()
                    .testingSetup()
                    .spezi(appDelegate)
            }
        }
    }
}
