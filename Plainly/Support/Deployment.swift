//
// This source file is part of the Plainly based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared


enum Deployment {
    /// Simulators and Firebase projects whose id ends in `-dev` get a study's previews; releases do not.
    static let isDevelopment: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        let config = FeatureFlags.useFirebaseEmulator ? .emulator : AppConfigFile.current().firebaseConfig
        return (config?.asNSDictionary()["PROJECT_ID"] as? String)?.hasSuffix("-dev") == true
        #endif
    }()
}
